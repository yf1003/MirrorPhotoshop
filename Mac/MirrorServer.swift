import Foundation
import Network
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import AppKit

final class MirrorServer: ObservableObject {
    @Published var running = false
    @Published var message = "正在启动…"
    @Published var frames: [MirrorFrame] = []
    @Published var addresses: [String] = []
    @Published var pluginStatus = "等待 Photoshop 插件"
    let pairingCode = String(format: "%08u", UInt32.random(in: 10_000_000...99_999_999))
    private let pluginKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let queue = DispatchQueue(label: "local.psdmirror.server")
    private var listener: NWListener?
    private var pluginListener: NWListener?
    private var timer: DispatchSourceTimer?
    private var watched: [URL] = []
    private var signatures: [URL: String] = [:]
    private var stored: [String: (MirrorFrame, Data)] = [:]
    private var order: [String] = []
    private var activeID: String?
    private var clients: [UUID: NWConnection] = [:]
    private var lastPluginActivity = Date.distantPast
    private var lastAddressRefresh = Date.distantPast
    private enum Channel { case phone, plugin }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: MirrorProtocol.port)!)
            self.listener = listener
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: MirrorProtocol.service)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.running = true; self?.message = "等待 iPhone 连接"
                    case .failed(let error): self?.running = false; self?.message = error.localizedDescription
                    case .cancelled: self?.running = false
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection, channel: .phone) }
            listener.start(queue: queue)
            startPluginListener()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.refreshFiles()
                if Date().timeIntervalSince(self.lastPluginActivity) > 10 && self.lastPluginActivity != .distantPast {
                    self.lastPluginActivity = .distantPast
                    DispatchQueue.main.async { self.pluginStatus = "等待 Photoshop 插件" }
                }
                if Date().timeIntervalSince(self.lastAddressRefresh) >= 5 {
                    self.lastAddressRefresh = Date()
                    let addresses = Self.localAddresses()
                    DispatchQueue.main.async { if self.addresses != addresses { self.addresses = addresses } }
                }
            }
            timer.resume()
            self.timer = timer
            addresses = Self.localAddresses()
            let remembered = UserDefaults.standard.stringArray(forKey: "mirror.psdPaths") ?? []
            if !remembered.isEmpty { add(urls: remembered.map { URL(fileURLWithPath: $0) }) }
        } catch { message = error.localizedDescription }
    }

    func add(urls: [URL]) {
        queue.async {
            var newFiles: [URL] = []
            for url in urls {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let file as URL in enumerator where file.pathExtension.lowercased() == "psd" {
                            newFiles.append(file)
                            if newFiles.count >= 100 { break }
                        }
                    }
                } else if url.pathExtension.lowercased() == "psd" { newFiles.append(url) }
            }
            for url in newFiles where !self.watched.contains(url) { self.watched.append(url) }
            UserDefaults.standard.set(self.watched.map(\.path), forKey: "mirror.psdPaths")
            self.refreshFiles()
        }
    }

    func select(_ id: String) { queue.async { self.activeID = id } }

    private func startPluginListener() {
        do {
            let port = NWEndpoint.Port(rawValue: MirrorProtocol.pluginPort)!
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            let listener = try NWListener(using: params)
            pluginListener = listener
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    DispatchQueue.main.async { self?.pluginStatus = "插件连接失败：\(error.localizedDescription)" }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection, channel: .plugin) }
            listener.start(queue: queue)
        } catch { pluginStatus = "插件连接失败：\(error.localizedDescription)" }
    }

    private func refreshFiles() {
        for url in watched {
            // URL.resourceValues caches values on the URL instance; stat afresh for live file watching.
            guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let date = values[.modificationDate] as? Date else { continue }
            let signature = "\(date.timeIntervalSince1970)-\(values[.size] as? Int ?? 0)"
            guard signatures[url] != signature else { continue }
            do {
                let (data, width, height) = try Self.renderPSD(url)
                let id = "file-" + SHA256.hash(data: Data(url.path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
                let version = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
                put(MirrorFrame(id: id, title: url.lastPathComponent, version: version, width: width, height: height, source: "已保存 PSD"), data: data)
                signatures[url] = signature
            } catch {
                DispatchQueue.main.async { self.message = "\(url.lastPathComponent)：\(error.localizedDescription)" }
            }
        }
    }

    static func renderPSD(_ url: URL) throws -> (Data, Int, Int) {
        guard url.pathExtension.lowercased() == "psd",
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw NSError(domain: "PSDMirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取 PSD"])
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 8192,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw NSError(domain: "PSDMirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "PSD 没有可用的合成预览；请在 Photoshop 开启最大兼容性后重新保存"])
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "PSDMirror", code: 3)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "PSDMirror", code: 4) }
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? image.width
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? image.height
        return (output as Data, width, height)
    }

    private func put(_ frame: MirrorFrame, data: Data) {
        // Bound retained previews so a long Photoshop session cannot grow without limit.
        if stored[frame.id] == nil { order.append(frame.id) }
        stored[frame.id] = (frame, data)
        while order.count > 1 && (order.count > 32 || stored.values.reduce(0, { $0 + $1.1.count }) > 256 * 1024 * 1024) {
            let old = order.removeFirst()
            stored.removeValue(forKey: old)
        }
        activeID = frame.id
        let snapshot = order.compactMap { stored[$0]?.0 }
        DispatchQueue.main.async { self.frames = snapshot; self.message = "已更新：\(frame.title)" }
    }

    private static func decodePush(_ body: Data) -> (MirrorFrame, Data)? {
        guard let push = try? JSONDecoder().decode(PushFrame.self, from: body),
              push.title.lowercased().hasSuffix(".psd"), !push.id.isEmpty, push.id.utf8.count <= 256,
              push.width > 0, push.height > 0, push.width <= 300000, push.height <= 300000,
              let data = Data(base64Encoded: push.jpeg), data.count <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let version = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
        return (MirrorFrame(id: "live-" + push.id, title: push.title, version: version, width: push.width, height: push.height, source: "Photoshop 实时"), data)
    }

    private func accept(_ connection: NWConnection, channel: Channel) {
        guard clients.count < 24 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 20) { [weak self, weak connection] in
            connection?.cancel(); self?.clients.removeValue(forKey: id)
        }
        receive(connection, id: id, channel: channel, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, channel: Channel, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 48 * 1024 * 1024 else { self.reply(connection, id: id, status: 413); return }
            if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard boundary.lowerBound < 16384,
                      let head = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else {
                    self.reply(connection, id: id, status: 400); return
                }
                let lines = head.components(separatedBy: "\r\n")
                let parts = (lines.first ?? "").split(separator: " ")
                guard parts.count == 3 else { self.reply(connection, id: id, status: 400); return }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                if channel == .phone {
                    guard headers[MirrorProtocol.keyHeader.lowercased()] == self.pairingCode else {
                        self.reply(connection, id: id, status: 401); return
                    }
                } else {
                    // No browser CORS permission is granted; the marker also prevents
                    // simple cross-origin form requests from accessing this local API.
                    let origin = headers["origin"]
                    guard headers[MirrorProtocol.pluginClientHeader.lowercased()] == MirrorProtocol.pluginClient,
                          origin == nil || origin!.hasPrefix("uxp://") else {
                        self.reply(connection, id: id, status: 403); return
                    }
                    if !(parts[0] == "GET" && parts[1] == "/session") {
                        guard headers[MirrorProtocol.pluginKeyHeader.lowercased()] == self.pluginKey else {
                            self.reply(connection, id: id, status: 401); return
                        }
                    }
                }
                let rawLength = headers["content-length"] ?? "0"
                guard let length = Int(rawLength), length >= 0, length <= 48 * 1024 * 1024,
                      headers["transfer-encoding"] == nil else { self.reply(connection, id: id, status: 400); return }
                if buffer.count >= boundary.upperBound + length {
                    let body = Data(buffer[boundary.upperBound..<(boundary.upperBound + length)])
                    if channel == .plugin {
                        self.routePlugin(connection, id: id, method: String(parts[0]), target: String(parts[1]), body: body)
                    } else {
                        self.route(connection, id: id, method: String(parts[0]), target: String(parts[1]), body: body)
                    }
                    return
                }
            } else if buffer.count > 16384 { self.reply(connection, id: id, status: 400); return }
            if complete || error != nil { connection.cancel(); self.clients.removeValue(forKey: id) }
            else { self.receive(connection, id: id, channel: channel, buffer: buffer) }
        }
    }

    private func routePlugin(_ connection: NWConnection, id: UUID, method: String, target: String, body: Data) {
        if method == "GET", target == "/session" {
            let session = PluginSession(service: "psdmirror-plugin", version: 1, key: pluginKey)
            lastPluginActivity = Date()
            DispatchQueue.main.async { self.pluginStatus = "Photoshop 已连接" }
            reply(connection, id: id, status: 200, type: "application/json", data: (try? JSONEncoder().encode(session)) ?? Data())
        } else if method == "POST", target == "/push" {
            guard let (frame, image) = Self.decodePush(body) else { reply(connection, id: id, status: 400); return }
            lastPluginActivity = Date()
            DispatchQueue.main.async { self.pluginStatus = "Photoshop 已连接" }
            put(frame, data: image)
            reply(connection, id: id, status: 200, type: "application/json", data: Data("{\"ok\":true}".utf8))
        } else { reply(connection, id: id, status: 404) }
    }

    private func route(_ connection: NWConnection, id: UUID, method: String, target: String, body: Data) {
        let path = String(target.split(separator: "?", maxSplits: 1).first ?? "")
        if method == "GET", path == "/state" {
            let state = MirrorState(name: Host.current().localizedName ?? "Mac", frames: order.compactMap { stored[$0]?.0 }, activeID: activeID)
            reply(connection, id: id, status: 200, type: "application/json", data: (try? JSONEncoder().encode(state)) ?? Data())
        } else if method == "GET", path.hasPrefix("/frame/"), let frame = stored[String(path.dropFirst(7))] {
            let isPNG = frame.1.starts(with: [0x89, 0x50, 0x4e, 0x47])
            reply(connection, id: id, status: 200, type: isPNG ? "image/png" : "image/jpeg", data: frame.1)
        } else if method == "POST", path == "/push" {
            guard let (frame, data) = Self.decodePush(body) else {
                reply(connection, id: id, status: 400); return
            }
            put(frame, data: data)
            reply(connection, id: id, status: 200, type: "application/json", data: Data("{\"ok\":true}".utf8))
        } else { reply(connection, id: id, status: 404) }
    }

    private func reply(_ connection: NWConnection, id: UUID, status: Int, type: String = "text/plain", data: Data = Data()) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large"][status] ?? "Error"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            connection.cancel(); self?.clients.removeValue(forKey: id)
        })
    }

    private static func localAddresses() -> [String] {
        var result: [(String, Int)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let value = item.pointee
            guard let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (value.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  (value.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let host = String(cString: host)
                guard MirrorPairing.validHost(host) else { continue }
                let interface = String(cString: value.ifa_name)
                let rank = (host.hasPrefix("169.254.") ? 100 : 0) + (interface == "en0" ? 0 : (interface.hasPrefix("en") ? 1 : 2))
                result.append((host, rank))
            }
        }
        var seen = Set<String>()
        return result.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map(\.0).filter { seen.insert($0).inserted }
    }
}
