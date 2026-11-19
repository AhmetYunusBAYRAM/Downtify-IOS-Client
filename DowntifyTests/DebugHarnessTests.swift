#if DEBUG
import Foundation
import XCTest
@testable import Downtify

@MainActor
final class DebugHarnessTests: XCTestCase {
    private let harnessArgs = ["-DowntifyHarness"]
    private let stagingArgs = ["-DowntifyHarness", "-DowntifyHarnessMode", "staging"]

    // MARK: Activation and fixture defaults

    func testHarnessIsInactiveWithoutFlag() {
        XCTAssertNil(DebugHarnessConfiguration.parse(arguments: ["-other"], environment: [:]))
    }

    func testFixtureModeIsDefault() throws {
        let config = try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: harnessArgs, environment: [:]))
        XCTAssertEqual(config.mode, .fixture)
        XCTAssertNil(config.staging)
        XCTAssertNil(config.configurationError)
    }

    // MARK: Fault parsing

    func testFaultsParsePerRoute() {
        let faults = DebugHarnessConfiguration.parseFaults(
            ["-DowntifyFault", "stream=http500", "-DowntifyFault", "library=timeout", "-DowntifyFault", "bogus=offline"])
        XCTAssertEqual(faults, [.stream: .http500, .library: .timeout])
    }

    func testFaultTransportThrowsTimeoutAndReturnsStatusCodes() async throws {
        let url = try XCTUnwrap(URL(string: "https://fixture.test/api/v1/library"))
        let timeout = DebugFixtureTransport(faults: [.library: .timeout])
        do {
            _ = try await timeout.data(for: URLRequest(url: url))
            XCTFail("expected timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        let server = DebugFixtureTransport(faults: [.library: .http500])
        let (_, response) = try await server.data(for: URLRequest(url: url))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 500)

        let auth = DebugFixtureTransport(faults: [.library: .unauthorized])
        let (_, unauthorized) = try await auth.data(for: URLRequest(url: url))
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)
    }

    func testFixtureSignInCompletesThroughConnectionService() async throws {
        let connection = ConnectionService(transport: DebugFixtureTransport(faults: [:]),
                                           store: DebugMemorySessionStore())
        let target = try await connection.probe("https://fixture.test")
        let session = try await connection.signIn(username: "fixture", password: "fixture-password",
                                                  at: target, deviceName: "Harness")
        XCTAssertEqual(session.serverID, DebugFixtureTransport.serverID)
    }

    // MARK: Staging fail-closed rules

    func testStagingFailsClosedOnDisallowedHost() throws {
        let env = ["DOWNTIFY_TEST_SERVER": "https://music.example.com", "DOWNTIFY_TEST_USER": "u", "DOWNTIFY_TEST_PASSWORD": "p"]
        let config = try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: stagingArgs, environment: env))
        XCTAssertNil(config.staging)
        XCTAssertEqual(config.configurationError, .hostNotAllowed)
    }

    func testStagingFailsClosedWhenServerOrCredentialsMissing() throws {
        let noServer = try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: stagingArgs, environment: [:]))
        XCTAssertEqual(noServer.configurationError, .missingStagingServer)
        let noCreds = try XCTUnwrap(DebugHarnessConfiguration.parse(
            arguments: stagingArgs, environment: ["DOWNTIFY_TEST_SERVER": "http://localhost:8000"]))
        XCTAssertEqual(noCreds.configurationError, .missingStagingCredentials)
    }

    func testAllowedHostDeclarationMustMatch() throws {
        let env = ["DOWNTIFY_TEST_SERVER": "http://localhost:8000", "DOWNTIFY_TEST_USER": "u",
                   "DOWNTIFY_TEST_PASSWORD": "p", "DOWNTIFY_TEST_ALLOWED_HOST": "other.localhost"]
        XCTAssertEqual(try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: stagingArgs, environment: env))
            .configurationError, .hostMismatch)
    }

    func testHostAllowList() {
        for host in ["localhost", "127.0.0.1", "::1", "[::1]", "app.localhost", "x.test", "staging.example.com", "qa.example.org"] {
            XCTAssertTrue(DebugHarnessConfiguration.isAllowedHost(host), host)
        }
        for host in ["music.example.com", "downtify.app", "192.168.1.10"] {
            XCTAssertFalse(DebugHarnessConfiguration.isAllowedHost(host), host)
        }
    }

    // MARK: Mutation rules

    func testMutationsOnlyOnLoopbackWithOptIn() throws {
        let loopback = try staging(server: "http://127.0.0.1:8000", allowMutations: "1")
        XCTAssertTrue(loopback.allowsMutations)

        let remoteStaging = try staging(server: "https://staging.example.com", allowMutations: "1")
        XCTAssertFalse(remoteStaging.allowsMutations, "remote staging hosts are read-only even with opt-in")

        let noOptIn = try staging(server: "http://localhost:8000", allowMutations: nil)
        XCTAssertFalse(noOptIn.allowsMutations)
    }

    func testGuardRefusesMutationWithoutOptInAndForeignHosts() throws {
        let config = try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: stagingArgs, environment: [
            "DOWNTIFY_TEST_SERVER": "https://staging.example.com", "DOWNTIFY_TEST_USER": "u",
            "DOWNTIFY_TEST_PASSWORD": "p", "DOWNTIFY_TEST_ALLOW_MUTATIONS": "1"]))

        var post = URLRequest(url: try XCTUnwrap(URL(string: "https://staging.example.com/api/v1/likes")))
        post.httpMethod = "POST"
        XCTAssertThrowsError(try DebugGuardedTransport.authorize(post, configuration: config)) {
            XCTAssertEqual($0 as? DebugHarnessError, .mutationRefused)
        }

        let other = URLRequest(url: try XCTUnwrap(URL(string: "https://elsewhere.staging.example.com/api/v1/library")))
        XCTAssertThrowsError(try DebugGuardedTransport.authorize(other, configuration: config)) {
            XCTAssertEqual($0 as? DebugHarnessError, .hostMismatch)
        }

        var signIn = URLRequest(url: try XCTUnwrap(URL(string: "https://staging.example.com/api/auth/token")))
        signIn.httpMethod = "POST"
        XCTAssertNoThrow(try DebugGuardedTransport.authorize(signIn, configuration: config))

        var otherPost = URLRequest(url: try XCTUnwrap(URL(string: "https://staging.example.com/api/auth/pair")))
        otherPost.httpMethod = "POST"
        XCTAssertThrowsError(try DebugGuardedTransport.authorize(otherPost, configuration: config))

        let get = URLRequest(url: try XCTUnwrap(URL(string: "https://staging.example.com/api/v1/library")))
        XCTAssertNoThrow(try DebugGuardedTransport.authorize(get, configuration: config))
    }

    func testInvalidConfigurationRefusesAllTraffic() throws {
        let config = try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: stagingArgs, environment: [:]))
        let get = URLRequest(url: try XCTUnwrap(URL(string: "http://localhost:8000/api/v1/library")))
        XCTAssertThrowsError(try DebugGuardedTransport.authorize(get, configuration: config))
    }

    // MARK: Redaction

    func testSnapshotContainsOnlyApprovedKeysAndNoSecrets() throws {
        let snapshot = DebugStateSnapshot(playbackPhase: "playing", queueCount: 2, currentTrackID: "fixture-track-1",
                                          position: 1.5, network: "wifiOrWired", libraryTrackCount: 2,
                                          lastErrorCode: nil, artworkLoaded: true, playerVisible: true, sessionActive: true)
        let json = snapshot.json
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["playbackPhase", "queueCount", "currentTrackID", "position", "network",
                                          "libraryTrackCount", "lastErrorCode", "artworkLoaded", "playerVisible", "sessionActive"])
        for forbidden in ["token", "username", "password", "http", "server", "title", DebugFixtureTransport.token, "fixture-server"] {
            XCTAssertFalse(json.lowercased().contains(forbidden.lowercased()), forbidden)
        }
    }

    // MARK: Isolation

    func testHarnessWritesNothingToStandardDefaults() throws {
        let before = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let harness = DebugHarness(configuration: try XCTUnwrap(
            DebugHarnessConfiguration.parse(arguments: harnessArgs, environment: [:])))
        let defaults = harness.makeDefaults()
        PlaybackStateStore(defaults: defaults).saveImmediateQualitySwitch(true)
        defaults.set("probe", forKey: "debug.harness.probe")
        XCTAssertEqual(defaults.string(forKey: "debug.harness.probe"), "probe")

        XCTAssertEqual(Set(UserDefaults.standard.dictionaryRepresentation().keys), before)
    }

    private func staging(server: String, allowMutations: String?) throws -> DebugHarnessConfiguration.StagingTarget {
        var env = ["DOWNTIFY_TEST_SERVER": server, "DOWNTIFY_TEST_USER": "u", "DOWNTIFY_TEST_PASSWORD": "p"]
        if let allowMutations { env["DOWNTIFY_TEST_ALLOW_MUTATIONS"] = allowMutations }
        return try XCTUnwrap(DebugHarnessConfiguration.parse(arguments: stagingArgs, environment: env).flatMap(\.staging))
    }
}
#endif
