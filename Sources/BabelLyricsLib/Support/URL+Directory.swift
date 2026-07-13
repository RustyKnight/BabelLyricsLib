import Foundation

public extension URL {
    /// Indicates whether the URL points to a directory resource.
    var isDirectory: Bool {
        let resourceValues = try? resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true
    }
}
