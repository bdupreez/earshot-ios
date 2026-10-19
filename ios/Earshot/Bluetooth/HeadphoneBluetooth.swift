import Foundation
import Combine
@preconcurrency import CoreBluetooth

struct DiscoveredHeadphone: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertisesBmap: Bool
}

struct BmapOutgoingFrame {
    let data: Data
    let address: BmapAddress
    let diagnosticID: UUID?
    let operation: BmapOperation

    static func retainingAfterDiagnosticCancel(_ frames: [Self], partialWriteOffset: Int) -> [Self] {
        frames.enumerated().compactMap { index, frame in
            frame.diagnosticID == nil || index == 0 && partialWriteOffset > 0 ? frame : nil
        }
    }
}

/// AI-assisted native port of the MIT-licensed HellzYeahh/earshot Bluetooth contract.
/// Core Bluetooth connection to the BMAP LE connection-oriented channel advertised by Bose.
/// A GATT connection alone is not a working control connection: the [0.1] probe must answer.
@MainActor
final class HeadphoneBluetooth: NSObject, ObservableObject {
    @Published private(set) var status = "Not connected"
    @Published private(set) var devices: [DiscoveredHeadphone] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isScanning = false
    @Published private(set) var log: [String] = []
    @Published private(set) var reconnectEnabled: Bool
    @Published private(set) var rememberedDeviceName: String?
    @Published private(set) var isReconnecting = false
    @Published private(set) var reconnectAttempt = 0
    var onPacket: ((BmapPacket) -> Void)?
    var diagnosticPreflightError: (() -> String?)?
    var connectedDeviceID: UUID? { selected?.identifier }
    let protocolScanner = BmapProtocolScanner()
    let printConsole = BosePrintConsole()

    static let service = CBUUID(string: "FEBE")
    static let psmCharacteristic = CBUUID(string: "089CA084-6721-4419-9003-5E14D5AB587D")

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var channel: CBL2CAPChannel?
    private var frameBuffer = BmapFrameBuffer()
    private var outgoing: [BmapOutgoingFrame] = []
    private var outputOffset = 0
    private var lastFrameSent = Date.distantPast
    private var timeout: Timer?
    private var scanTimeout: Timer?
    private var writeTimer: Timer?
    private var livenessTimer: Timer?
    private var liveness = BluetoothLivenessMonitor(lastResponse: .distantPast)
    private var wantsScan = false
    private var findingRememberedDevice = false
    private var wantsRememberedReconnect = false
    private var restoredCancellations: [CBPeripheral] = []
    private var cancelRestoredScan = false
    private var restoringPeripheral = false
    private var retryTask: Task<Void, Never>?
    private var retryToken = UUID()
    private var reconnectPolicy: BluetoothReconnectPolicy
    private let defaults: UserDefaults
    private static let restorationID = "dev.earshot.ios.bmap-central"
    private static let preferencePrefix = "earshot.bluetooth."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.preferencePrefix + "reconnect")
        reconnectEnabled = enabled
        rememberedDeviceName = defaults.string(forKey: Self.preferencePrefix + "name")
        reconnectPolicy = BluetoothReconnectPolicy(enabled: enabled,
            rememberedID: defaults.string(forKey: Self.preferencePrefix + "identifier").flatMap(UUID.init(uuidString:)),
            userStopped: defaults.bool(forKey: Self.preferencePrefix + "manual-stop"))
        super.init()
        protocolScanner.onCancel = { [weak self] in self?.discardUnsentDiagnosticFrames() }
        protocolScanner.preflightError = { [weak self] in
            guard let self else { return "The headphone control channel is unavailable." }
            if self.printConsole.isRunning || self.outgoing.contains(where: { $0.operation != .get }) {
                return "Wait for the current headphone command or console collection to finish before scanning."
            }
            return self.diagnosticPreflightError?()
        }
        // Deliberately no CBCentralManager here: demo/onboarding must not request Bluetooth.
    }

    /// Call after the application has established that it is outside demo/onboarding.
    /// iOS may restore a manager after system termination; force-quit is not a relaunch promise.
    func start() {
        reconnectPolicy.resume()
        guard reconnectPolicy.eligible else { return }
        #if targetEnvironment(simulator)
        return
        #else
        ensureCentral()
        if central?.state == .poweredOn, selected == nil, retryTask == nil { attemptRememberedConnection() }
        #endif
    }

    func setReconnectEnabled(_ enabled: Bool) {
        let cancelPendingConnection = !enabled && isReconnecting && !isConnected
        reconnectEnabled = enabled
        reconnectPolicy.enable(enabled)
        defaults.set(enabled, forKey: Self.preferencePrefix + "reconnect")
        defaults.set(reconnectPolicy.userStopped, forKey: Self.preferencePrefix + "manual-stop")
        if enabled && !reconnectPolicy.suspended { start() }
        else {
            cancelRetry()
            if cancelPendingConnection { stopScan(); closeLink(); status = "Automatic reconnect is off." }
        }
    }

    func reconnectRememberedDevice() {
        guard reconnectPolicy.rememberedID != nil else { status = "Connect headphones once before using remembered-device reconnect."; return }
        reconnectPolicy.manualConnection()
        wantsRememberedReconnect = true
        defaults.set(false, forKey: Self.preferencePrefix + "manual-stop")
        #if targetEnvironment(simulator)
        status = "Remembered-device Bluetooth reconnect needs a physical iPhone."
        #else
        cancelRetry(); ensureCentral()
        if central?.state == .poweredOn { attemptRememberedConnection() }
        #endif
    }

    /// Cancels a connection for demo mode without changing the user's saved reconnect preference.
    func suspend() {
        reconnectPolicy.suspended = true
        wantsRememberedReconnect = false
        cancelRetry(); stopScan(); closeLink()
        status = "Bluetooth control is paused."
    }

    /// Use before an intentional power-off or disconnection of the control source.
    func preventReconnectUntilUserAction() {
        reconnectPolicy.manualDisconnect()
        wantsRememberedReconnect = false
        defaults.set(true, forKey: Self.preferencePrefix + "manual-stop")
        cancelRetry()
    }

    func forgetRememberedDevice() {
        disconnect()
        reconnectPolicy.rememberedID = nil
        rememberedDeviceName = nil
        defaults.removeObject(forKey: Self.preferencePrefix + "identifier")
        defaults.removeObject(forKey: Self.preferencePrefix + "name")
    }

    private func ensureCentral() {
        guard central == nil else { return }
        // Apple's restoration dictionary preserves peripherals, not our L2CAP streams. Restored
        // devices always rediscover their PSM and pass a new BMAP liveness probe before use.
        central = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restorationID, CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func scan() {
        #if targetEnvironment(simulator)
        status = "Bluetooth hardware needs a physical iPhone. Use Demo to explore in Simulator."
        appendLog("Simulator: real headphone discovery requires an iPhone.")
        #else
        guard !isConnected, selected == nil else { return }
        wantsRememberedReconnect = false
        reconnectPolicy.resume(); cancelRetry()
        wantsScan = true
        if central == nil {
            ensureCentral()
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            updateBluetoothStatus()
        }
        #endif
    }

    func stopScan() {
        wantsScan = false
        findingRememberedDevice = false
        central?.stopScan()
        scanTimeout?.invalidate(); scanTimeout = nil
        isScanning = false
    }

    func connect(_ device: DiscoveredHeadphone) {
        guard let central, central.state == .poweredOn, let peripheral = peripherals[device.id] else {
            status = "Scan for nearby headphones before connecting."
            return
        }
        cancelRetry(); closeLink()
        reconnectPolicy.manualConnection()
        wantsRememberedReconnect = false
        defaults.set(false, forKey: Self.preferencePrefix + "manual-stop")
        stopScan()
        openControlLink(peripheral, name: device.name)
    }

    private func openControlLink(_ peripheral: CBPeripheral, name: String) {
        guard let central, central.state == .poweredOn else { return }
        selected = peripheral
        peripheral.delegate = self
        status = "Connecting to \(name)…"
        appendLog("Connecting to the selected Bose device.")
        if peripheral.state == .connected {
            status = "Restoring headphone control service…"
            peripheral.discoverServices(nil)
        } else if peripheral.state != .connecting {
            central.connect(peripheral, options: nil)
        }
        armTimeout(seconds: 15, message: "Connection timed out. Keep the headphones nearby and close other control apps.")
    }

    func disconnect() {
        preventReconnectUntilUserAction()
        stopScan(); closeLink()
        status = "Not connected"
    }

    private func closeLink() {
        let peripheral = selected
        selected = nil
        restoringPeripheral = false
        closeChannel()
        if let peripheral {
            if central?.state == .poweredOn { central?.cancelPeripheralConnection(peripheral) }
            else if peripheral.state != .disconnected { restoredCancellations.append(peripheral) }
        }
    }

    private func cancelRetry() {
        retryToken = UUID(); retryTask?.cancel(); retryTask = nil
        isReconnecting = false
    }

    private func attemptRememberedConnection() {
        guard !reconnectPolicy.suspended, !reconnectPolicy.userStopped,
              !isConnected, selected == nil, let central, central.state == .poweredOn,
              let identifier = reconnectPolicy.rememberedID else { return }
        retryTask = nil
        wantsRememberedReconnect = false
        isReconnecting = true; reconnectAttempt = max(1, reconnectPolicy.attempts)
        let known = peripherals[identifier] ?? central.retrievePeripherals(withIdentifiers: [identifier]).first
        if let peripheral = known, peripheral.state != .disconnecting {
            peripherals[identifier] = peripheral
            openControlLink(peripheral, name: rememberedDeviceName ?? "remembered Bose headphones")
        } else if known?.state == .disconnecting {
            scheduleReconnect()
        } else {
            findingRememberedDevice = true
            isScanning = true
            status = "Looking for your remembered headphones…"
            // A service-filtered scan is also valid under iOS's constrained background policy.
            central.scanForPeripherals(withServices: [Self.service], options: nil)
            armTimeout(seconds: 8, message: "Remembered headphones are not advertising a compatible control service.")
        }
    }

    private func scheduleReconnect() {
        guard reconnectPolicy.eligible, central?.state == .poweredOn else { isReconnecting = false; return }
        guard let delay = reconnectPolicy.nextDelay() else {
            isReconnecting = false
            if reconnectPolicy.exhausted { status = "Automatic reconnect paused after six retries. Tap Reconnect or scan again." }
            return
        }
        cancelRetry()
        isReconnecting = true
        reconnectAttempt = reconnectPolicy.attempts
        status = "Reconnecting in \(Int(delay)) seconds (attempt \(reconnectPolicy.attempts) of 6)…"
        let token = UUID(); retryToken = token
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.retryToken == token, self.reconnectPolicy.eligible else { return }
            self.attemptRememberedConnection()
        }
    }

    /// Acceptance means queued for transport, not acknowledged by the headphones.
    /// Features must update hardware state only when a STATUS/RESULT packet arrives.
    func send(_ packet: BmapPacket) throws {
        try BmapWriteGuard.check(packet)
        if let error = protocolScanner.mutationAccessError(for: packet) { throw BmapFailure.unavailable(error) }
        guard isConnected, channel != nil else { throw BmapFailure.unavailable("Connect to a verified headphone control channel first.") }
        try enqueue(packet, diagnosticID: protocolScanner.expectsDiagnosticRead(packet) ? UUID() : nil)
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
        let failedIdentifier = selected?.identifier ?? (findingRememberedDevice ? reconnectPolicy.rememberedID : nil)
        stopScan(); closeLink()
        status = message
        appendLog(message)
        if failedIdentifier == reconnectPolicy.rememberedID { scheduleReconnect() }
    }

    private func closeChannel() {
        isConnected = false
        protocolScanner.cancel()
        printConsole.cancel(reason: "The headphone control channel disconnected. Collection stopped; no response is simulated.")
        timeout?.invalidate(); timeout = nil
        writeTimer?.invalidate(); writeTimer = nil
        livenessTimer?.invalidate(); livenessTimer = nil
        if let channel {
            channel.inputStream.delegate = nil
            channel.outputStream.delegate = nil
            channel.inputStream.close(); channel.outputStream.close()
            channel.inputStream.remove(from: .main, forMode: .common)
            channel.outputStream.remove(from: .main, forMode: .common)
        }
        channel = nil
        outgoing.removeAll(); outputOffset = 0
        protocolScanner.resetDiagnosticConnection()
        frameBuffer.reset()
    }

    private func enqueue(_ packet: BmapPacket, priority: Bool = false, diagnosticID: UUID? = nil) throws {
        try BmapWriteGuard.check(packet)
        guard outgoing.count < 256 else { throw BmapFailure.unavailable("The headphone command queue is full. Wait for the current changes to finish.") }
        let encoded = try packet.encode()
        let frame = BmapOutgoingFrame(data: encoded, address: packet.address, diagnosticID: diagnosticID, operation: packet.operation)
        if let diagnosticID { protocolScanner.queuedDiagnosticRead(id: diagnosticID, address: packet.address) }
        if priority { outgoing.insert(frame, at: outputOffset > 0 && !outgoing.isEmpty ? 1 : 0) }
        else { outgoing.append(frame) }
        appendLog("→ \(packetLog(packet))")
        flushOutput()
    }

    private func flushOutput() {
        guard let stream = channel?.outputStream, stream.hasSpaceAvailable, !outgoing.isEmpty else { return }
        // The Android transport spaces requests too. Preserve whole-frame order even on partial writes.
        guard outputOffset > 0 || Date().timeIntervalSince(lastFrameSent) >= 0.08 else { return }
        let frame = outgoing[0]
        let data = frame.data
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return stream.write(base.advanced(by: outputOffset), maxLength: data.count - outputOffset)
        }
        if written < 0 { fail(stream.streamError?.localizedDescription ?? "The headphone output stream failed."); return }
        outputOffset += written
        if outputOffset == data.count {
            if let id = frame.diagnosticID { protocolScanner.transmittedDiagnosticRead(id: id) }
            if isConnected, let packet = BmapPacket.decodeOne(data), packet.address != BmapAddress(0, 1) {
                liveness.sentRequest(at: Date())
            }
            outgoing.removeFirst(); outputOffset = 0; lastFrameSent = Date()
        }
    }

    private func discardUnsentDiagnosticFrames() {
        let retained = BmapOutgoingFrame.retainingAfterDiagnosticCancel(outgoing, partialWriteOffset: outputOffset)
        let retainedIDs = Set(retained.compactMap(\.diagnosticID))
        for id in outgoing.compactMap(\.diagnosticID) where !retainedIDs.contains(id) {
            protocolScanner.discardedDiagnosticRead(id: id)
        }
        outgoing = retained
    }

    /// Called after transport liveness verification. Only errors matching an actually
    /// transmitted diagnostic read are isolated; unsolicited valid status still updates the app.
    func routeVerifiedResponse(_ packet: BmapPacket, at now: Date = .now) {
        guard packet.operation.isDeviceResponse else { return }
        if packet.block == 22 { printConsole.receive(packet); return }
        protocolScanner.receive(packet)
        if protocolScanner.isolatesDiagnosticError(packet, at: now) { return }
        onPacket?(packet)
    }

    private func receive(_ data: Data) {
        let oldDesyncCount = frameBuffer.desyncCount
        let packets = frameBuffer.feed(data)
        if frameBuffer.desyncCount > oldDesyncCount { fail("The control channel returned invalid BMAP data. Reconnect to try again."); return }
        for packet in packets {
            guard packet.operation.isDeviceResponse else { continue }
            liveness.received(at: Date())
            // Idle firmware console floods must not fill generic diagnostics or reach AppStore.
            // Explicit console collection has its own bounded, user-visible transcript.
            if packet.block != 22 || printConsole.isRunning { appendLog("← \(packetLog(packet))") }
            if !isConnected {
                guard packet.answersLivenessProbe else { continue }
                isConnected = true
                timeout?.invalidate(); timeout = nil
                status = "Connected to \(selected?.name ?? "Bose headphones")"
                appendLog("BMAP liveness verified over LE L2CAP.")
                if let selected {
                    reconnectPolicy.verified(selected.identifier)
                    rememberedDeviceName = selected.name ?? "Bose headphones"
                    defaults.set(selected.identifier.uuidString, forKey: Self.preferencePrefix + "identifier")
                    defaults.set(rememberedDeviceName, forKey: Self.preferencePrefix + "name")
                    defaults.set(false, forKey: Self.preferencePrefix + "manual-stop")
                }
                cancelRetry()
                // This timer runs only when iOS grants the process execution time. Restoration
                // never assumes that timers or our L2CAP streams survived suspension/termination.
                livenessTimer?.invalidate()
                livenessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkLiveness() }
                }
            }
            routeVerifiedResponse(packet)
        }
    }

    private func checkLiveness() {
        guard isConnected else { return }
        switch liveness.tick(at: Date()) {
        case .none: break
        case .sendProbe:
            do { try enqueue(BoseCommands.liveness, priority: true) } catch { fail(error.localizedDescription) }
        case .disconnect: fail("The headphones stopped answering BMAP requests. Their control channel will be reconnected if automatic reconnect is enabled.")
        }
    }

    private func appendLog(_ message: String) {
        log.append(message)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    private func packetLog(_ packet: BmapPacket) -> String {
        // Paired-source names/addresses, custom names, serials, keys and mode names must not
        // be copied into a diagnostics report. Keep the address and frame length for debugging.
        let privatePayload = packet.block == 4 || packet.block == 18 || packet.block == 22
            || packet.address == BmapAddress(1, 2) || packet.address == BmapAddress(31, 6)
            || packet.block == 0 && [7, 9, 12].contains(packet.function)
        return privatePayload ? "\(packet.address) \(packet.operation) <\(packet.payload.count) bytes redacted>" : packet.description
    }
}

extension HeadphoneBluetooth: @preconcurrency CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        cancelRestoredScan = true
        guard reconnectPolicy.eligible else {
            if central.state == .poweredOn {
                for peripheral in restored { central.cancelPeripheralConnection(peripheral) }
                central.stopScan()
            } else { restoredCancellations += restored; cancelRestoredScan = true }
            return
        }
        guard let peripheral = restored.first(where: { $0.identifier == reconnectPolicy.rememberedID }) else { return }
        let others = restored.filter { $0.identifier != peripheral.identifier }
        if central.state == .poweredOn { for other in others { central.cancelPeripheralConnection(other) } }
        else { restoredCancellations += others }
        // Retain delegates before Apple's later didConnect/didUpdateState callbacks arrive.
        peripherals[peripheral.identifier] = peripheral
        selected = peripheral; peripheral.delegate = self
        restoringPeripheral = true
        isReconnecting = true
        status = "Restoring Bluetooth. The headphone protocol still needs verification…"
        appendLog("Core Bluetooth restored the remembered peripheral; re-verification required.")
        if central.state == .poweredOn {
            if peripheral.state == .connected { peripheral.discoverServices(nil) }
            else if peripheral.state == .disconnected { central.connect(peripheral, options: nil) }
        }
        armTimeout(seconds: 15, message: "Restored connection did not establish a working headphone control channel.")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if cancelRestoredScan { central.stopScan(); cancelRestoredScan = false }
            for peripheral in restoredCancellations { central.cancelPeripheralConnection(peripheral) }
            restoredCancellations.removeAll()
            if wantsScan { beginScan() }
            else if let selected {
                if selected.state == .connected, channel == nil { selected.discoverServices(nil) }
                else if selected.state == .disconnected { openControlLink(selected, name: rememberedDeviceName ?? "Bose headphones") }
            } else if wantsRememberedReconnect || reconnectPolicy.eligible {
                reconnectPolicy.rearm(); attemptRememberedConnection()
            } else { updateBluetoothStatus() }
        } else {
            if central.state == .unknown, restoringPeripheral { updateBluetoothStatus(); return }
            let resumeScan = wantsScan && [.unknown, .resetting, .poweredOff].contains(central.state)
            cancelRetry(); stopScan(); closeLink(); wantsScan = resumeScan
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
        if findingRememberedDevice, peripheral.identifier == reconnectPolicy.rememberedID {
            stopScan()
            openControlLink(peripheral, name: rememberedDeviceName ?? name)
        }
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
        if peripheral.identifier == reconnectPolicy.rememberedID { scheduleReconnect() }
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
