import Combine
import CoreLocation
import Foundation
import Network
import NetworkExtension

/// Public-API foreground equivalent for upstream Earshot's optional Wi-Fi trigger (MIT).
/// Reading SSID requires Access WiFi Information + precise location authorization on a signed
/// device. CLLocationManager is used only for authorization: no location service is started.
/// Apple: https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:)
/// Apple: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.wifi-info
@MainActor
final class WiFiObserver: NSObject, ObservableObject {
    @Published private(set) var ssid: String?
    @Published private(set) var status = "Optional Wi-Fi rules are off. Allow access explicitly to read the current network name."
    @Published private(set) var isEnabled: Bool
    var onSSIDChange: ((String?) -> Void)?

    private let defaults: UserDefaults
    private var active = false
    private var location: CLLocationManager?
    private var monitor: NWPathMonitor?
    private var timer: Timer?
    private var queryID = UUID()
    private var observationID = UUID()
    private var queryInFlight = false
    private var pathUnavailable = false
    private var joins = ForegroundWiFiJoinTracker()
    private static let preference = "earshot.wifi-observer.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.preference)
        super.init()
        // No location manager, network query, or permission request is made during init.
    }

    deinit { monitor?.cancel(); timer?.invalidate() }

    /// Call only from a user-initiated control. The normal active/background lifecycle never prompts.
    func requestAccess() {
        guard active else { status = "Open Earshot in the foreground before allowing Wi-Fi access."; return }
        isEnabled = true
        defaults.set(true, forKey: Self.preference)
        #if targetEnvironment(simulator)
        status = "Wi-Fi SSID access needs a signed physical iPhone with the Access WiFi Information capability. Simulator cannot validate it."
        #else
        let manager = locationManager()
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") is String else {
            status = "This build is missing the Wi-Fi location-permission explanation."
            return
        }
        if manager.authorizationStatus == .notDetermined {
            status = "Allow While Using App with Precise Location to enable optional foreground Wi-Fi rules."
            manager.requestWhenInUseAuthorization()
        } else { updateAuthorization() }
        #endif
    }

    func disable() {
        isEnabled = false; defaults.set(false, forKey: Self.preference)
        stopObserving(); ssid = nil; joins = ForegroundWiFiJoinTracker()
        status = "Optional Wi-Fi rules are off."
    }

    /// Root must pass false in demo and whenever the scene is not active. No background watcher.
    func setActive(_ value: Bool) {
        active = value
        guard active, isEnabled else {
            stopObserving(); ssid = nil
            status = isEnabled ? "Wi-Fi observation is paused while Earshot is inactive or in demo mode." : "Optional Wi-Fi rules are off."
            return
        }
        #if targetEnvironment(simulator)
        status = "Current Wi-Fi SSID requires a signed physical iPhone; Simulator is unsupported."
        #else
        _ = locationManager()
        updateAuthorization()
        #endif
    }

    private func locationManager() -> CLLocationManager {
        if let location { return location }
        let manager = CLLocationManager()
        location = manager; manager.delegate = self
        return manager
    }

    private func updateAuthorization() {
        guard active, isEnabled, let location else { return }
        switch location.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            guard location.accuracyAuthorization == .fullAccuracy else {
                stopObserving(); ssid = nil
                status = "Enable Precise Location for Earshot in Settings to read the Wi-Fi name. GPS updates are not requested."
                return
            }
            beginObserving()
        case .notDetermined:
            stopObserving(); ssid = nil
            status = "Tap Allow Wi-Fi access to request While Using App permission."
        case .denied, .restricted:
            stopObserving(); ssid = nil
            status = "Wi-Fi rules need While Using App and Precise Location permission in Settings."
        @unknown default:
            stopObserving(); ssid = nil; status = "Wi-Fi authorization is unavailable."
        }
    }

    private func beginObserving() {
        guard active, isEnabled, monitor == nil else { return }
        let observation = UUID(); observationID = observation
        pathUnavailable = false
        let next = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor = next
        next.pathUpdateHandler = { [weak self] path in
            let noWiFiPath = path.status == .unsatisfied
            Task { @MainActor [weak self] in
                guard let self, self.active, self.isEnabled, self.monitor != nil,
                      self.observationID == observation else { return }
                self.pathUnavailable = noWiFiPath
                self.queryID = UUID(); self.queryInFlight = false
                self.refreshSSID()
            }
        }
        next.start(queue: DispatchQueue(label: "dev.earshot.wifi-observation"))
        // Network-path changes are not an SSID-change API. A small foreground refresh also
        // catches joins where the system retains a similar route. It is stopped on inactivity.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSSID() }
        }
        refreshSSID()
    }

    private func stopObserving() {
        observationID = UUID()
        queryID = UUID(); queryInFlight = false
        monitor?.cancel(); monitor = nil
        timer?.invalidate(); timer = nil
        // A pause is not evidence that the phone left its network. Retain the last observed
        // join so reactivating the same foreground session does not fire a duplicate rule.
    }

    private func refreshSSID() {
        guard active, isEnabled, monitor != nil, !queryInFlight,
              let location, [.authorizedWhenInUse, .authorizedAlways].contains(location.authorizationStatus),
              location.accuracyAuthorization == .fullAccuracy else { return }
        queryInFlight = true
        let token = UUID(); queryID = token
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let name = network?.ssid
            Task { @MainActor [weak self] in
                guard let self, self.active, self.isEnabled, self.queryID == token else { return }
                self.queryInFlight = false
                self.ssid = name
                if let name, !name.isEmpty {
                    self.status = "Current Wi-Fi name is available for foreground rules."
                    if self.joins.observe(name) { self.onSSIDChange?(name) }
                } else if self.pathUnavailable {
                    self.status = "No Wi-Fi network path is currently available."
                    if self.joins.disconnected() { self.onSSIDChange?(nil) }
                } else {
                    // nil also means missing entitlement/permission, not necessarily a network
                    // departure. Never synthesize a leave/rejoin event from a nil API result.
                    self.status = "Wi-Fi name is unavailable. A signed build needs Access WiFi Information, precise permission, and a connected Wi-Fi network."
                }
            }
        }
    }
}

extension WiFiObserver: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard active, isEnabled else { return }
        updateAuthorization()
    }
}

struct ForegroundWiFiJoinTracker {
    private(set) var lastObservedSSID: String?
    mutating func observe(_ ssid: String) -> Bool {
        guard !ssid.isEmpty, ssid != lastObservedSSID else { return false }
        lastObservedSSID = ssid
        return true
    }
    mutating func disconnected() -> Bool {
        guard lastObservedSSID != nil else { return false }
        lastObservedSSID = nil
        return true
    }
}
