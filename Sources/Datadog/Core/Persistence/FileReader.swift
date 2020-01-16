import Foundation

internal struct Batch {
    /// Data read from file, prefixed with `[` and suffixed with `]`.
    let data: Data
    /// File from which `data` was read.
    fileprivate let file: ReadableFile
}

internal final class FileReader {
    /// Opening bracked used to prefix data in `Batch`.
    private let openingBracketData: Data = "[".data(using: .utf8)! // swiftlint:disable:this force_unwrapping
    /// Opening bracked used to suffix data in `Batch`.
    private let closingBracketData: Data = "]".data(using: .utf8)! // swiftlint:disable:this force_unwrapping
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestrator
    /// Queue used to synchronize files access (read / write).
    private let queue: DispatchQueue

    /// Files marked as read.
    private var filesRead: [ReadableFile] = []

    init(orchestrator: FilesOrchestrator, queue: DispatchQueue) {
        self.orchestrator = orchestrator
        self.queue = queue
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        queue.sync {
            synchronizedReadNextBatch()
        }
    }

    private func synchronizedReadNextBatch() -> Batch? {
        if let file = orchestrator.getReadableFile(excludingFilesNamed: Set(filesRead.map { $0.fileURL.lastPathComponent })) {
            do {
                let fileData = try file.read()
                let batchData = openingBracketData + fileData + closingBracketData
                return Batch(data: batchData, file: file)
            } catch {
                developerLogger?.error("🔥 Failed to read file: \(error)")
                return nil
            }
        }

        return nil
    }

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch) {
        queue.sync { [weak self] in
            self?.synchronizedMarkBatchAsRead(batch)
        }
    }

    private func synchronizedMarkBatchAsRead(_ batch: Batch) {
        orchestrator.delete(readableFile: batch.file)
        filesRead.append(batch.file)
    }
}
