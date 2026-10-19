import Foundation
import Combine
@preconcurrency import CoreBluetooth

struct DiscoveredHeadphone: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertisesBmap: Bool
}

/// Core Bluetooth connection to the BMAP LE connection-oriented channel advertised by Bose.
/// A GATT connection alone is not a working control connection: the [0.1] probe must answer.
@MainActor
final class HeadphoneBluetooth: NSObject, ObservableObject {
    @Published private(set) var status = "Not connected"
    @Published private(set) var devices: [DiscoveredHeadphone] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false
    @Published private(set) var log: [String] = []
    var onPacket: ((BmapPacket) -> Void)?
    var connectedDeviceID: UUID? { selected?.identifier }

    static let service = CBUUID(string: "FEBE")
    static let psmCharacteristic = CBUUID(string: "089CA084-6721-4419-9003-5E14D5AB587D")

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var channel: CBL2CAPChannel?
    private var frameBuffer = BmapFrameBuffer()
    private var outgoing: [Data] = []
    private var outputOffset = 0
    private var lastFrameSent = Date.distantPast
    private var timeout: Timer?
    private var scanTimeout: Timer?
    private var writeTimer: Timer?
    private var wantsScan = false

    func scan() {
        #if targetEnvironment(simulator)
        status = "Bluetooth hardware needs a physical iPhone. Use Demo to explore in Simulator."
        appendLog("Simulator: real headphone discovery requires an iPhone.")
        #else
        guard !isConnected, selected == nil else { return }
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            updateBluetoothStatus()
        }
        #endif
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
        scanTimeout?.invalidate(); scanTimeout = nil
        isScanning = false
    }

    func connect(_ device: DiscoveredHeadphone) {
        guard let central, central.state == .poweredOn, let peripheral = peripherals[device.id] else {
            status = "Scan for nearby headphones before connecting."
            return
        }
        disconnect()
        stopScan()
        selected = peripheral
        peripheral.delegate = self
        status = "Connecting to \(device.name)…"
        appendLog("Connecting to the selected Bose device.")
        central.connect(peripheral, options: nil)
        armTimeout(seconds: 15, message: "Connection timed out. Keep the headphones nearby and close other control apps.")
    }

    func disconnect() {
        let peripheral = selected
        selected = nil
        closeChannel()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        status = "Not connected"
    }

    /// Acceptance means queued for transport, not acknowledged by the headphones.
    /// Features must update hardware state only when a STATUS/RESULT packet arrives.
    func send(_ packet: BmapPacket) throws {
        try BmapWriteGuard.check(packet)
        guard isConnected, channel != nil else { throw BmapFailure.unavailable("Connect to a verified headphone control channel first.") }
        try enqueue(packet)
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        devices.removeAll(); peripherals.removeAll()
        status = "Looking for Bose headphones…"
        isScanning = true
        // Unfiltered foreground scanning also discovers renamed Bose peripherals. Results are
        // restricted by advertised service/name; opening an unknown GATT service is never guessed.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        central.registerForConnectionEvents(options: [.serviceUUIDs: [Self.service]])
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.service]) {
            record(peripheral, name: peripheral.name ?? "Bose headphones", rssi: 0, bmap: true)
        }
        scanTimeout?.invalidate()
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stopScan()
                if self.selected == nil {
                    self.status = self.devices.isEmpty ? "No compatible Bose advertisements found. Wake the headphones and try again." : "Choose your headphones to connect."
                }
            }
        }
    }

    private func record(_ peripheral: CBPeripheral, name: String, rssi: Int, bmap: Bool) {
        peripherals[peripheral.identifier] = peripheral
        let device = DiscoveredHeadphone(id: peripheral.identifier, name: name, rssi: rssi, advertisesBmap: bmap)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { $0.rssi > $1.rssi }
    }

    private func updateBluetoothStatus() {
        guard let central else { return }
        switch central.state {
        case .poweredOn: status = "Bluetooth is ready."
        case .poweredOff: status = "Turn on Bluetooth in Settings to find headphones."
        case .unauthorized: status = "Allow Bluetooth for Earshot in Settings."
        case .unsupported: status = "Bluetooth control is unavailable on this device."
        case .resetting: status = "Bluetooth is restarting. Try again shortly."
        case .unknown: status = "Checking Bluetooth…"
        @unknown default: status = "Bluetooth is unavailable."
        }
    }

    private func armTimeout(seconds: TimeInterval, message: String) {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fail(message) }
        }
    }

    private func fail(_ message: String) {
        disconnect()
        status = message
        appendLog(message)
    }

    private func closeChannel() {
        isConnected = false
        timeout?.invalidate(); timeout = nil
        writeTimer?.invalidate(); writeTimer = nil
        if let channel {
            channel.inputStream.delegate = nil
            channel.outputStream.delegate = nil
            channel.inputStream.close(); channel.outputStream.close()
            channel.inputStream.remove(from: .main, forMode: .common)
            channel.outputStream.remove(from: .main, forMode: .common)
        }
        channel = nil
        outgoing.removeAll(); outputOffset = 0
        frameBuffer.reset()
    }

    private func enqueue(_ packet: BmapPacket) throws {
        try BmapWriteGuard.check(packet)
        guard outgoing.count < 256 else { throw BmapFailure.unavailable("The headphone command queue is full. Wait for the current changes to finish.") }
        outgoing.append(try packet.encode())
        appendLog("→ \(packetLog(packet))")
        flushOutput()
    }

    private func flushOutput() {
        guard let stream = channel?.outputStream, stream.hasSpaceAvailable, !outgoing.isEmpty else { return }
        // The Android transport spaces requests too. Preserve whole-frame order even on partial writes.
        guard outputOffset > 0 || Date().timeIntervalSince(lastFrameSent) >= 0.08 else { return }
        let data = outgoing[0]
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return stream.write(base.advanced(by: outputOffset), maxLength: data.count - outputOffset)
        }
        if written < 0 { fail(stream.streamError?.localizedDescription ?? "The headphone output stream failed."); return }
        outputOffset += written
        if outputOffset == data.count {
            outgoing.removeFirst(); outputOffset = 0; lastFrameSent = Date()
        }
    }

    private func receive(_ data: Data) {
        let oldDesyncCount = frameBuffer.desyncCount
        let packets = frameBuffer.feed(data)
        if frameBuffer.desyncCount > oldDesyncCount { fail("The control channel returned invalid BMAP data. Reconnect to try again."); return }
        for packet in packets {
            guard packet.operation.isDeviceResponse else { continue }
            appendLog("← \(packetLog(packet))")
            if !isConnected {
                guard packet.answersLivenessProbe else { continue }
                isConnected = true
                timeout?.invalidate(); timeout = nil
                status = "Connected to \(selected?.name ?? "Bose headphones")"
                appendLog("BMAP liveness verified over LE L2CAP.")
            }
            onPacket?(packet)
        }
    }

    private func appendLog(_ message: String) {
        log.append(message)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private func packetLog(_ packet: BmapPacket) -> String {
        // Paired-source names/addresses, custom names, serials, keys and mode names must not
        // be copied into a diagnostics report. Keep the address and frame length for debugging.
        let privatePayload = packet.block == 4 || packet.block == 18
            || packet.address == BmapAddress(1, 2) || packet.address == BmapAddress(31, 6)
            || packet.block == 0 && [7, 9, 12].contains(packet.function)
        return privatePayload ? "\(packet.address) \(packet.operation) <\(packet.payload.count) bytes redacted>" : packet.description
    }
}

extension HeadphoneBluetooth: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, wantsScan { beginScan() }
        else {
            if central.state != .poweredOn {
                // The manager may report unknown/resetting before it is ready. Keep the scan
                // intent so its subsequent poweredOn callback can actually begin discovery.
                let resumeScan = wantsScan && (central.state == .unknown || central.state == .resetting)
                stopScan(); disconnect(); wantsScan = resumeScan
            }
            updateBluetoothStatus()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown Bluetooth device"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let bmap = services.contains(Self.service)
        let knownName = name.localizedCaseInsensitiveContains("bose") || name.localizedCaseInsensitiveContains("quietcomfort")
        guard bmap || knownName else { return }
        record(peripheral, name: name, rssi: RSSI.intValue, bmap: bmap)
    }

    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        if event == .peerConnected, isScanning {
            record(peripheral, name: peripheral.name ?? "Bose headphones", rssi: 0, bmap: true)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard selected?.identifier == peripheral.identifier else { return }
        status = "Discovering headphone control service…"
        // Find the known PSM characteristic even if a firmware moved it to a different service.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        fail(error?.localizedDescription ?? "The headphones could not connect.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        selected = nil; closeChannel()
        status = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Headphones disconnected."
        appendLog(status)
    }
}

extension HeadphoneBluetooth: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error { fail(error.localizedDescription); return }
        guard let services = peripheral.services, !services.isEmpty else {
            fail("No control services found. This firmware may expose only an RFCOMM channel, which iOS cannot open directly.")
            return
        }
        for service in services { peripheral.discoverCharacteristics([Self.psmCharacteristic], for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error { appendLog("Service discovery: \(error.localizedDescription)"); return }
        if let characteristic = service.characteristics?.first(where: { $0.uuid == Self.psmCharacteristic }) {
            status = "Reading the Bose LE control channel…"
            peripheral.readValue(for: characteristic)
        } else if peripheral.services?.allSatisfy({ $0.characteristics != nil }) == true,
                  peripheral.services?.contains(where: { $0.characteristics?.contains(where: { $0.uuid == Self.psmCharacteristic }) == true }) == false {
            fail("These headphones do not publish a supported BMAP LE channel. Classic RFCOMM control needs a different accessory interface on iOS.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard selected?.identifier == peripheral.identifier, characteristic.uuid == Self.psmCharacteristic else { return }
        if let error { fail(error.localizedDescription); return }
        guard let data = characteristic.value, let psm = BoseParsers.psm(data) else {
            fail("The Bose service did not provide a valid LE L2CAP channel number."); return
        }
        status = "Opening headphone control channel…"
        peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard selected?.identifier == peripheral.identifier else { return }
        if let error { fail(error.localizedDescription); return }
        guard let channel else { fail("The headphones refused the LE L2CAP channel."); return }
        self.channel = channel
        frameBuffer.reset()
        lastFrameSent = .distantPast
        channel.inputStream.delegate = self; channel.outputStream.delegate = self
        channel.inputStream.schedule(in: .main, forMode: .common)
        channel.outputStream.schedule(in: .main, forMode: .common)
        channel.inputStream.open(); channel.outputStream.open()
        status = "Verifying the headphone control protocol…"
        writeTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushOutput() }
        }
        armTimeout(seconds: 3, message: "The channel opened but no BMAP reply arrived. Close the Bose app and reconnect; this firmware may not support iOS control.")
        do { try enqueue(BoseCommands.liveness) } catch { fail(error.localizedDescription) }
    }
}

extension HeadphoneBluetooth: @preconcurrency StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let channel, aStream === channel.inputStream || aStream === channel.outputStream else { return }
        switch eventCode {
        case .hasBytesAvailable:
            let stream = channel.inputStream!
            var bytes = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count < 0 { fail(stream.streamError?.localizedDescription ?? "The headphone input stream failed."); return }
                if count == 0 { break }
                receive(Data(bytes.prefix(count)))
                guard self.channel != nil else { return }
            }
        case .hasSpaceAvailable: flushOutput()
        case .errorOccurred: fail(aStream.streamError?.localizedDescription ?? "The headphone control stream failed.")
        case .endEncountered: fail("The headphones closed their control channel.")
        default: break
        }
    }
}
