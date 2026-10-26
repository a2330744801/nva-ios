// PacketTunnelProvider.swift — 隧道扩展（WireGuardKit）
import NetworkExtension
import WireGuardKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var adapter: WireGuardAdapter?

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // App 端通过 providerConfiguration 传 wg-quick 配置
        guard let cfg = (protocolConfiguration as? NETunnelProviderProtocol)?
                .providerConfiguration?["wgQuick"] as? String,
              !cfg.isEmpty else {
            completionHandler(NSError(domain: "NVA", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "缺少 WireGuard 配置"]))
            return
        }
        do {
            let tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: cfg, called: "NVA")
            let a = WireGuardAdapter(with: self) { logType, message in
                NSLog("[wg][%@] %@", logType == .verbose ? "v" : String(describing: logType).prefix(1), message)
            }
            adapter = a
            a.start(tunnelConfiguration: tunnelConfig) { error in
                completionHandler(error)
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        adapter?.stop { _ in }
        adapter = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: @escaping (Data?) -> Void) {
        // 预留：主 App 可查询隧道状态
        completionHandler(nil)
    }
}
