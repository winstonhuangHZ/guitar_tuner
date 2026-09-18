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
    @discardableResult
    public static func request() async -> MicrophonePermissionStatus {
        let status = current
        guard status == .undetermined else { return status }

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
