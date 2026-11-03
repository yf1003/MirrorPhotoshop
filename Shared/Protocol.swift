import Foundation

struct MirrorFrame: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var version: String
    var width: Int
    var height: Int
    var source: String
}

struct MirrorState: Codable {
    var name: String
    var frames: [MirrorFrame]
    var activeID: String?
}

struct PushFrame: Codable {
    var id: String
    var title: String
    var width: Int
    var height: Int
    var jpeg: String
}

struct PluginSession: Codable {
    let service: String
    let version: Int
    let key: String
}

enum MirrorProtocol {
    static let port: UInt16 = 48765
    static let service = "_psdmirror._tcp."
    static let keyHeader = "X-Mirror-Key"
    static let pluginPort: UInt16 = 48766
    static let pluginKeyHeader = "X-Mirror-Plugin-Key"
    static let pluginClientHeader = "X-Mirror-Plugin-Client"
    static let pluginClient = "psdmirror-uxp"
}
