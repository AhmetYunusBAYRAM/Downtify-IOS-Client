import Foundation

enum MediaDestination { case library, device }

enum DeviceUnavailableReason: Equatable { case notInLibrary }

/// Derived from the library track and offline record; never stored.
enum DeviceSaveState: Equatable {
    case unavailable(DeviceUnavailableReason)
    case notSaved
    case pending
    case transferring(fraction: Double?)
    case saved
    case failed(OfflineDownloadFailure)

    init(track: LibraryTrack?, record: OfflineDownload?) {
        guard track != nil else { self = .unavailable(.notInLibrary); return }
        guard let record else { self = .notSaved; return }
        switch record.state {
        case .preparing, .paused:
            self = .pending
        case .transferring:
            if let length = record.media?.length, length > 0 {
                let fraction = Double(record.receivedBytes) / Double(length)
                self = .transferring(fraction: min(max(fraction, 0), 1))
            } else {
                self = .transferring(fraction: nil)
            }
        case .ready:
            self = .saved
        case .cancelled:
            self = .notSaved
        case .failed(let failure):
            self = .failed(failure)
        }
    }
}

struct MediaActionPresentation: Equatable {
    let title: String
    let systemImage: String?
    let accessibilityLabel: String
    let isEnabled: Bool
    let explanation: String?

    static func library(_ state: ServerDownloadActionState, itemTitle t: String) -> Self {
        switch state {
        case .idle:
            return Self(title: String(localized: "Add to Library"), systemImage: "plus.circle",
                        accessibilityLabel: String(localized: "Add \(t) to Library"),
                        isEnabled: true, explanation: nil)
        case .submitting:
            return Self(title: String(localized: "Adding to Library"), systemImage: nil,
                        accessibilityLabel: String(localized: "Adding \(t) to Library"),
                        isEnabled: false, explanation: nil)
        case .queued:
            return Self(title: String(localized: "Queued for Library"), systemImage: "clock.arrow.circlepath",
                        accessibilityLabel: String(localized: "\(t) is queued for your Library"),
                        isEnabled: false, explanation: nil)
        case .accepted:
            return Self(title: String(localized: "In Library"), systemImage: "checkmark.circle.fill",
                        accessibilityLabel: String(localized: "\(t) is in your Library"),
                        isEnabled: false, explanation: nil)
        case .partiallyAccepted(let successful, let expected):
            return Self(title: String(localized: "\(successful) of \(expected) added to Library"),
                        systemImage: "checkmark.circle",
                        accessibilityLabel: String(localized: "\(successful) of \(expected) added to Library for \(t)"),
                        isEnabled: false, explanation: nil)
        case .outcomeUnknown:
            return Self(title: String(localized: "Library status unknown"), systemImage: "questionmark.circle",
                        accessibilityLabel: String(localized: "Library status unknown for \(t)"),
                        isEnabled: false, explanation: nil)
        case .failed(let message):
            return Self(title: String(localized: "Retry Add to Library"), systemImage: "exclamationmark.arrow.circlepath",
                        accessibilityLabel: String(localized: "Retry adding \(t) to Library"),
                        isEnabled: true, explanation: message)
        }
    }

    static func device(_ state: DeviceSaveState, itemTitle t: String) -> Self {
        switch state {
        case .unavailable(.notInLibrary):
            return Self(title: String(localized: "Add to Device"), systemImage: "iphone.slash",
                        accessibilityLabel: String(localized: "\(t) must be in your Library before it can be added to this device"),
                        isEnabled: false, explanation: String(localized: "Add to Library first"))
        case .notSaved:
            return Self(title: String(localized: "Add to Device"), systemImage: "arrow.down.to.line.circle",
                        accessibilityLabel: String(localized: "Add \(t) to this device"),
                        isEnabled: true, explanation: nil)
        case .pending:
            return Self(title: String(localized: "Waiting to Add to Device"), systemImage: nil,
                        accessibilityLabel: String(localized: "Waiting to add \(t) to this device"),
                        isEnabled: false, explanation: nil)
        case .transferring:
            return Self(title: String(localized: "Adding to Device"), systemImage: nil,
                        accessibilityLabel: String(localized: "Adding \(t) to this device"),
                        isEnabled: false, explanation: nil)
        case .saved:
            return Self(title: String(localized: "On Device"), systemImage: "arrow.down.to.line.circle.fill",
                        accessibilityLabel: String(localized: "\(t) is on this device"),
                        isEnabled: false, explanation: nil)
        case .failed:
            return Self(title: String(localized: "Retry Add to Device"), systemImage: "exclamationmark.triangle",
                        accessibilityLabel: String(localized: "Retry adding \(t) to this device"),
                        isEnabled: true, explanation: nil)
        }
    }
}
