import ApplicationServices
import AVFoundation
import Foundation

@MainActor
final class PermissionsService: ObservableObject {
    enum PermissionState: String {
        case granted
        case denied
        case notDetermined
    }

    @Published private(set) var microphoneState: PermissionState = .notDetermined
    @Published private(set) var accessibilityState: PermissionState = .notDetermined

    init() {
        refresh()
    }

    func refresh() {
        microphoneState = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }

        accessibilityState = AXIsProcessTrusted() ? .granted : .notDetermined
    }

    func requestMicrophoneAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    func requestAccessibilityAccess(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        refresh()
        return granted
    }
}
