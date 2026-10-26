// TunnelManager.swift — 管理 VPN 配置（NETunnelProviderManager）
import Foundation
import NetworkExtension

final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()
    static let bundleID = "（替换成你的）com.yourname.nvaradar.tunnel"

    @Published var status: NEVPNStatus = .invalid

    /// 创建/更新 VPN 配置并保存。wgQuick: 完整的 wg-quick 配置文本
    func install(wgQuick: String, completion: @escaping (String?) -> Void) {
        load { mgr in
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.bundleID
            proto.serverAddress = "NVA WireGuard"
            proto.providerConfiguration = ["wgQuick": wgQuick]
            proto.disconnectOnSleep = false
            mgr.protocolConfiguration = proto
            mgr.isEnabled = true
            mgr.saveToPreferences { err in
                if let err = err { completion("保存配置失败: \(err.localizedDescription)"); return }
                mgr.loadFromPreferences { _ in completion(nil) }
            }
        }
    }

    func start() {
        load { mgr in
            do { try mgr.connection.startVPNTunnel() }
            catch { print("start failed:", error) }
        }
    }

    func stop() {
        load { mgr in mgr.connection.stopVPNTunnel() }
    }

    func observeStatus() {
        load { mgr in
            NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange, object: mgr.connection, queue: .main
            ) { [weak self] _ in
                self?.status = mgr.connection.status
            }
            self.status = mgr.connection.status
        }
    }

    private func load(_ done: @escaping (NETunnelProviderManager) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let mgr = managers?.first ?? NETunnelProviderManager()
            DispatchQueue.main.async { done(mgr) }
        }
    }
}
