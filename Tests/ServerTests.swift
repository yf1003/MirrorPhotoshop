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
        let server = MirrorServer()
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
