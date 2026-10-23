import Foundation
import Combine
@preconcurrency import CoreBluetooth

// AI-assisted native adaptation of Earshot by HellzYeahh and contributors (MIT).
// Source0.75: bt/GattBatteryReader.kt and protocol/apple/ContinuityAdvert.kt.
// Public API: developer.apple.com/documentation/corebluetooth/advertisement-data-retrieval-keys
// Standard BAS reads and passive manufacturer data only; never a vendor control transport.

struct BatteryCompanionDevice: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
    let advertisesBatteryService: Bool
}

struct BatteryCompanionReading: Equatable, Sendable {
    let sourceID: UUID
    let sourceName: String
    let percent: Int
    let receivedAt: Date
}

struct NearbyAppleBatteryObservation: Identifiable, Equatable, Sendable {
    let id: UUID
    let advert: AppleContinuityAdvert
    let rssi: Int
    let receivedAt: Date
}

enum BatteryCompanionPolicy {
    static let maximumDevices = 32
    static let maximumNearbyObservations = 16
    static let scanDuration: TimeInterval = 15
    static let readTimeout: TimeInterval = 8

    static func batteryLevel(_ data: Data) -> Int? {
        guard data.count == 1, let byte = data.first, byte <= 100 else { return nil }
        return Int(byte)
    }

    static func allowsRead(service: String, characteristic: String) -> Bool {
        let services = ["180F", "0000180F-0000-1000-8000-00805F9B34FB"]
        let characteristics = ["2A19", "00002A19-0000-1000-8000-00805F9B34FB"]
        return services.contains(service.uppercased()) && characteristics.contains(characteristic.uppercased())
    }

    static func allowsSelection(_ id: UUID, discovered: [BatteryCompanionDevice]) -> Bool {
        discovered.contains { $0.id == id && $0.advertisesBatteryService }
    }

    static func updating<Element: Identifiable>(_ item: Element, in items: [Element], limit: Int) -> [Element] {
        guard limit > 0 else { return [] }
        return Array(([item] + items.filter { $0.id != item.id }).prefix(limit))
    }
}

/// CoreBluetooth cancellation is asynchronous. Keep the old connection reserved until its
/// terminal delegate callback; a same-source reread must never inherit that callback.
struct BatteryReadLifecycle: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle, active(UUID), disconnecting(UUID)
    }
    enum Effect: Equatable, Sendable {
        case none, connect(UUID), cancel(UUID)
    }

    private(set) var phase: Phase = .idle
    private(set) var pendingID: UUID?

    func accepts(_ id: UUID) -> Bool { phase == .active(id) }
    var waitsForDisconnect: Bool { if case .disconnecting = phase { return true }; return false }

    mutating func request(_ id: UUID) -> Effect {
        switch phase {
        case .idle:
            phase = .active(id)
            return .connect(id)
        case .active(let previous):
            pendingID = id
            phase = .disconnecting(previous)
            return .cancel(previous)
        case .disconnecting:
            pendingID = id // The latest explicit selection wins; none connect before acknowledgement.
            return .none
        }
    }

    mutating func cancel() -> Effect {
        pendingID = nil
        guard case .active(let previous) = phase else { return .none }
        phase = .disconnecting(previous)
        return .cancel(previous)
    }

    mutating func terminal(_ id: UUID) -> Effect {
        switch phase {
        case .disconnecting(let previous) where previous == id:
            phase = .idle
            guard let next = pendingID else { return .none }
            pendingID = nil
            phase = .active(next)
            return .connect(next)
        case .active(let current) where current == id:
            phase = .idle
            return .none
        default:
            return .none
        }
    }

    /// Radio unavailability invalidates all connections, including queued intent.
    mutating func reset() { phase = .idle; pendingID = nil }
}

/// Parses only a delivered public manufacturer-data value, including company bytes4C00.
/// Delivery/ownership cannot be inferred from this parser. It never identifies the user's route.
struct AppleContinuityAdvert: Equatable, Sendable {
    let model: UInt16
    let leftPercent: Int?
    let rightPercent: Int?
    let casePercent: Int?
    let leftCharging: Bool
    let rightCharging: Bool
    let caseCharging: Bool

    var modelName: String { Self.names[model] ?? "Apple accessory (unknown model)" }
    var isHeadphones: Bool { Self.headphoneModels.contains(model) }
    var headlinePercent: Int? {
        if isHeadphones { return leftPercent ?? rightPercent }
        return [leftPercent, rightPercent].compactMap { $0 }.min()
    }

    static func parse(manufacturerData data: Data) -> Self? {
        let bytes = Array(data)
        guard bytes.count >= 10, bytes[0] == 0x4c, bytes[1] == 0x00, bytes[2] == 0x07 else { return nil }
        let body = Array(bytes.dropFirst(2))
        let flipped = body[5] & 0x20 == 0
        let high = body[6] >> 4, low = body[6] & 0x0f
        let charge = body[7] >> 4
        func percent(_ nibble: UInt8) -> Int? { nibble <= 10 ? Int(nibble) * 10 : nil }
        return .init(model: UInt16(body[3]) << 8 | UInt16(body[4]),
            leftPercent: percent(flipped ? high : low), rightPercent: percent(flipped ? low : high),
            casePercent: percent(body[7] & 0x0f), leftCharging: charge & (flipped ? 2 : 1) != 0,
            rightCharging: charge & (flipped ? 1 : 2) != 0, caseCharging: charge & 4 != 0)
    }

    private static let headphoneModels: Set<UInt16> = [0x0a20, 0x0620, 0x0920, 0x0c20, 0x1720]
    private static let names: [UInt16: String] = [
        0x0220: "AirPods", 0x0f20: "AirPods (2nd generation)", 0x1320: "AirPods (3rd generation)",
        0x0e20: "AirPods Pro", 0x1420: "AirPods Pro (2nd generation)", 0x2420: "AirPods Pro (2nd generation, USB-C)",
        0x0a20: "AirPods Max", 0x0320: "Powerbeats3", 0x0b20: "Powerbeats Pro", 0x0d20: "Powerbeats4", 0x0520: "BeatsX",
        0x0620: "Beats Solo3", 0x0920: "Beats Studio3", 0x0c20: "Beats Solo Pro", 0x1020: "Beats Flex",
        0x1120: "Beats Studio Buds", 0x1220: "Beats Fit Pro", 0x1620: "Beats Studio Buds+", 0x1720: "Beats Studio Pro"
    ]
}

@MainActor
final class BatteryCompanion: NSObject, ObservableObject {
    @Published private(set) var devices: [BatteryCompanionDevice] = []
    @Published private(set) var nearbyApple: [NearbyAppleBatteryObservation] = []
    @Published private(set) var reading: BatteryCompanionReading?
    @Published private(set) var isScanning = false
    @Published private(set) var isReading = false
    @Published private(set) var status = "Choose Discover to look for standard BLE battery sources."

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var pendingPeripheral: CBPeripheral?
    private var readLifecycle = BatteryReadLifecycle()
    private var requestedScan = false
    private var includeNearbyApple = false
    private var deadline: Task<Void, Never>?
    private var scanToken = UUID()
    private var readToken = UUID()
    private static let service = CBUUID(string: "180F")
    private static let characteristic = CBUUID(string: "2A19")

    override init() { super.init() } // No manager/permission prompt merely from opening this tool.

    func discover(includeNearbyApple: Bool = false) {
        stop()
        devices = []; nearbyApple = []; peripherals = [:]
        self.includeNearbyApple = includeNearbyApple
        requestedScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central?.state == .poweredOn { beginScan() }
        else { updatePowerStatus() }
    }

    func read(_ device: BatteryCompanionDevice) {
        guard BatteryCompanionPolicy.allowsSelection(device.id, discovered: devices),
              let peripheral = peripherals[device.id], central?.state == .poweredOn else {
            status = "Discover and select a peripheral that advertises the standard Battery Service first."
            return
        }
        stop()
        reading = nil; pendingPeripheral = peripheral; isReading = true
        let effect = readLifecycle.request(peripheral.identifier)
        status = readLifecycle.waitsForDisconnect ? "Waiting for the previous battery source to disconnect…" : "Reading the selected device's standard battery…"
        let token = UUID(); readToken = token
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(BatteryCompanionPolicy.readTimeout)) } catch { return }
            guard let self, self.readToken == token, self.isReading else { return }
            self.endRead("The selected battery source did not answer in time. No vendor command was sent.")
        }
        perform(effect)
    }

    func stop() {
        requestedScan = false; isScanning = false
        scanToken = UUID(); readToken = UUID()
        deadline?.cancel(); deadline = nil
        central?.stopScan()
        pendingPeripheral = nil; isReading = false
        perform(readLifecycle.cancel())
    }

    func stopForInactivity() {
        let wasBusy = requestedScan || isScanning || isReading
        stop()
        if wasBusy { status = "Battery discovery stopped because this screen or app is inactive." }
    }

    func cancelByUser() {
        stop()
        status = "Battery discovery or reading cancelled. No vendor command was sent."
    }

    private func beginScan() {
        guard requestedScan, central?.state == .poweredOn else { return }
        isScanning = true
        status = includeNearbyApple ? "Looking for standard battery sources and unverified nearby Apple adverts…" : "Looking for peripherals advertising the standard Battery Service…"
        central?.scanForPeripherals(withServices: includeNearbyApple ? nil : [Self.service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        let token = UUID(); scanToken = token
        deadline?.cancel()
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(BatteryCompanionPolicy.scanDuration)) } catch { return }
            guard let self, self.scanToken == token else { return }
            self.central?.stopScan(); self.requestedScan = false; self.isScanning = false; self.deadline = nil
            self.status = self.devices.isEmpty ? "No standard battery source found. Nearby Apple telemetry may be unavailable through public iOS APIs." : "Discovery finished. Select a standard battery source to read it."
        }
    }

    private func endRead(_ message: String) {
        pendingPeripheral = nil; isReading = false
        readToken = UUID(); deadline?.cancel(); deadline = nil
        perform(readLifecycle.cancel())
        status = message
    }

    private func perform(_ effect: BatteryReadLifecycle.Effect) {
        switch effect {
        case .none: break
        case .cancel(let id):
            guard let selected, selected.identifier == id else { return }
            selected.delegate = nil
            central?.cancelPeripheralConnection(selected)
        case .connect(let id):
            guard let peripheral = pendingPeripheral, peripheral.identifier == id,
                  central?.state == .poweredOn else {
                // No new connect was issued, so there is no terminal callback to await.
                readLifecycle.reset(); pendingPeripheral = nil; isReading = false
                readToken = UUID(); deadline?.cancel(); deadline = nil
                status = "The selected battery source is no longer available. Discover and select it again."
                return
            }
            pendingPeripheral = nil
            selected = peripheral; peripheral.delegate = self
            status = "Reading the selected device's standard battery…"
            central?.connect(peripheral, options: nil)
        }
    }

    private func connectionTerminated(_ peripheral: CBPeripheral, message: String) {
        guard selected === peripheral else { return }
        let failedActiveRead = readLifecycle.accepts(peripheral.identifier)
        selected = nil; peripheral.delegate = nil
        let next = readLifecycle.terminal(peripheral.identifier)
        if failedActiveRead {
            pendingPeripheral = nil; isReading = false
            readToken = UUID(); deadline?.cancel(); deadline = nil
            status = message
        }
        perform(next)
    }

    private func invalidateReadConnection() {
        stop()
        selected?.delegate = nil; selected = nil
        readLifecycle.reset()
    }

    private func updatePowerStatus() {
        switch central?.state {
        case .poweredOn: if requestedScan { beginScan() }
        case .unauthorized: invalidateReadConnection(); status = "Allow Bluetooth for Earshot in Settings to discover battery sources."
        case .poweredOff: invalidateReadConnection(); status = "Turn on Bluetooth to discover battery sources."
        case .unsupported: invalidateReadConnection(); status = "Bluetooth battery discovery is unavailable on this device."
        case .resetting: invalidateReadConnection(); status = "Bluetooth is restarting. Choose Discover again when it is ready."
        default: status = "Waiting for Bluetooth permission or availability…"
        }
    }
}

extension BatteryCompanion: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) { updatePowerStatus() }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) +
                       (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        if !includeNearbyApple || services.contains(Self.service) {
            let source = BatteryCompanionDevice(id: peripheral.identifier,
                name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unnamed BLE battery source",
                rssi: RSSI.intValue, advertisesBatteryService: true)
            devices = BatteryCompanionPolicy.updating(source, in: devices, limit: BatteryCompanionPolicy.maximumDevices)
            peripherals[peripheral.identifier] = peripheral
            let retained = Set(devices.map(\.id))
            peripherals = peripherals.filter { retained.contains($0.key) }
        }
        if includeNearbyApple, let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           let advert = AppleContinuityAdvert.parse(manufacturerData: data) {
            let observation = NearbyAppleBatteryObservation(id: peripheral.identifier, advert: advert, rssi: RSSI.intValue, receivedAt: .now)
            nearbyApple = BatteryCompanionPolicy.updating(observation, in: nearbyApple, limit: BatteryCompanionPolicy.maximumNearbyObservations)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isReading, selected === peripheral, readLifecycle.accepts(peripheral.identifier) else { central.cancelPeripheralConnection(peripheral); return }
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionTerminated(peripheral, message: "The selected standard battery source could not be reached. No vendor command was sent.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionTerminated(peripheral, message: "The selected standard battery source disconnected before a reading arrived.")
    }
}

extension BatteryCompanion: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isReading, selected === peripheral, readLifecycle.accepts(peripheral.identifier) else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            endRead("The selected device did not expose the standard Battery Service."); return
        }
        peripheral.discoverCharacteristics([Self.characteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isReading, selected === peripheral, readLifecycle.accepts(peripheral.identifier), service.uuid == Self.service else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristic }),
              characteristic.properties.contains(.read) else {
            endRead("The selected device has no readable standard Battery Level characteristic."); return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let reportedService: CBService? = characteristic.service
        guard isReading, selected === peripheral, readLifecycle.accepts(peripheral.identifier), let service = reportedService,
              BatteryCompanionPolicy.allowsRead(service: service.uuid.uuidString, characteristic: characteristic.uuid.uuidString) else { return }
        guard error == nil, let data = characteristic.value, let percent = BatteryCompanionPolicy.batteryLevel(data) else {
            endRead("The selected source returned no valid standard battery percentage."); return
        }
        let name = devices.first { $0.id == peripheral.identifier }?.name ?? "Selected BLE battery source"
        reading = .init(sourceID: peripheral.identifier, sourceName: name, percent: percent, receivedAt: .now)
        endRead("Read the selected source's standard battery. This is separate from headphone control.")
    }
}
