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
    @Published var followActive = true {
        didSet { if followActive && !oldValue { selectMacFrameIfVisible() } }
    }
    @Published private var removedKeys: Set<String>
    private let defaults: UserDefaults
    private static let removedFramesKey = "mirror.removedPreviewKeys"
    private var macFrames: [MirrorFrame] = []
    private var lastMacActiveID: String?
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        removedKeys = Set(defaults.stringArray(forKey: Self.removedFramesKey) ?? [])
    }

    var hasRemovedFrames: Bool { !removedKeys.isEmpty }
    var allFramesRemoved: Bool { frames.isEmpty && !macFrames.isEmpty }

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
        macFrames = []
        frames = []; image = nil; displayedFrame = nil; selectedID = nil; loadedVersion = nil
        lastMacActiveID = nil; showViewer = false
    }

    func setActive(_ active: Bool) {
        if !active { task?.cancel(); task = nil }
        else if baseURL != nil && task == nil { startPolling() }
    }

    func choose(_ frame: MirrorFrame) {
        if frame.artboardName == nil { followActive = false }
        if displayedFrame?.id != frame.id { image = nil; displayedFrame = nil; loadedVersion = nil }
        selectedID = frame.id; showViewer = true
    }

    func removeFrames(_ ids: Set<String>) {
        removedKeys.formUnion(frames.filter { ids.contains($0.id) }.map(Self.removalKey))
        defaults.set(removedKeys.sorted(), forKey: Self.removedFramesKey)
        refreshVisibleFrames()
    }

    func restoreRemovedFrames() {
        removedKeys.removeAll()
        defaults.removeObject(forKey: Self.removedFramesKey)
        refreshVisibleFrames()
        if followActive { selectMacFrameIfVisible() }
    }

    private static func removalKey(_ frame: MirrorFrame) -> String {
        // File IDs derive from the path. Live IDs are scoped to a Photoshop
        // session; include the PSD name to avoid matching an unrelated reused ID.
        frame.id.hasPrefix("file-") ? frame.id : frame.id + ":" + frame.title
    }

    private func selectMacFrameIfVisible() {
        if let id = lastMacActiveID, frames.contains(where: { $0.id == id }) { selectedID = id }
    }

    private func refreshVisibleFrames() {
        let visible = macFrames.filter { !removedKeys.contains(Self.removalKey($0)) }
        if frames != visible { frames = visible }
        if !visible.contains(where: { $0.id == selectedID }) { selectedID = visible.first?.id }
        if let displayedFrame, !visible.contains(where: { $0.id == displayedFrame.id }) {
            image = nil; self.displayedFrame = nil; loadedVersion = nil
        }
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
        if response.statusCode == 404, path.hasPrefix("frame/") { throw ClientError.frameRemoved }
        guard response.statusCode == 200, data.count <= 40 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        return data
    }

    private func poll() async {
        do {
            let data = try await request("state")
            try Task.checkCancellation()
            let state = try JSONDecoder().decode(MirrorState.self, from: data)
            connected = true; connecting = false; macFrames = state.frames
            status = macFrames.isEmpty ? "已连接 \(state.name)，等待 PSD 画面" : "已连接 \(state.name)"
            let macSelectionChanged = state.activeID != lastMacActiveID
            lastMacActiveID = state.activeID
            refreshVisibleFrames()
            if followActive && macSelectionChanged { selectMacFrameIfVisible() }
            guard let frame = frames.first(where: { $0.id == selectedID }) else {
                image = nil; displayedFrame = nil; loadedVersion = nil
                return
            }
            let version = frame.id + ":" + frame.version
            if loadedVersion != version {
                let bytes = try await request("frame/" + frame.id)
                try Task.checkCancellation()
                guard selectedID == frame.id else { return }
                guard let image = UIImage(data: bytes)?.preparingForDisplay() else { throw URLError(.cannotDecodeContentData) }
                self.image = image; displayedFrame = frame; loadedVersion = version
            } else if displayedFrame != frame {
                displayedFrame = frame
            }
        } catch is CancellationError { }
        catch ClientError.frameRemoved { /* An artboard may be deleted between the list and image requests. */ }
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
    private enum ClientError: Error { case pairing, frameRemoved }
}
