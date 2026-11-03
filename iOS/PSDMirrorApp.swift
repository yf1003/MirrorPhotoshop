import SwiftUI

@main
struct PSDMirrorApp: App {
    var body: some Scene { WindowGroup { ConnectionView(client: MirrorClient()).preferredColorScheme(.dark) } }
}

struct ConnectionView: View {
    @StateObject private var client: MirrorClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLibrary = false
    @State private var showScanner = false
    @State private var pendingPairing: MirrorPairing?

    init(client: MirrorClient) { _client = StateObject(wrappedValue: client) }

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.055).ignoresSafeArea()
            if client.connected || !client.frames.isEmpty {
                catalog
            } else {
                welcome
            }
        }
        .onChange(of: scenePhase) { _, value in client.setActive(value == .active) }
        .sheet(isPresented: $showScanner, onDismiss: {
            if let pairing = pendingPairing {
                pendingPairing = nil
                client.connect(pairing)
            }
        }) {
            QRScannerSheet { pairing in
                pendingPairing = pairing
                showScanner = false
            }
        }
        .fullScreenCover(isPresented: $client.showViewer) {
            FullscreenPreview(image: client.image, frame: client.displayedFrame, status: client.status,
                              onClose: { client.showViewer = false },
                              onLibrary: { showLibrary = true })
                .ignoresSafeArea().statusBarHidden()
                .sheet(isPresented: $showLibrary) { library }
        }
    }

    private var welcome: some View {
        ZStack(alignment: .top) {
            Text("PSD Mirror")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.top, 28)
            VStack(spacing: 18) {
                Button(action: scan) {
                    Label("扫码连接", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 28).padding(.vertical, 18)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
                }.buttonStyle(.plain)
                if client.connecting {
                    ProgressView("正在连接…").font(.caption).tint(.gray)
                } else if client.status != "尚未连接" {
                    Text(client.status).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 280)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var catalog: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("PSD Mirror").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    connectionMenu
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("PSD 画面").font(.system(size: 30, weight: .semibold))
                        Text(String(client.frames.count)).font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 7) {
                        Circle().fill(client.connected ? Color.green.opacity(0.85) : Color.orange)
                            .frame(width: 5, height: 5)
                        Text(client.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 8)
                        if client.followActive {
                            Label("跟随 Mac", systemImage: "link")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            framesList
        }
    }

    private var connectionMenu: some View {
        Menu {
            Toggle("跟随 Mac 当前画面", isOn: $client.followActive)
            Divider()
            Button("重新扫码", systemImage: "qrcode.viewfinder", action: scan)
            Button("断开连接", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                client.disconnect()
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel("连接与同步选项")
    }

    private var framesList: some View {
        Group {
            if client.frames.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.richtext").font(.system(size: 32, weight: .light)).padding(.bottom, 4)
                    Text("还没有 PSD 画面").font(.subheadline.weight(.medium))
                    Text("在 Mac 添加 PSD，或开启 Photoshop 实时同步。")
                        .font(.caption).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary).padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(client.frames) { frame in
                            Button {
                                client.choose(frame)
                                showLibrary = false
                            } label: {
                                PSDFileRow(frame: frame, selected: client.selectedID == frame.id)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 24)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private var library: some View {
        NavigationStack {
            framesList
                .background(Color(red: 0.035, green: 0.045, blue: 0.055))
                .navigationTitle("PSD 画面").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Toggle("跟随 Mac 当前画面", isOn: $client.followActive)
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("同步选项")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { showLibrary = false } }
                }
        }.preferredColorScheme(.dark)
    }

    private func scan() {
        client.disconnect()
        showScanner = true
    }
}

private struct PSDFileRow: View {
    let frame: MirrorFrame
    let selected: Bool
    private var live: Bool { frame.source.contains("实时") }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, height: 52)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 8) {
                Text(frame.title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text("\(String(frame.width)) × \(String(frame.height))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    if live {
                        HStack(spacing: 4) {
                            Circle().fill(.cyan.opacity(0.7)).frame(width: 4, height: 4)
                            Text("实时").font(.system(size: 10, weight: .medium))
                        }.foregroundStyle(.cyan.opacity(0.8))
                    } else {
                        Text("已保存").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: selected ? 16 : 11, weight: .medium))
                .foregroundStyle(selected ? Color.cyan.opacity(0.8) : Color.white.opacity(0.2))
        }.padding(16)
            .background(.white.opacity(selected ? 0.06 : 0.035), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(selected ? 0.1 : 0.035)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
