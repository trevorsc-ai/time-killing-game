import XCTest
@testable import PuzzleGetaway

final class ContentTests: XCTestCase {
    func testContentLoadsAndEveryModeIsRegistered() throws {
        let content = try ContentStore.load()
        XCTAssertFalse(content.allLevels.isEmpty)
        XCTAssertEqual(content.destinations.count, 8)
        XCTAssertGreaterThanOrEqual(content.palette.colors.count, 12)
        XCTAssertNotNil(content.pools["daily"])
        XCTAssertNotNil(content.pools["relax-liquid"])
        for level in content.everyLevel {
            XCTAssertNotNil(ModeRegistry.plugin(for: level.mode), "mode \(level.mode) of \(level.id) is not registered")
        }
    }

    func testDestinationsAndPalette() throws {
        let content = try ContentStore.load()
        XCTAssertEqual(content.destination(id: "d1")?.name, "Station Snack Cart")
        XCTAssertEqual(content.destination(id: "d1")?.restorationStages.count, 6)
        XCTAssertTrue(content.destination(id: "d5")?.comingSoon ?? false)
        XCTAssertEqual(content.palette.color("r")?.symbol, "circle.fill")
    }

    func testDemoLevelPayloadDecodes() throws {
        let content = try ContentStore.load()
        let level = try XCTUnwrap(content.level(id: "demo-demo-01"))
        let payload = try level.decodePayload(DemoPayload.self)
        XCTAssertEqual(payload.target, 7)
        XCTAssertEqual(try level.decodeSolution(DemoMove.self).count, level.par)
    }

    func testJSONValueRoundTrip() throws {
        let json = #"{"a":[1,2.5,"x",true,null],"b":{"c":3}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(value["b"]?["c"], .int(3))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(value, again)
    }

    func testEnvelopeOrdersAreUniquePerDestination() throws {
        let content = try ContentStore.load()
        var seen = Set<String>()
        for l in content.allLevels {
            XCTAssertTrue(seen.insert("\(l.destination)#\(l.order)").inserted, "duplicate order for \(l.id)")
        }
    }
}
