import Foundation

public enum JointTodoPaths {
    public static func defaultDataFile() -> URL {
        if let override = ProcessInfo.processInfo.environment["JOINTODO_DATA_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("JointTodo", isDirectory: true)
            .appendingPathComponent("jointodo.json")
    }
}

public enum TodoPersistence {
    public static func load(from url: URL) throws -> TodoLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .starter
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TodoLibrary.self, from: data)
    }

    public static func save(_ library: TodoLibrary, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(library)
        try data.write(to: url, options: [.atomic])
    }
}
