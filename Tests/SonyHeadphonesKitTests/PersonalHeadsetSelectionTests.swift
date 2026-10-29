import XCTest
@testable import SonyHeadphonesKit

final class PersonalHeadsetSelectionTests: XCTestCase {
    private let unrelated = [
        PairedDeviceInfo(id: "01", name: "Magic Keyboard"),
        PairedDeviceInfo(id: "02", name: "iPhone de Marie"),
        PairedDeviceInfo(id: "03", name: "AirPods Pro")
    ]

    func testSingleFactoryHeadsetIsChosen() {
        let xm6 = PairedDeviceInfo(id: "AA", name: "WH-1000XM6")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: unrelated + [xm6], rememberedAddress: nil),
            xm6
        )
    }

    func testSingleCustomXMNameIsChosen() {
        let custom = PairedDeviceInfo(id: "AA", name: "Mon XM6")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: unrelated + [custom], rememberedAddress: nil),
            custom
        )
    }

    func testCustomDisplayNameExactMatchWins() {
        let mine = PairedDeviceInfo(id: "AA", name: "Casque de Marie")
        let other = PairedDeviceInfo(id: "BB", name: "WH-1000XM5")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: [mine, other], rememberedAddress: nil, customName: "Casque de Marie"),
            mine
        )
    }

    func testXM4AndXM5AreRecognized() {
        let xm4 = PairedDeviceInfo(id: "AA", name: "WH-1000XM4")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: unrelated + [xm4], rememberedAddress: nil),
            xm4
        )
        let xm5 = PairedDeviceInfo(id: "BB", name: "Mon XM5")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: unrelated + [xm5], rememberedAddress: nil),
            xm5
        )
    }

    func testStraightCaseIsAccepted() {
        let xm = PairedDeviceInfo(id: "AA", name: "MON XM6")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: [xm], rememberedAddress: nil),
            xm
        )
    }

    func testRememberedAddressWorksAfterRenaming() {
        let renamed = PairedDeviceInfo(id: "aa:bb", name: "Mon casque blanc")
        XCTAssertEqual(PersonalHeadsetSelection.preferred(in: unrelated + [renamed], rememberedAddress: "AA:BB"), renamed)
    }

    func testMissingRememberedHeadsetNeverSelectsSomeoneElses() {
        let other = PairedDeviceInfo(id: "BB", name: "WH-1000XM6")
        XCTAssertNil(PersonalHeadsetSelection.preferred(in: unrelated + [other], rememberedAddress: "AA"))
    }

    func testAmbiguousHeadsetsRequireAnExplicitChoice() {
        XCTAssertNil(PersonalHeadsetSelection.preferred(in: [
            PairedDeviceInfo(id: "AA", name: "WH-1000XM6"),
            PairedDeviceInfo(id: "BB", name: "WH-1000XM6")
        ], rememberedAddress: nil))
    }

    func testNoUnrelatedDeviceIsSelected() {
        XCTAssertNil(PersonalHeadsetSelection.preferred(in: unrelated, rememberedAddress: nil))
        XCTAssertNil(PersonalHeadsetSelection.preferred(in: [], rememberedAddress: nil))
    }

    func testModelPreferenceDisambiguates() {
        let xm4 = PairedDeviceInfo(id: "AA", name: "WH-1000XM4")
        let xm6 = PairedDeviceInfo(id: "BB", name: "WH-1000XM6")
        XCTAssertEqual(
            PersonalHeadsetSelection.preferred(in: [xm4, xm6], rememberedAddress: nil, preferredModel: .xm4),
            xm4
        )
    }
}
