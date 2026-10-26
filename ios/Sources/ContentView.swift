// ContentView.swift — 主界面：填配置 → 开隧道 → 房间号/雷达链接
import SwiftUI

struct ContentView: View {
    @ObservedObject var tm = TunnelManager.shared
    @AppStorage("server")   var server   = "http://120.26.174.238"
    // WireGuard 配置（服务端 gen_keys.ps1 生成后抄进来）
    @AppStorage("wgPriv")   var wgPriv   = ""    // 本机私钥
    @AppStorage("wgIP")     var wgIP     = "10.66.0.2/32"
    @AppStorage("wgPub")    var wgPub    = ""    // 服务端公钥
    @AppStorage("wgEndpoint") var wgEndpoint = "120.26.174.238:51820"
    @AppStorage("allowedIPs") var allowedIPs = "0.0.0.0/0"

    @State var token = ""
    @State var room = ""
    @State var radarURL = ""
    @State var msg = ""

    var wgQuick: String {
        """
        [Interface]
        PrivateKey = \(wgPriv.trimmingCharacters(in: .whitespaces))
        Address = \(wgIP.trimmingCharacters(in: .whitespaces))
        DNS = 223.5.5.5

        [Peer]
        PublicKey = \(wgPub.trimmingCharacters(in: .whitespaces))
        Endpoint = \(wgEndpoint.trimmingCharacters(in: .whitespaces))
        AllowedIPs = \(allowedIPs)
        PersistentKeepalive = 25
        """
    }

    var body: some View {
        Form {
            Section("服务器") {
                TextField("http://服务器地址", text: $server)
                    .keyboardType(.URL). autocapitalization(.none).disableAutocorrection(true)
                Button("注册并生成房间") {
                    do {
                        let api = API(base: server)
                        token = try api.register()
                        (room, radarURL) = try api.createRoom(token: token)
                        msg = "房间已生成"
                    } catch { msg = "失败: \(error.localizedDescription)" }
                }
                if !room.isEmpty {
                    HStack { Text("房间号").foregroundColor(.gray); Spacer(); Text(room).bold().monospaced() }
                    Link("打开雷达页", destination: URL(string: radarURL)!)
                }
            }
            Section("WireGuard 配置（服务器 gen_keys.ps1 生成）") {
                TextField("本机私钥 PrivateKey", text: $wgPriv).autocapitalization(.none).disableAutocorrection(true)
                TextField("本机隧道 IP（如 10.66.0.2/32）", text: $wgIP).autocapitalization(.none).disableAutocorrection(true)
                TextField("服务端公钥 PublicKey", text: $wgPub).autocapitalization(.none).disableAutocorrection(true)
                TextField("服务端 Endpoint", text: $wgEndpoint).autocapitalization(.none).disableAutocorrection(true)
            }
            Section("隧道") {
                Button(tm.status == .connected ? "断开隧道" : "连接隧道") {
                    tm.observeStatus()
                    if tm.status == .connected { tm.stop() }
                    else {
                        tm.install(wgQuick: wgQuick) { err in
                            if let err = err { msg = err } else { tm.start() }
                        }
                    }
                }
                Text("状态: \(String(describing: tm.status))").foregroundColor(.gray)
            }
            if !msg.isEmpty {
                Section { Text(msg).foregroundColor(msg.contains("失败") ? .red : .green) }
            }
            Section {
                Text("用法：先连接隧道，再进游戏。服务器侧 wg_relay.py 自动抓包解析。\n房间号与雷达页在上方。").font(.footnote).foregroundColor(.gray)
            }
        }
        .navigationTitle("稳雷达 iOS")
    }
}
