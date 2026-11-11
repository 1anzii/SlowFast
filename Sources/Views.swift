// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI

private enum Metal {
    static let ink = Color(white: 0.17)
    static let secondary = Color(white: 0.38)
    static let green = Color(red: 0.23, green: 0.48, blue: 0.35)
    static let amber = Color(red: 0.68, green: 0.34, blue: 0.12)
    static let face = LinearGradient(colors: [Color(white: 0.94), Color(white: 0.78), Color(white: 0.88)], startPoint: .top, endPoint: .bottom)
}

private struct BrushedCase: View {
    var body: some View { WornMetalCase() }
}

private typealias MetalButton = HardwareKeyStyle
private typealias Screw = HardwareScrew

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var viewportSize = NSSize(width: 400, height: 568)
    @State private var expandedPlayer: String?
    @State private var showOtherPlayers = false
    @State private var showConnections: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, viewportSize: NSSize = NSSize(width: 400, height: 568), connectionsOpen: Bool = false) {
        self.model = model; self.viewportSize = viewportSize
        _showConnections = State(initialValue: connectionsOpen)
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 10) {
                    if showConnections {
                        connectionBay
                    } else {
                        transport
                        shortcutStatus
                        connectionHatch
                    }
                }.padding(.horizontal, 22).padding(.bottom, 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: showConnections)
            }
            HStack {
                Screw(); Spacer()
                Text("SF–04  /  VARIABLE SPEED").font(.system(size: 6.5, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Metal.secondary)
                Spacer(); Screw()
            }.padding(.horizontal, 17).padding(.top, 4).padding(.bottom, 13)
        }.frame(width: viewportSize.width, height: viewportSize.height)
            .background(BrushedCase()).foregroundStyle(Metal.ink).tint(Metal.green).preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SLOWFAST").font(.custom("Michroma-Regular", size: 21)).tracking(0.5).shadow(color: .white.opacity(0.65), radius: 0, y: 1)
                Text("PORTABLE SPEED CONTROL").font(.system(size: 6.5, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Metal.secondary).padding(.top, 3)
            }
            Spacer()
            Button { model.showHistory = false; model.showAdvanced = true } label: { Image(systemName: "gearshape.fill").font(.system(size: 13, weight: .medium)) }
                .buttonStyle(MetalButton(compact: true)).accessibilityLabel("设置与操作记录")
        }
    }

    private var transport: some View {
        VStack(spacing: 6) {
            CassetteDeck(rate: model.rate, playing: model.playbackKnown && model.playbackPlaying)
            TapeDisplay(rate: model.rate, word: displayWord,
                        target: model.targetSupported ? model.targetName : "NO SOURCE",
                        status: displayStatus, playing: model.playbackKnown && model.playbackPlaying)
                .help(model.rate == nil ? idleHint : "实时读取播放器的倍速与播放状态")
            HStack(spacing: 4) {
                ForEach(SpeedScale.values, id: \.self) { rate in
                    Button { model.perform(.set, requested: rate) } label: {
                        VStack(spacing: 5) {
                            Rectangle().fill(model.rate == rate ? Metal.amber : Metal.secondary.opacity(0.4)).frame(width: model.rate == rate ? 3 : 1, height: 5)
                            Text(SpeedScale.label(rate)).font(.system(size: 10, weight: model.rate == rate ? .bold : .regular, design: .monospaced))
                        }.frame(maxWidth: .infinity).frame(height: 23).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!model.canControlFromWindow).accessibilityLabel("设置为 " + SpeedScale.label(rate))
                }
            }
            HStack(spacing: 5) {
                transportKey("SLOW", key: "Fn ,", symbol: "backward.fill", action: .slower)
                transportKey("RESET", key: "Fn ?", symbol: "arrow.counterclockwise", action: .reset)
                transportKey("FAST", key: "Fn .", symbol: "forward.fill", action: .faster)
            }.padding(5).padding(.bottom, 2).background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.45), lineWidth: 0.8).padding(-1))
        }
    }

    private var displayWord: String {
        if !model.enabled { return "OFF" }
        if !model.hotKeysReady || model.lastError || model.currentConnection?.needsSetup == true { return "CHECK" }
        return "READY"
    }

    private var displayStatus: String {
        if model.busy { return "SETTING" }
        if !model.enabled { return "FN OFF" }
        if !model.hotKeysReady { return "CHECK ACCESS" }
        if model.lastError { return "CHECK CONNECTION" }
        if model.extensionMode && model.targetIsChromium { return "EXTENSION" }
        if model.playbackKnown { return model.playbackPlaying ? "PLAY" : "PAUSE" }
        return model.rate != nil ? "LAST SPEED" : "STANDBY"
    }

    private var idleHint: String {
        if model.busy { return "正在确认视频的实际倍速" }
        if !model.enabled { return "打开下方开关，即可继续使用 Fn 快捷键" }
        if !model.targetSupported { return "切到浏览器或播放器，开始播放视频" }
        if model.lastError { return "打开下方「播放器连接」查看提示或修复" }
        if model.extensionMode && model.targetIsChromium { return "实际倍速显示在视频页面中" }
        if !model.hotKeysReady { return "点击下方「修复权限」完成设置" }
        if model.currentConnection?.needsSetup == true { return "打开下方「播放器连接」，点击播放器旁的「修复」" }
        return "打开视频后，这里会自动显示倍速；Fn + . 加速，Fn + , 减速"
    }

    private func transportKey(_ title: String, key: String, symbol: String, action: SpeedAction) -> some View {
        Button { model.perform(action) } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 23, weight: .bold)).frame(height: 25)
                Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4)
                Text(key).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Color(white: 0.36))
            }.shadow(color: .white.opacity(0.45), radius: 0, y: 0.5)
        }.buttonStyle(TransportKeyStyle()).disabled(!model.canControlFromWindow)
            .accessibilityLabel((action == .slower ? "减速 SLOW" : action == .faster ? "加速 FAST" : "恢复原速 RESET") + "，" + key)
    }

    private var shortcutStatus: some View {
        HStack(spacing: 9) {
            HardwareLED(on: model.enabled, warning: !model.hotKeysReady)
            VStack(alignment: .leading, spacing: 4) {
                Text("Fn 快捷键").font(.system(size: 11, weight: .bold))
                if !model.hotKeysReady {
                    Button("修复权限") { model.repairShortcutPermission() }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(Metal.amber)
                } else {
                    Text(model.enabled ? "已开启" : "已关闭").font(.system(size: 9)).foregroundStyle(Metal.secondary)
                }
            }
            Spacer()
            MechanicalPowerSwitch(isOn: $model.enabled)
        }.padding(.horizontal, 10).padding(.vertical, 2)
    }

    private var connectionSummary: String {
        let issues = model.installedPlayers.filter { model.connection($0.id).needsSetup }.count
        if issues > 0 { return "\(issues) 项待修复" }
        if model.lastError { return "查看连接提示" }
        let ready = model.installedPlayers.filter { model.connection($0.id).connected }.count
        return ready > 0 ? "\(ready) 台已连接" : "检查与修复"
    }

    private var connectionHatch: some View {
        Button { showConnections = true } label: {
            HStack(spacing: 10) {
                VentGrille()
                Text("播放器连接").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(connectionSummary).font(.system(size: 9)).foregroundStyle(model.lastError ? Metal.amber : Metal.secondary)
                Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
            }.padding(.horizontal, 13).frame(height: 36)
                .background(LinearGradient(colors: [.white.opacity(0.13), .black.opacity(0.07)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.32), lineWidth: 0.8))
                .shadow(color: .white.opacity(0.50), radius: 0, y: 1)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("打开播放器连接，" + connectionSummary)
    }

    private var connectionBay: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                VentGrille()
                VStack(alignment: .leading, spacing: 3) {
                    Text("播放器连接").font(.system(size: 16, weight: .bold))
                    Text("CONNECTION BAY").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1)
                }
                Spacer()
                Button { showConnections = false } label: {
                    Label("收起", systemImage: "chevron.down").font(.system(size: 10, weight: .semibold))
                }.buttonStyle(MetalButton(compact: true)).accessibilityLabel("收起播放器连接")
            }
            connections
            if model.lastError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Button("查看操作记录") { model.showHistory = true; model.showAdvanced = true }.font(.system(size: 10)).buttonStyle(.plain)
                }.foregroundStyle(Metal.amber)
            }
            if !model.connectionDetail.isEmpty {
                Text(model.connectionDetail).font(.system(size: 10)).foregroundStyle(Metal.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule().fill(.black.opacity(0.16)).frame(height: 1.5).shadow(color: .white.opacity(0.5), radius: 0, y: 0.7)
                }
            }.padding(.horizontal, 20).accessibilityHidden(true)
            HStack { Screw(); Spacer(); Text("CHECK · CONNECT · REPAIR").font(.system(size: 6.5, design: .monospaced)).tracking(1); Spacer(); Screw() }.foregroundStyle(Metal.secondary)
        }.padding(14).frame(minHeight: max(320, viewportSize.height - 132))
            .background(LinearGradient(colors: [Color(white: 0.66).opacity(0.65), Color(white: 0.83).opacity(0.75)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.45), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.5), lineWidth: 0.7).padding(2))
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本机播放器").font(.system(size: 10, weight: .semibold)); Spacer()
                Button(model.checkingAll ? "检查中…" : "全部检查") { model.checkAllConnections() }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).disabled(model.checkingAll || model.setupBrowserID != nil)
            }
            VStack(spacing: 0) {
                ForEach(Array(model.installedPlayers.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().padding(.horizontal, 12) }
                    connectionRow(player)
                }
            }.background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.black.opacity(0.13), lineWidth: 0.6))
            if !model.otherPlayers.isEmpty {
                Button { showOtherPlayers.toggle() } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: showOtherPlayers ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).padding(.top, 3)
                        Text("还支持 " + model.otherPlayers.map(\.name).joined(separator: " · ")).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    }.font(.system(size: 10)).foregroundStyle(Metal.secondary)
                }.buttonStyle(.plain)
                if showOtherPlayers {
                    ForEach(model.otherPlayers) { player in connectionRow(player) }
                    Text("IINA / mpv / VLC 可自动配置本地接口；不同版本仍需连接验证。").font(.system(size: 10)).foregroundStyle(Metal.secondary)
                }
            }
            if !model.selfCheckSummary.isEmpty { Text(model.selfCheckSummary).font(.system(size: 9)).foregroundStyle(Metal.secondary) }
        }
    }

    private func connectionRow(_ player: PlayerChoice) -> some View {
        let state = model.connection(player.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                HardwareLED(on: state.connected || state.needsSetup, warning: state.needsSetup)
                Button { expandedPlayer = expandedPlayer == player.id ? nil : player.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                            Text(player.name).font(.system(size: 11, weight: .semibold))
                        Text(model.setupBrowserID == player.id ? "正在自动连接…" : state.title).font(.system(size: 10)).foregroundStyle(Metal.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(player.name + "，" + state.title + "，查看连接说明")
                if state.needsSetup || state == .notRunning || state == .noPage {
                    Button { model.checkBrowser(player.id, force: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel("检查 " + player.name + " 连接").disabled(model.setupBrowserID != nil)
                }
                Button(state.actionTitle) { model.connectionAction(player) }.font(.system(size: 10, weight: .medium)).buttonStyle(MetalButton(compact: true))
                    .disabled(state == .checking || model.setupBrowserID != nil).accessibilityLabel(state.actionTitle + " " + player.name)
            }
            if expandedPlayer == player.id { Text(connectionHelp(player, state)).font(.system(size: 10)).foregroundStyle(Metal.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
        }.padding(.horizontal, 12).padding(.vertical, 7)
    }

    private func connectionHelp(_ player: PlayerChoice, _ state: BrowserConnection) -> String {
        if case .failed(let message) = state { return message + "。点击修复重新连接。" }
        if state == .notInstalled { return "此 Mac 尚未安装；点击官网可查看下载方式。" }
        if state == .automation { return "点击修复后，在 macOS 提示中允许 SlowFast 控制 " + player.name + "。" }
        if state == .javascript || state == .confirmation {
            return SupportedApp.safari.contains(player.id) ? "Safari 设置 → 高级 → 显示网页开发者功能 → 开发者 → 允许 Apple 事件中的 JavaScript。点击修复可自动定位，安全确认需本人完成。" : "显示（查看）→ 开发者 → 允许 Apple 事件中的 JavaScript。点击修复会自动定位并验证。"
        }
        if player.kind == .quickTime { return "打开视频并开始播放，再用 Fn 快捷键调速。暂停时不会自动播放。" }
        if player.kind == .iina || player.kind == .mpv { return "使用本机控制接口。点击修复可自动配置；只打开一个播放窗口。实际连接成功后才显示绿色。" }
        if player.kind == .vlc { return "仅连接 127.0.0.1；自动配置会备份设置并重启 VLC，密码会同时保存到 VLC 配置及 macOS 钥匙串。" }
        return "控制当前标签页的视频。点击检查验证连接；少数网页无法调速时，可在「设置 → 高级选项」安装兼容扩展。"
    }

}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    var viewportSize: NSSize
    @State private var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置与自检").font(.system(size: 18, weight: .bold))
                    Text("拖动顶部可移动窗口").font(.system(size: 10)).foregroundStyle(Metal.secondary)
                }.allowsHitTesting(false)
                Spacer()
                Button("完成") { model.showAdvanced = false }.buttonStyle(MetalButton(compact: true))
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 4)
                .background(WindowDragArea())
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Fn + , 减速   ·   Fn + . 加速\nFn + Shift + / 恢复 1×，Fn + / 也可以")
                    HStack { Text(model.hotKeysReady ? "快捷键监听正常" : "快捷键权限未就绪"); Spacer(); Button("修复权限") { model.repairShortcutPermission() } }
                    Button("重新运行自检") { model.checkAllConnections() }.disabled(model.checkingAll)
                    Text(model.selfCheckSummary).foregroundStyle(Metal.secondary)
                    Divider()
                    DisclosureGroup("高级选项", isExpanded: $advancedExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("正常调速时，无需设置这里。").foregroundStyle(Metal.secondary)
                            Toggle("用扩展兼容特殊网页", isOn: $model.extensionMode)
                            Text("仅用于 Chrome 等浏览器里少数无法调速的视频。先安装配套扩展，再开启；倍速看网页提示，磁带动画会停用。").font(.system(size: 11)).foregroundStyle(Metal.secondary)
                            Button("安装兼容扩展") { model.showExtension() }
                            DisclosureGroup("本地播放器手动设置") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("IINA socket 路径", text: $model.socketPath)
                            Button("复制 IINA 完整路径") { model.copySocketPath() }
                            HStack { Text("VLC 端口"); TextField("8080", text: $model.vlcPort) }
                            SecureField("VLC 本地接口密码", text: $model.vlcPassword)
                            Button("保存密码到钥匙串") { model.savePassword() }
                            Text(model.passwordStatus)
                            Button("查看完整配置说明") { model.showGuide() }
                        }.padding(.top, 8).textFieldStyle(.roundedBorder)
                            }
                        }.padding(.top, 10)
                    }
                    Divider()
                    DisclosureGroup("操作记录", isExpanded: $model.showHistory) {
                        VStack(alignment: .leading, spacing: 9) {
                            if model.lastError { Text(model.status) }
                            if model.recentResults.isEmpty { Text("调速后显示播放器返回的真实结果。") }
                            ForEach(Array(model.recentResults.enumerated()), id: \.offset) { _, line in Text(line).textSelection(.enabled); Divider() }
                        }.padding(.top, 8).font(.system(size: 10))
                    }
                    Text("SlowFast \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · 本机运行，无需账号\n已适配的播放器可连接；不保证所有 App、直播或 DRM 视频均能调速。").font(.system(size: 10)).foregroundStyle(Metal.secondary)
                    Button("使用与安装说明") { model.showGuide() }
                }.font(.system(size: 12)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }.frame(width: viewportSize.width, height: viewportSize.height)
            .background(BrushedCase()).foregroundStyle(Metal.ink).tint(Metal.green).preferredColorScheme(.light)
            .onAppear { advancedExpanded = model.extensionMode }
    }
}

struct HUDView: View {
    let title: String
    let subtitle: String
    let error: Bool
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: error ? 18 : 38, weight: .medium, design: .monospaced))
            Text(error ? "点菜单栏 SlowFast，检查并修复连接" : subtitle).font(.system(size: 11)).multilineTextAlignment(.center).foregroundStyle(Color(white: 0.7))
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(Color(white: 0.94))
            .background(Color(white: 0.14).opacity(0.97), in: RoundedRectangle(cornerRadius: 15)).padding(8)
    }
}
