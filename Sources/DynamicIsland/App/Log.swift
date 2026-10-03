import Foundation

enum Log {
    private static let path = "/tmp/dynamicisland.log"
    private static let queue = DispatchQueue(label: "island.log")
    static func write(_ message: String) {
        queue.async {
            let line = "\(Date()) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile(); fh.write(data); try? fh.close()
            } else { try? data.write(to: URL(fileURLWithPath: path)) }
        }
    }
}
