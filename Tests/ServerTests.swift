import Foundation
import ImageIO

@main
struct ServerTests {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixture = root.appendingPathComponent("build/QA/check.psd")
        try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makePSD(width: 80, height: 160, red: 70).write(to: fixture)
        let (png, width, height) = try MirrorServer.renderPSD(fixture)
        try check(width == 80 && height == 160, "PSD source dimensions")
        try check(png.starts(with: [0x89, 0x50, 0x4e, 0x47]), "PSD rendered to lossless PNG")
        if CommandLine.arguments.count > 1 {
            let actual = URL(fileURLWithPath: CommandLine.arguments[1])
            let (bytes, w, h) = try MirrorServer.renderPSD(actual)
            try bytes.write(to: root.appendingPathComponent("build/QA/actual-preview.png"))
            try check(w > 0 && h > 0 && !bytes.isEmpty, "Actual garden PSD renders: \(w) × \(h)")
        }
        let suite = "PSDMirror.ServerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = MirrorServer(defaults: defaults)
        server.start()
        server.add(urls: [fixture])
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let base = URL(string: "http://127.0.0.1:\(MirrorProtocol.port)")!
        func request(_ path: String, key: String? = nil, method: String = "GET", body: Data? = nil) async throws -> (Data, Int) {
            var req = URLRequest(url: base.appendingPathComponent(path))
            req.timeoutInterval = 5; req.httpMethod = method; req.httpBody = body
            req.setValue(key ?? server.pairingCode, forHTTPHeaderField: MirrorProtocol.keyHeader)
            let (data, response) = try await URLSession.shared.data(for: req)
            return (data, (response as! HTTPURLResponse).statusCode)
        }
        let (_, unauthorized) = try await request("state", key: "wrong")
        try check(unauthorized == 401, "Unauthenticated clients rejected")
        let (stateData, code) = try await request("state")
        let state = try JSONDecoder().decode(MirrorState.self, from: stateData)
        try check(code == 200 && state.frames.count == 1, "Authenticated PSD list")
        let first = state.frames[0]
        let (image, imageCode) = try await request("frame/" + first.id)
        try check(imageCode == 200 && image == png, "Frame transport preserves image bytes")
        let (_, missing) = try await request("frame/../../etc/passwd")
        try check(missing == 404, "No arbitrary filesystem access")
        let invalid = PushFrame(id: "invalid", title: "private.txt", width: 80, height: 160, jpeg: png.base64EncodedString())
        let (_, invalidCode) = try await request("push", method: "POST", body: JSONEncoder().encode(invalid))
        try check(invalidCode == 400, "Non-PSD uploads rejected")
        let live = PushFrame(id: "integration", title: "实时测试.psd", width: 80, height: 160, jpeg: png.base64EncodedString())
        let (_, pushCode) = try await request("push", method: "POST", body: JSONEncoder().encode(live))
        try check(pushCode == 200, "Live frame accepted")
        let (liveStateData, _) = try await request("state")
        let liveState = try JSONDecoder().decode(MirrorState.self, from: liveStateData)
        try check(liveState.activeID == "live-integration", "New live frame becomes active")

        func pluginRequest(_ path: String, marker: Bool = true, token: String? = nil, origin: String? = nil,
                           method: String = "GET", body: Data? = nil) async throws -> (Data, Int) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(MirrorProtocol.pluginPort)/\(path)")!)
            request.timeoutInterval = 5; request.httpMethod = method; request.httpBody = body
            if marker { request.setValue(MirrorProtocol.pluginClient, forHTTPHeaderField: MirrorProtocol.pluginClientHeader) }
            if let token { request.setValue(token, forHTTPHeaderField: MirrorProtocol.pluginKeyHeader) }
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            let (bytes, response) = try await URLSession.shared.data(for: request)
            return (bytes, (response as! HTTPURLResponse).statusCode)
        }
        let (_, noMarker) = try await pluginRequest("session", marker: false)
        try check(noMarker == 403, "Local plugin session requires client marker")
        let (_, browserOrigin) = try await pluginRequest("session", origin: "https://example.com")
        try check(browserOrigin == 403, "Browser origins cannot obtain local plugin session")
        let (sessionBytes, sessionCode) = try await pluginRequest("session")
        let pluginSession = try JSONDecoder().decode(PluginSession.self, from: sessionBytes)
        try check(sessionCode == 200 && pluginSession.service == "psdmirror-plugin" && pluginSession.version == 1 && pluginSession.key.count == 32,
                  "Automatic plugin handshake returns independent session token")
        let (_, noToken) = try await pluginRequest("push", method: "POST", body: JSONEncoder().encode(live))
        try check(noToken == 401, "Plugin uploads require local session token")
        let (_, pluginPush) = try await pluginRequest("push", token: pluginSession.key, method: "POST", body: JSONEncoder().encode(live))
        try check(pluginPush == 200, "Plugin image is transferred directly without filesystem bridge")
        let (_, isolatedRead) = try await pluginRequest("state", token: pluginSession.key)
        try check(isolatedRead == 404, "Plugin API does not expose phone preview endpoints")
        let (_, isolatedSession) = try await request("session")
        try check(isolatedSession == 404, "LAN phone API does not expose plugin handshake")

        func publishBoards(_ ids: [Int], active: Int) async throws -> PluginArtboardState {
            let update = PluginArtboards(documentID: "123", layerIDs: ids, activeLayerID: active)
            let (data, status) = try await pluginRequest("artboards", token: pluginSession.key, method: "POST", body: JSONEncoder().encode(update))
            try check(status == 200, "Artboard list and selection accepted")
            return try JSONDecoder().decode(PluginArtboardState.self, from: data)
        }
        let pending = try await publishBoards([11, 12], active: 11)
        try check(pending.missingLayerIDs == [11, 12], "Plugin can discover previews that need uploading")
        for (id, name) in [(11, "商店"), (12, "详情")] {
            let doc = PushFrame(id: "123", title: "示例.psd", width: 80, height: 160, jpeg: png.base64EncodedString())
            let push = PushArtboard(document: doc, layerID: id, name: name)
            let (_, status) = try await pluginRequest("artboard", token: pluginSession.key, method: "POST", body: JSONEncoder().encode(push))
            try check(status == 200, "Individual artboard uploaded")
        }
        let ready = try await publishBoards([11, 12], active: 11)
        try check(ready.missingLayerIDs.isEmpty, "Both artboard images are cached")
        let (boardsData, _) = try await request("state")
        let boards = try JSONDecoder().decode(MirrorState.self, from: boardsData)
        try check(boards.activeID == "artboard-123-11" && boards.frames.filter { $0.title == "示例.psd" }.map(\.artboardName) == ["商店", "详情"],
                  "Phone receives separate named entries from the same PSD")
        let (boardImage, boardStatus) = try await request("frame/artboard-123-12")
        try check(boardStatus == 200 && boardImage == png, "Artboard image fetched by its stable ID")
        _ = try await publishBoards([11, 12], active: 12)
        let (selectionData, _) = try await request("state")
        let selection = try JSONDecoder().decode(MirrorState.self, from: selectionData)
        try check(selection.activeID == "artboard-123-12" && selection.frames == boards.frames, "Photoshop selection changes without replacing any images")
        _ = try await publishBoards([12], active: 12)
        let (_, deleted) = try await request("frame/artboard-123-11")
        try check(deleted == 404, "Deleted artboard is removed from the cache")
        let ordinary = PushFrame(id: "123", title: "示例.psd", width: 80, height: 160, jpeg: png.base64EncodedString())
        let (_, ordinaryStatus) = try await pluginRequest("push", token: pluginSession.key, method: "POST", body: JSONEncoder().encode(ordinary))
        let (ordinaryData, _) = try await request("state")
        let ordinaryState = try JSONDecoder().decode(MirrorState.self, from: ordinaryData)
        try check(ordinaryStatus == 200 && ordinaryState.activeID == "live-123" && ordinaryState.frames.filter { $0.title == "示例.psd" }.map(\.id) == ["live-123"],
                  "Removing all artboards restores the ordinary PSD preview")
        try await Task.sleep(nanoseconds: 100_000_000)
        try makePSD(width: 80, height: 160, red: 190).write(to: fixture, options: .atomic)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let (updatedData, _) = try await request("state")
        let updated = try JSONDecoder().decode(MirrorState.self, from: updatedData)
        try check(updated.frames.first(where: { $0.id == first.id })?.version != first.version, "Saving a PSD changes the frame version")
        print("All PSD and HTTP integration checks passed.")
    }

    static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS \(name)")
    }
    static func makePSD(width: Int, height: Int, red: UInt8) -> Data {
        var result = Data("8BPS".utf8)
        func u16(_ value: UInt16) { var value = value.bigEndian; withUnsafeBytes(of: &value) { result.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.bigEndian; withUnsafeBytes(of: &value) { result.append(contentsOf: $0) } }
        u16(1); result.append(Data(repeating: 0, count: 6)); u16(3)
        u32(UInt32(height)); u32(UInt32(width)); u16(8); u16(3)
        u32(0); u32(0); u32(0); u16(0)
        result.append(Data(repeating: red, count: width * height))
        result.append(Data(repeating: 180, count: width * height))
        result.append(Data(repeating: 230, count: width * height))
        return result
    }
}
