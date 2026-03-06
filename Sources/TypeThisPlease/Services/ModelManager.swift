import Foundation

struct WhisperInstallationStatus: Equatable, Sendable {
    var runtimeURL: URL?
    var modelURL: URL?
    var runtimeExists: Bool
    var modelExists: Bool
    var runtimeDownloadInProgress: Bool
    var modelDownloadInProgress: Bool
    var lastError: String?
}

actor ModelManager {
    enum ModelError: LocalizedError {
        case invalidRuntimeURL
        case invalidModelURL
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidRuntimeURL:
                return "The runtime download URL is invalid."
            case .invalidModelURL:
                return "The model download URL is invalid."
            case .downloadFailed(let message):
                return message
            }
        }
    }

    private let fileManager = FileManager.default
    private let appSupportURL: URL
    private var runtimeDownloadInProgress = false
    private var modelDownloadInProgress = false
    private var lastError: String?

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportURL = appSupport.appendingPathComponent("TypeThisPlease", isDirectory: true)
    }

    func runtimeStorageURL() -> URL {
        appSupportURL.appendingPathComponent("runtime").appendingPathComponent("whisper-cli")
    }

    func modelStorageURL() -> URL {
        appSupportURL.appendingPathComponent("models").appendingPathComponent("whisper-model.bin")
    }

    func status(configuration: WhisperConfiguration) -> WhisperInstallationStatus {
        let runtimeURL = resolvedRuntimeURL(configuration: configuration)
        let modelURL = resolvedModelURL(configuration: configuration)

        return WhisperInstallationStatus(
            runtimeURL: runtimeURL,
            modelURL: modelURL,
            runtimeExists: runtimeURL.map { fileManager.fileExists(atPath: $0.path) } ?? false,
            modelExists: modelURL.map { fileManager.fileExists(atPath: $0.path) } ?? false,
            runtimeDownloadInProgress: runtimeDownloadInProgress,
            modelDownloadInProgress: modelDownloadInProgress,
            lastError: lastError
        )
    }

    func downloadRuntime(configuration: WhisperConfiguration) async throws -> URL {
        guard let remoteURL = URL(string: configuration.runtimeDownloadURL), !configuration.runtimeDownloadURL.isEmpty else {
            throw ModelError.invalidRuntimeURL
        }

        runtimeDownloadInProgress = true
        defer { runtimeDownloadInProgress = false }
        let destination = runtimeStorageURL()
        do {
            let url = try await downloadFile(from: remoteURL, to: destination, makeExecutable: true)
            lastError = nil
            return url
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func downloadModel(configuration: WhisperConfiguration) async throws -> URL {
        guard let remoteURL = URL(string: configuration.modelDownloadURL), !configuration.modelDownloadURL.isEmpty else {
            throw ModelError.invalidModelURL
        }

        modelDownloadInProgress = true
        defer { modelDownloadInProgress = false }
        let destination = modelStorageURL()
        do {
            let url = try await downloadFile(from: remoteURL, to: destination, makeExecutable: false)
            lastError = nil
            return url
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func resolvedRuntimeURL(configuration: WhisperConfiguration) -> URL? {
        if !configuration.executablePath.isEmpty {
            return URL(fileURLWithPath: configuration.executablePath)
        }
        return runtimeStorageURL()
    }

    private func resolvedModelURL(configuration: WhisperConfiguration) -> URL? {
        if !configuration.modelPath.isEmpty {
            return URL(fileURLWithPath: configuration.modelPath)
        }
        return modelStorageURL()
    }

    private func downloadFile(from remoteURL: URL, to destination: URL, makeExecutable: Bool) async throws -> URL {
        try ensureParentDirectory(for: destination)
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ModelError.downloadFailed("Download failed with a non-success status code.")
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        if makeExecutable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
        return destination
    }

    private func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
}
