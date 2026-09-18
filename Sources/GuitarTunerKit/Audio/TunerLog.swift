import Foundation

/// Opt-in diagnostics for the audio stack.
///
/// `GUITAR_TUNER_TRACE=1` writes to stderr; `GUITAR_TUNER_TRACE=/tmp/tuner.log` also
/// appends to that file, which is the reliable way to capture what a GUI app does —
/// stdout of a bundled app is easy to lose and block-buffered.
///
/// The messages answer the two questions that matter when nothing happens: did the
/// engine start, and are buffers reaching the analysis loop?
enum TunerLog {
    private static let destination = ProcessInfo.processInfo.environment["GUITAR_TUNER_TRACE"]
    static let isEnabled = destination?.isEmpty == false

    static func trace(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "[tuner] \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))

        guard let destination, destination.hasPrefix("/") else { return }
        // Opened per message on purpose: tracing is a diagnostic path, and this keeps the
        // helper free of shared mutable state (which Swift 6 rejects, and which would
        // need locking because messages arrive from both the main actor and the analysis
        // queue).
        if let handle = FileHandle(forWritingAtPath: destination) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            FileManager.default.createFile(atPath: destination, contents: Data(line.utf8))
        }
    }
}
