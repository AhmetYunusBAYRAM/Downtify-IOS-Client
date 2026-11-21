import XCTest
@testable import Downtify

final class MediaActionTests: XCTestCase {
    private let title = "Zebra Song"

    func testLibraryPresentationForEveryServerState() {
        let cases: [(ServerDownloadActionState, String, String?, Bool, String?)] = [
            (.idle, "Add to Library", "plus.circle", true, nil),
            (.submitting, "Adding to Library", nil, false, nil),
            (.queued(jobID: "job-1"), "Queued for Library", "clock.arrow.circlepath", false, nil),
            (.queued(jobID: nil), "Queued for Library", "clock.arrow.circlepath", false, nil),
            (.accepted, "In Library", "checkmark.circle.fill", false, nil),
            (.partiallyAccepted(successful: 2, expected: 3), "2 of 3 added to Library", "checkmark.circle", false, nil),
            (.outcomeUnknown, "Library status unknown", "questionmark.circle", false, nil),
            (.failed("Network down"), "Retry Add to Library", "exclamationmark.arrow.circlepath", true, "Network down"),
        ]
        for (state, expectedTitle, icon, enabled, explanation) in cases {
            let presentation = MediaActionPresentation.library(state, itemTitle: title)
            XCTAssertEqual(presentation.title, expectedTitle, "\(state)")
            XCTAssertEqual(presentation.systemImage, icon, "\(state)")
            XCTAssertEqual(presentation.isEnabled, enabled, "\(state)")
            XCTAssertEqual(presentation.explanation, explanation, "\(state)")
        }
    }

    func testOnlyIdleAndFailedLibraryStatesAreEnabled() {
        for state in libraryStates {
            let expected: Bool
            switch state {
            case .idle, .failed: expected = true
            default: expected = false
            }
            XCTAssertEqual(MediaActionPresentation.library(state, itemTitle: title).isEnabled, expected, "\(state)")
        }
    }

    func testFailedLibraryExplanationMatchesMessage() {
        let presentation = MediaActionPresentation.library(.failed("Quota exceeded"), itemTitle: title)
        XCTAssertEqual(presentation.explanation, "Quota exceeded")
    }

    func testSubmittingLibraryStateHasNoIcon() {
        XCTAssertNil(MediaActionPresentation.library(.submitting, itemTitle: title).systemImage)
    }

    func testDevicePresentationForEveryState() {
        let cases: [(DeviceSaveState, String, String?, Bool, String?)] = [
            (.unavailable(.notInLibrary), "Add to Device", "iphone.slash", false, "Add to Library first"),
            (.notSaved, "Add to Device", "arrow.down.to.line.circle", true, nil),
            (.pending, "Waiting to Add to Device", nil, false, nil),
            (.transferring(fraction: nil), "Adding to Device", nil, false, nil),
            (.transferring(fraction: 0.5), "Adding to Device", nil, false, nil),
            (.saved, "On Device", "arrow.down.to.line.circle.fill", false, nil),
            (.failed(.network), "Retry Add to Device", "exclamationmark.triangle", true, nil),
        ]
        for (state, expectedTitle, icon, enabled, explanation) in cases {
            let presentation = MediaActionPresentation.device(state, itemTitle: title)
            XCTAssertEqual(presentation.title, expectedTitle, "\(state)")
            XCTAssertEqual(presentation.systemImage, icon, "\(state)")
            XCTAssertEqual(presentation.isEnabled, enabled, "\(state)")
            XCTAssertEqual(presentation.explanation, explanation, "\(state)")
        }
    }

    func testOnlyNotSavedAndFailedDeviceStatesAreEnabled() {
        for state in deviceStates {
            let expected: Bool
            switch state {
            case .notSaved, .failed: expected = true
            default: expected = false
            }
            XCTAssertEqual(MediaActionPresentation.device(state, itemTitle: title).isEnabled, expected, "\(state)")
        }
    }

    func testNotInLibraryDeviceStateIsDisabledWithExplanation() {
        let presentation = MediaActionPresentation.device(.unavailable(.notInLibrary), itemTitle: title)
        XCTAssertFalse(presentation.isEnabled)
        XCTAssertNotNil(presentation.explanation)
    }

    func testDeviceSaveStateWithoutTrackIsNotInLibrary() {
        XCTAssertEqual(DeviceSaveState(track: nil, record: record(state: .ready, bytes: 8)),
                       .unavailable(.notInLibrary))
        XCTAssertEqual(DeviceSaveState(track: nil, record: nil), .unavailable(.notInLibrary))
    }

    func testDeviceSaveStateWithTrackMapsRecordState() {
        let track = track()
        XCTAssertEqual(DeviceSaveState(track: track, record: nil), .notSaved)
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .preparing, bytes: 0)), .pending)
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .paused, bytes: 3)), .pending)
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .transferring, bytes: 3)),
                       .transferring(fraction: 0.375))
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .transferring, bytes: 3, hasMedia: false)),
                       .transferring(fraction: nil))
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .transferring, bytes: 20)),
                       .transferring(fraction: 1))
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .ready, bytes: 8)), .saved)
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .cancelled, bytes: 3)), .notSaved)
        XCTAssertEqual(DeviceSaveState(track: track, record: record(state: .failed(.insufficientStorage), bytes: 3)),
                       .failed(.insufficientStorage))
    }

    func testLibraryAndDeviceIconsAreDisjointAndExcludeLegacyIcon() {
        let libraryIcons = Set(libraryStates.compactMap {
            MediaActionPresentation.library($0, itemTitle: title).systemImage
        })
        let deviceIcons = Set(deviceStates.compactMap {
            MediaActionPresentation.device($0, itemTitle: title).systemImage
        })
        XCTAssertTrue(libraryIcons.isDisjoint(with: deviceIcons))
        XCTAssertFalse(libraryIcons.contains("arrow.down.circle"))
        XCTAssertFalse(deviceIcons.contains("arrow.down.circle"))
    }

    func testEveryAccessibilityLabelContainsItemTitle() {
        for state in libraryStates {
            let label = MediaActionPresentation.library(state, itemTitle: title).accessibilityLabel
            XCTAssertTrue(label.contains(title), "\(state): \(label)")
        }
        for state in deviceStates {
            let label = MediaActionPresentation.device(state, itemTitle: title).accessibilityLabel
            XCTAssertTrue(label.contains(title), "\(state): \(label)")
        }
    }

    // MARK: - Fixtures

    private var libraryStates: [ServerDownloadActionState] {
        [
            .idle, .submitting, .queued(jobID: nil), .accepted,
            .partiallyAccepted(successful: 2, expected: 3), .outcomeUnknown, .failed("Network down"),
        ]
    }

    private var deviceStates: [DeviceSaveState] {
        [
            .unavailable(.notInLibrary), .notSaved, .pending, .transferring(fraction: nil),
            .transferring(fraction: 0.5), .saved, .failed(.network),
        ]
    }

    private func track() -> LibraryTrack {
        LibraryTrack(id: "song", file: "Song.mp3", title: title, artist: "Artist", artists: [],
                     album: "", albumArtist: "", albumID: "", artistID: "", trackNumber: 0, year: "",
                     duration: 60, codec: "mp3", bitrate: 0, sampleRate: 0, channels: 0, size: 8,
                     added: 0, hasCover: false, isExplicit: false, playlists: [])
    }

    private func session() -> DeviceSession {
        DeviceSession(baseAddress: "https://music.local/proxy", serverID: "server", serverName: "Music",
                      deviceID: "device", username: "user", role: nil, token: "test-token", allowsInsecureHTTP: false)
    }

    private func media() -> OfflineMedia {
        OfflineMedia(length: 8, mime: "audio/mpeg", type: "public.mp3",
                     fileExtension: "mp3", etag: "\"version\"", quality: .original)
    }

    private func record(state: OfflineDownload.State, bytes: Int64, hasMedia: Bool = true) -> OfflineDownload {
        OfflineDownload(id: UUID(), track: track(), scope: .init(session()), requestedQuality: .original,
                        state: state, media: hasMedia ? media() : nil, receivedBytes: bytes)
    }

    func testAlbumAddBelowThresholdNeedsNoConfirmation() {
        XCTAssertNil(AlbumAddConfirmation.make(albumTitle: "Small Album", trackCount: 5))
        XCTAssertNil(AlbumAddConfirmation.make(albumTitle: "Small Album", trackCount: 19))
    }

    func testAlbumAddAtThresholdNeedsConfirmationWithCount() throws {
        let confirmation = try XCTUnwrap(AlbumAddConfirmation.make(albumTitle: "Big Album", trackCount: 20))
        XCTAssertTrue(confirmation.message.contains("20"), confirmation.message)
        XCTAssertFalse(confirmation.message.contains("unknown"), confirmation.message)
    }

    func testAlbumAddUnknownCountNeedsConfirmation() throws {
        let unknown = try XCTUnwrap(AlbumAddConfirmation.make(albumTitle: "Mystery Album", trackCount: nil))
        XCTAssertTrue(unknown.message.contains("unknown"), unknown.message)
        let zero = try XCTUnwrap(AlbumAddConfirmation.make(albumTitle: "Mystery Album", trackCount: 0))
        XCTAssertEqual(zero, unknown)
    }

    func testAlbumAddConfirmationTitleContainsAlbumTitle() throws {
        let confirmation = try XCTUnwrap(AlbumAddConfirmation.make(albumTitle: "Zebra Album", trackCount: nil))
        XCTAssertTrue(confirmation.title.contains("Zebra Album"), confirmation.title)
    }
}
