import Foundation
import UIKit

@MainActor
final class MirrorClient: ObservableObject {
    @Published var status = "尚未连接"
    @Published var connected = false
    @Published var connecting = false
    @Published var frames: [MirrorFrame] = []
    @Published var selectedID: String?
    @Published var image: UIImage?
    @Published var displayedFrame: MirrorFrame?
    @Published var showViewer = false
    @Published var followActive = true
    private var baseURL: URL?
    private var code = ""
    private var candidateURLs: [URL] = []
    private var candidateIndex = 0
    private var task: Task<Void, Never>?
    private var loadedVersion: String?
    private var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func connect(_ pairing: MirrorPairing) {
        disconnect()
        code = pairing.code
        candidateURLs = pairing.baseURLs
        baseURL = candidateURLs.first
        followActive = true
        connecting = true
        status = "正在连接 Mac…"
        startPolling()
    }

    func disconnect() {
        task?.cancel(); task = nil
        connected = false; connecting = false; baseURL = nil
        code = ""; candidateURLs = []; candidateIndex = 0
        status = "尚未连接"
        frames = []; image = nil; displayedFrame = nil; selectedID = nil; loadedVersion = nil
    }

    func setActive(_ active: Bool) {
        if !active { task?.cancel(); task = nil }
        else if baseURL != nil && task == nil { startPolling() }
    }

    func choose(_ frame: MirrorFrame) {
        followActive = false; selectedID = frame.id; showViewer = true
    }

    private func startPolling() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
            }
        }
    }

    private func request(_ path: String) async throws -> Data {
        guard let baseURL else { throw URLError(.cancelled) }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue(code, forHTTPHeaderField: MirrorProtocol.keyHeader)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 401 { throw ClientError.pairing }
        guard response.statusCode == 200, data.count <= 40 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        return data
    }

    private func poll() async {
        do {
            let data = try await request("state")
            try Task.checkCancellation()
            let state = try JSONDecoder().decode(MirrorState.self, from: data)
            connected = true; connecting = false; frames = state.frames
            status = frames.isEmpty ? "已连接 \(state.name)，等待 PSD 画面" : "已连接 \(state.name)"
            if followActive, let id = state.activeID { selectedID = id }
            if !frames.contains(where: { $0.id == selectedID }) { selectedID = frames.first?.id }
            guard let frame = frames.first(where: { $0.id == selectedID }) else { return }
            let version = frame.id + ":" + frame.version
            if loadedVersion != version {
                let bytes = try await request("frame/" + frame.id)
                try Task.checkCancellation()
                guard let image = UIImage(data: bytes)?.preparingForDisplay() else { throw URLError(.cannotDecodeContentData) }
                self.image = image; displayedFrame = frame; loadedVersion = version
            }
        } catch is CancellationError { }
        catch ClientError.pairing {
            if Task.isCancelled { return }
            connected = false; connecting = false; status = "二维码已失效，请重新扫描 Mac 上的二维码。"
            task?.cancel(); task = nil
        } catch {
            if Task.isCancelled { return }
            connected = false; connecting = false
            if candidateURLs.count > 1 {
                candidateIndex = (candidateIndex + 1) % candidateURLs.count
                baseURL = candidateURLs[candidateIndex]
            }
            status = "暂时无法连接，正在重试。请保持 Mac 运行，并检查两端 Wi-Fi 和本地网络权限。"
        }
    }
    private enum ClientError: Error { case pairing }
}
