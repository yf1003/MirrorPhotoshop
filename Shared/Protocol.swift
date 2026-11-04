import Foundation

struct MirrorFrame: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var version: String
    var width: Int
    var height: Int
    var source: String
    var artboardName: String? = nil

    var previewTitle: String { artboardName.map { "\($0) · \(title)" } ?? title }
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

struct PushArtboard: Codable {
    var document: PushFrame
    var layerID: Int
    var name: String
}

struct PluginArtboards: Codable {
    var documentID: String
    var layerIDs: [Int]
    var activeLayerID: Int
}

struct PluginArtboardState: Codable {
    var missingLayerIDs: [Int]
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
