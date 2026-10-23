import XCTest
@testable import Earshot

// Source-backed fixture tests, not headphone hardware validation.
// Original Earshot: HellzYeahh and contributors (MIT); experimental AI-assisted iOS port.
final class VendorCatalogueTests: XCTestCase {
    func testCatalogueHasStableUniqueIDsAndValidModelScopedDefaults() {
        let models = VendorCatalogue.models
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(models.filter { $0.vendor == .sennheiser }.count, 8)
        XCTAssertEqual(models.filter { $0.vendor == .skullcandy }.count, 2)
        for model in models {
            XCTAssertFalse(model.sourcePaths.isEmpty, model.id)
            XCTAssertEqual(Set(model.controls.map(\.id)).count, model.controls.count, model.id)
            XCTAssertEqual(Set(model.labGroups.map(\.id)).count, model.labGroups.count, model.id)
            let state = VendorDemoState(model: model)
            for control in model.controls {
                XCTAssertTrue(control.accepts(control.initialValue), "\(model.id).\(control.id)")
                XCTAssertEqual(state[control.id], control.initialValue)
            }
            XCTAssertTrue(model.batteryFixture.allSatisfy { (0...100).contains($0.percent) })
        }
    }

    func testCatalogueCannotAuthorizePhysicalConnectionOrInventClassicTransport() {
        for model in VendorCatalogue.models {
            XCTAssertFalse(model.physicalControlAvailable)
            if [.sennheiser, .sony, .skullcandy].contains(model.vendor) {
                XCTAssertEqual(model.transport, .classicRFCOMMUnsupported)
                XCTAssertTrue(model.transport.explanation.contains("simulated"))
            } else {
                XCTAssertEqual(model.transport, .systemAudioRouteOnly)
            }
        }
        XCTAssertNil(VendorCatalogue.model(id: "sony.wh1000xm4"))
        XCTAssertNotNil(VendorCatalogue.model(id: "generic.sonyWH1000XM4"))
        XCTAssertNotNil(VendorCatalogue.model(id: "generic.boseQCE2024"))
        XCTAssertNil(VendorCatalogue.model(id: "unknown"))
        XCTAssertTrue(VendorTransportAvailability.boseVerifiedL2CAP.explanation.contains("verified BMAP"))
        XCTAssertTrue(VendorTransportAvailability.batteryServiceReadOnly.explanation.contains("does not establish"))
    }

    func testSennheiserFamiliesDoNotShareUnsupportedControlsOrEQRanges() throws {
        let momentum4 = try model("sennheiser.momentum4")
        let momentum5 = try model("sennheiser.momentum5")
        let accentum = try model("sennheiser.accentum")
        let earbuds = try model("sennheiser.momentumTW4")
        XCTAssertEqual(momentum4.control(id: "noiseLevel")?.kind, .integerRange(0...100))
        XCTAssertNotNil(momentum4.control(id: "adaptive"))
        XCTAssertNil(accentum.control(id: "noiseLevel"))
        XCTAssertNil(accentum.control(id: "antiWind"))
        XCTAssertNil(accentum.control(id: "smartPause"))
        XCTAssertNotNil(accentum.control(id: "onHead"))
        XCTAssertNil(earbuds.control(id: "onHead"))
        XCTAssertNil(earbuds.control(id: "comfortCall"))
        XCTAssertNil(earbuds.control(id: "noiseLevel"))
        XCTAssertEqual(earbuds.control(id: "antiWind")?.kind, .toggle)
        guard case .choice(let choices) = try XCTUnwrap(earbuds.control(id: "transparencyLevel")).kind else {
            return XCTFail("Earbuds expose the documented1/50/100 transparency choices")
        }
        XCTAssertEqual(choices.map(\.id), ["1", "50", "100"])
        XCTAssertEqual(momentum4.controls.filter { $0.id.hasPrefix("eqBand") }.count, 5)
        XCTAssertEqual(momentum5.controls.filter { $0.id.hasPrefix("eqBand") }.count, 8)
        XCTAssertEqual(momentum4.control(id: "eqBand0")?.kind, .integerRange(-6...6))
        XCTAssertEqual(momentum4.evidence, .upstreamVirtualFixture)
        XCTAssertEqual(momentum5.evidence, .catalogueIllustration)
    }

    func testSennheiserDemoValidatesValuesAndAppliesCapturedNoiseSideEffects() throws {
        let definition = try model("sennheiser.momentum4")
        var state = VendorDemoState(model: definition)
        XCTAssertTrue(state.set(.integer(34), for: "noiseLevel"))
        XCTAssertTrue(state.set(.option("transparency"), for: "mode"))
        XCTAssertEqual(state["noiseLevel"], .integer(100))
        XCTAssertTrue(state.set(.option("off"), for: "mode"))
        XCTAssertEqual(state["noiseLevel"], .integer(34))
        XCTAssertTrue(state.set(.option("transparency"), for: "mode"))
        XCTAssertTrue(state.set(.boolean(true), for: "adaptive"))
        XCTAssertEqual(state["mode"], .option("anc"))
        XCTAssertEqual(state["noiseLevel"], .integer(0))
        let before = state
        XCTAssertFalse(state.set(.integer(101), for: "noiseLevel"))
        XCTAssertFalse(state.set(.boolean(true), for: "noiseLevel"))
        XCTAssertFalse(state.set(.option("unknown"), for: "sidetone"))
        XCTAssertFalse(state.set(.boolean(true), for: "factoryReset"))
        XCTAssertFalse(state.set(.integer(10), for: "noiseLevel", model: try model("sony.wh1000xm5")))
        XCTAssertEqual(state, before)
    }

    func testSonyFixtureEQUpdatesManualSlotAndKeepsCustomSlots() throws {
        let definition = try model("sony.wh1000xm5")
        XCTAssertTrue(definition.notes.contains("best guess"))
        XCTAssertEqual(definition.control(id: "ambientLevel")?.kind, .integerRange(1...20))
        XCTAssertEqual(definition.controls.filter { $0.id.hasPrefix("eqBand") }.count, 6)
        var state = VendorDemoState(model: definition)
        XCTAssertTrue(state.set(.option("16"), for: "eqPreset"))
        XCTAssertEqual(state["eqBand0"], .integer(6))
        XCTAssertEqual(state["eqBand1"], .integer(4))
        XCTAssertTrue(state.set(.integer(-3), for: "eqBand0"))
        XCTAssertEqual(state["eqPreset"], .option("a0"))
        XCTAssertTrue(state.set(.option("a1"), for: "eqPreset"))
        XCTAssertTrue(state.set(.integer(2), for: "eqBand2"))
        XCTAssertEqual(state["eqPreset"], .option("a1"))
        XCTAssertFalse(state.set(.integer(0), for: "ambientLevel"))
        XCTAssertFalse(state.set(.integer(11), for: "eqBand0"))
        XCTAssertTrue(try model("sony.wf1000xm5").controls.isEmpty, "No name-derived capabilities for another model")
        XCTAssertEqual(try model("sony.wf1000xm5").evidence, .noVendorControls)
    }

    func testMethodModelsExcludeCrusherAndSpatialServicesAndKeepFixtureRanges() throws {
        for (id, battery) in [("skullcandy.method360", 74), ("skullcandy.method540", 81)] {
            let definition = try model(id)
            XCTAssertTrue(definition.earbuds)
            XCTAssertEqual(definition.batteryFixture.first?.percent, battery)
            XCTAssertEqual(definition.control(id: "quietGain")?.kind, .integerRange(0...10))
            XCTAssertEqual(definition.control(id: "sidetoneVolume")?.kind, .integerRange(0...5))
            XCTAssertNil(definition.control(id: "crusherBass"))
            XCTAssertNil(definition.control(id: "spatial"))
            XCTAssertEqual(definition.documentedReadCount, 12)
            XCTAssertFalse(definition.labGroups.flatMap(\.reads).contains { $0.id.hasPrefix("17.") || $0.id.hasPrefix("23.") || $0.id.hasPrefix("25.") })
            var state = VendorDemoState(model: definition)
            XCTAssertTrue(state.set(.option("aware"), for: "mode"))
            XCTAssertTrue(state.set(.integer(0), for: "sidetoneVolume"))
            XCTAssertFalse(state.set(.integer(6), for: "sidetoneVolume"))
        }
    }

    func testAppleAndGenericModelsNeverInventControlsOrPrivateBatteryAccess() throws {
        for definition in VendorCatalogue.models where [.apple, .generic].contains(definition.vendor) {
            XCTAssertTrue(definition.controls.isEmpty)
            XCTAssertTrue(definition.labGroups.isEmpty)
            var state = VendorDemoState(model: definition)
            XCTAssertFalse(state.set(.option("anc"), for: "mode"))
        }
        let airpods = try model("apple.airpodsPro")
        XCTAssertEqual(airpods.batteryFixture.map(\.percent), [90, 80, 60])
        XCTAssertEqual(airpods.batteryFixture.map(\.charging), [false, false, true])
        XCTAssertTrue(airpods.notes.contains("simulated"))
        XCTAssertFalse(try model("apple.airpodsMax").earbuds)
    }

    func testPersistedDemoStateReconcilesInvalidUnknownAndCrossModelValues() throws {
        let definition = try model("sony.wh1000xm5")
        var state = VendorDemoState(model: definition)
        XCTAssertTrue(state.set(.integer(19), for: "ambientLevel"))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(VendorDemoState.self, from: data), state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var values = try XCTUnwrap(object["values"] as? [String: Any])
        values["ambientLevel"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(VendorControlValue.integer(999)))
        values["unknownFutureControl"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(VendorControlValue.boolean(true)))
        object["values"] = values
        var restored = try JSONDecoder().decode(VendorDemoState.self, from: JSONSerialization.data(withJSONObject: object))
        restored.reconcile(with: definition)
        XCTAssertEqual(restored["ambientLevel"], definition.control(id: "ambientLevel")?.initialValue)
        XCTAssertNil(restored["unknownFutureControl"])
        let another = try model("skullcandy.method360")
        restored.reconcile(with: another)
        XCTAssertEqual(restored, VendorDemoState(model: another))
    }

    func testLabMetadataContainsOnlyDocumentedReadsAndExplicitTransportRequirements() throws {
        for definition in VendorCatalogue.models {
            for group in definition.labGroups {
                XCTAssertEqual(Set(group.reads.map(\.id)).count, group.reads.count)
                XCTAssertTrue(group.reads.allSatisfy { !$0.requirement.isEmpty })
                XCTAssertFalse(group.reads.contains { read in
                    let name = read.title.lowercased()
                    return name.contains("factory reset") || name.contains("unpair") || name.contains("firmware update") || name.contains("reboot")
                })
            }
        }
        let sennheiserReads = try model("sennheiser.momentum4").labGroups.flatMap(\.reads).map(\.id)
        XCTAssertTrue(sennheiserReads.contains("0495.1a05"))
        XCTAssertFalse(sennheiserReads.contains("0495.1a04"), "ANC SET is not a documented read")
        XCTAssertFalse(sennheiserReads.contains("0495.1405"), "Pairing delete must remain absent")
    }

    private func model(_ id: String) throws -> VendorModelDefinition {
        try XCTUnwrap(VendorCatalogue.model(id: id), "Missing source-backed catalogue row: \(id)")
    }
}
