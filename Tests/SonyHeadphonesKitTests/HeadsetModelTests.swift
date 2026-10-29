import XCTest
@testable import SonyHeadphonesKit

final class HeadsetModelTests: XCTestCase {
    func testDetectFromFactoryNames() {
        XCTAssertEqual(HeadsetModel.detect(fromName: "WH-1000XM4"), .xm4)
        XCTAssertEqual(HeadsetModel.detect(fromName: "WH-1000XM5"), .xm5)
        XCTAssertEqual(HeadsetModel.detect(fromName: "WH-1000XM6"), .xm6)
    }

    func testDetectFromCustomNames() {
        XCTAssertEqual(HeadsetModel.detect(fromName: "Mon XM6"), .xm6)
        XCTAssertEqual(HeadsetModel.detect(fromName: "Casque de Marie XM5"), .xm5)
        XCTAssertEqual(HeadsetModel.detect(fromName: "XM4"), .xm4)
        XCTAssertNil(HeadsetModel.detect(fromName: "AirPods Pro"))
        XCTAssertNil(HeadsetModel.detect(fromName: "Magic Keyboard"))
    }

    func testCustomCurvesAreValidCustomWrites() {
        for curve in CustomEqualizerCurve.allCases {
            XCTAssertEqual(curve.bands.count, SonyCommands.defaultBandCount, "\(curve.rawValue) must have 10 bands")
            XCTAssertTrue(
                curve.bands.allSatisfy { SonyCommands.bandGainRange.contains($0) },
                "\(curve.rawValue) gains must fit -6…+6"
            )
        }
    }

    func testModelPreferenceRoundTrips() {
        XCTAssertEqual(HeadsetModelPreference.fromStored(nil), .auto)
        XCTAssertEqual(HeadsetModelPreference.fromStored("XM5").model, .xm5)
        XCTAssertEqual(HeadsetModelPreference.fromStored("nope"), .auto)
    }
}
