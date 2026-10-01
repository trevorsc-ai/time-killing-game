import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.pgsave`: the exported progress file (declared in project.yml as an exported type).
    static let pgsave = UTType(exportedAs: "com.example.puzzlegetaway.save", conformingTo: .json)
}

/// Wraps the bytes produced by `SaveStore.exportData` for `fileExporter`.
struct SaveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pgsave, .json] }
    static var writableContentTypes: [UTType] { [.pgsave] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
