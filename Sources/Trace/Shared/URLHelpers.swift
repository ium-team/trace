import Foundation

extension URL {
    func relativePath(from baseURL: URL) -> String {
        let base = baseURL.standardizedFileURL.path
        let path = standardizedFileURL.path
        guard path.hasPrefix(base) else { return path }
        var relative = String(path.dropFirst(base.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
}
