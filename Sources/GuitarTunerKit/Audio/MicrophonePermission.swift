import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

public enum MicrophonePermissionStatus: Sendable, Equatable {
    case undetermined
    case granted
    case denied
    /// No capture API on this platform/session.
    case unavailable
}

/// Thin wrapper over the platform microphone permission APIs so the rest of the code
/// can ask for access with a single `await`.
public enum MicrophonePermission {
    public static var current: MicrophonePermissionStatus {
        #if os(iOS) || os(tvOS)
        if #available(iOS 17.0, tvOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
        #else
        return .unavailable
        #endif
    }

    /// Requests access if it has not been decided yet; returns the resulting status.
    ///
    /// The request is *polled* rather than awaited. A request that macOS cannot attribute
    /// to an app — a bare `swift run` binary is the classic case — may never call its
    /// completion handler, and awaiting it would strand the UI on "waiting for
    /// microphone access" forever. Polling the system status returns as soon as the user
    /// answers, and gives up after `timeout` so the caller can try the capture anyway
    /// (or report a useful error) instead of hanging.
    @discardableResult
    public static func request(timeout: TimeInterval = 8) async -> MicrophonePermissionStatus {
        let status = current
        guard status == .undetermined else { return status }

        // Fire and forget: the task answers the prompt if it ever gets one.
        let request = Task { await performSystemRequest() }

        let deadline = Date().addingTimeInterval(max(timeout, 1))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let latest = current
            if latest != .undetermined { return latest }
        }

        _ = request
        // Still undetermined: let the caller decide what to do about it.
        return current
    }

    private static func performSystemRequest() async -> MicrophonePermissionStatus {
        #if os(iOS) || os(tvOS)
        if #available(iOS 17.0, tvOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            return granted ? .granted : .denied
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        }
        #elseif os(macOS)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
        #else
        return .unavailable
        #endif
    }
}
