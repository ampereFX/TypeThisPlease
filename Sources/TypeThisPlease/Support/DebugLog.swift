import Foundation

enum DebugLog {
    static func log(
        _ message: @autoclosure () -> String,
        category: String,
        function: StaticString = #function,
        file: StaticString = #fileID,
        line: Int = #line
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let thread = Thread.isMainThread ? "main" : "bg"
        let output = "[TypeThisPlease][\(timestamp)][\(thread)][\(category)][\(file):\(line)] \(function) - \(message())\n"
        fputs(output, stderr)
        fflush(stderr)
    }
}
