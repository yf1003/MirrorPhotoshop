import SwiftUI
import UniformTypeIdentifiers

@main
struct PSDMirrorMacApp: App {
    @StateObject private var server = MirrorServer()
    var body: some Scene {
        WindowGroup("PSD Mirror · Mac") {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 28)).foregroundStyle(.cyan)
                    Text("PSD Mirror").font(.system(size: 24, weight: .semibold))
                    Circle().fill(server.running ? .green : .orange).frame(width: 9, height: 9)
                    Spacer()
                    VStack(spacing: 6) {
                        if server.running, let pairing = MirrorPairing(hosts: Array(server.addresses.prefix(8)),
                                                                       port: Int(MirrorProtocol.port), code: server.pairingCode),
                           let image = PairingQRCode.image(pairing.qrString) {
                            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 96, height: 96).padding(4).background(.white, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("iPhone 连接二维码")
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "qrcode").font(.system(size: 30))
                                Text("等待网络").font(.caption2)
                            }.frame(width: 104, height: 104).foregroundStyle(.secondary)
                        }
                        Text("手机扫码连接").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("PSD 画面").font(.headline)
                    Spacer()
                    Button("添加 PSD…") { chooseFiles(folder: false) }
                    Button("添加文件夹…") { chooseFiles(folder: true) }
                }
                List(server.frames) { frame in
                    HStack {
                        Image(systemName: frame.source.contains("实时") ? "bolt.horizontal.circle" : "doc.richtext").foregroundStyle(.cyan)
                        VStack(alignment: .leading) {
                            Text(frame.previewTitle).lineLimit(1)
                            Text("\(frame.width) × \(frame.height) · \(frame.source)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("发送到手机") { server.select(frame.id) }
                    }.padding(.vertical, 4)
                }.overlay {
                    if server.frames.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "doc.badge.plus").font(.largeTitle)
                            Text("添加 PSD，保存后自动更新")
                            Text("也可加载配套 Photoshop 插件，实时发送未保存的修改。").font(.caption)
                        }.foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }.frame(minHeight: 180)
                Label(server.message, systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.secondary)
                Label(server.pluginStatus, systemImage: "puzzlepiece.extension")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(minWidth: 580, minHeight: 600).onAppear { server.start() }
        }.defaultSize(width: 640, height: 680)
    }
    private func chooseFiles(folder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = true
        if !folder { panel.allowedContentTypes = [UTType(filenameExtension: "psd")!] }
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/花园资源")
        panel.prompt = "添加"
        if panel.runModal() == .OK { server.add(urls: panel.urls) }
    }
}
