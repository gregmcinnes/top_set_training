import XCTest

/// The Watch can't use the shared colour catalogue (actool drops dark appearances
/// for watchOS), so scripts/make_watch_tokens.py writes SBSWatch/WatchTokens.xcassets
/// with each token's Iron value. This fails when a token changes and the script
/// wasn't rerun.
final class WatchTokensTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func colorsets(in catalogue: String) throws -> [String: URL] {
        let dir = root.appendingPathComponent(catalogue).appendingPathComponent("Colors")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".colorset") }
        return Dictionary(uniqueKeysWithValues: names.map { ($0, dir.appendingPathComponent($0)) })
    }

    private func entries(_ colorset: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: colorset.appendingPathComponent("Contents.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["colors"] as? [[String: Any]])
    }

    private func components(_ entry: [String: Any]) -> NSDictionary? {
        (entry["color"] as? [String: Any])?["components"] as? NSDictionary
    }

    func testWatchTokensAreTheSharedIronValues() throws {
        let shared = try colorsets(in: "Shared/Tokens.xcassets")
        let watch = try colorsets(in: "SBSWatch/WatchTokens.xcassets")
        XCTAssertFalse(shared.isEmpty)
        XCTAssertEqual(Set(shared.keys), Set(watch.keys),
                       "Token added or removed: run scripts/make_watch_tokens.py")

        for (name, url) in shared {
            let sharedEntries = try entries(url)
            let dark = sharedEntries.first { entry in
                (entry["appearances"] as? [[String: String]])?
                    .contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" } ?? false
            } ?? sharedEntries[0]
            guard let watchURL = watch[name] else { continue }
            let watchEntries = try entries(watchURL)
            XCTAssertEqual(watchEntries.count, 1, name)
            XCTAssertEqual(components(watchEntries[0]), components(dark),
                           "\(name) differs: run scripts/make_watch_tokens.py")
        }
    }
}
