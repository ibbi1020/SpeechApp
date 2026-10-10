import Foundation

public enum RecordingStoreError: Error, Equatable, Sendable {
    case diskFull
    case ioFailed(String)
}

/// On-device regimen store. Root directory is injected so tests can use a temp folder.
public final class RecordingStore: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func prepareRoot(excludeFromBackup: Bool = true) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if excludeFromBackup {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = rootURL
            try url.setResourceValues(values)
        }
    }

    public func regimenDirectory(id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func list(format: RecordingManifest.Format? = nil) throws -> [RecordingManifest] {
        try prepareRoot(excludeFromBackup: false)
        let contents = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var manifests: [RecordingManifest] = []
        for dir in contents where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(RecordingManifest.self, from: data)
            else { continue }
            if let format, manifest.format != format { continue }
            manifests.append(manifest)
        }
        return manifests.sorted { $0.createdAt > $1.createdAt }
    }

    public func load(id: UUID) throws -> RecordingManifest? {
        let url = regimenDirectory(id: id).appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(RecordingManifest.self, from: data)
    }

    public func audioURL(regimenID: UUID, fileName: String) -> URL {
        regimenDirectory(id: regimenID).appendingPathComponent(fileName)
    }

    /// Creates the regimen folder and writes the manifest. Caller places audio files first.
    public func save(_ manifest: RecordingManifest) throws {
        try prepareRoot()
        let dir = regimenDirectory(id: manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(values)

        let data: Data
        do {
            data = try encoder.encode(manifest)
        } catch {
            throw RecordingStoreError.ioFailed(error.localizedDescription)
        }
        let manifestURL = dir.appendingPathComponent("manifest.json")
        do {
            try data.write(to: manifestURL, options: .atomic)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
                throw RecordingStoreError.diskFull
            }
            throw RecordingStoreError.ioFailed(error.localizedDescription)
        }
    }

    public func delete(id: UUID) throws {
        let dir = regimenDirectory(id: id)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    public func deleteAll() throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
        try prepareRoot()
    }

    /// Copy a finished take audio file into the regimen folder.
    public func storeAudio(regimenID: UUID, from source: URL, fileName: String) throws -> URL {
        try prepareRoot()
        let dir = regimenDirectory(id: regimenID)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        do {
            try fileManager.copyItem(at: source, to: dest)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError {
                throw RecordingStoreError.diskFull
            }
            throw RecordingStoreError.ioFailed(error.localizedDescription)
        }
        return dest
    }
}
