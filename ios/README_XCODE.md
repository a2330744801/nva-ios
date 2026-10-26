# Xcode 工程搭建指南（ios/ 源码 → 可运行 App）

## 0. 硬前提（再说一遍）
- Apple Developer 账号（688 元/年）。免费账号装上 7 天掉签。
- Mac，或 Codemagic / GitHub Actions 云构建。
- iOS 15+ 设备。

## 1. 新建工程（Xcode）
1. File → New → Project → **iOS App**（SwiftUI，接口 Swift）
   - Product Name: `NvaRadar`，Bundle ID: `com.你的名字.nvaradar`
2. 再加一个 Target：File → New → Target → **Network Extension**：
   - Product Name: `NvaTunnel`
   - Type 选 **Packet Tunnel Provider**
   - "Include UI" 不要勾
3. 把 `Sources/` 下 4 个 swift 文件加进 **NvaRadar** target；
   把 `Extension/PacketTunnelProvider.swift` 加进 **NvaTunnel** target；
   `Extension/Info.plist` 替换 NvaTunnel target 的 Info.plist（或对照补 NSExtension 两项）。

## 2. 两个 Target 各自的签名与能力
- NvaRadar 和 NvaTunnel 都要：
  - Signing & Capabilities → Team 选你的付费账号
  - + Capability → **Network Extensions**，勾 **Packet Tunnel Provider**
  - Bundle ID 必须形如 `com.你的名字.nvaradar` 和 `com.你的名字.nvaradar.tunnel`（后者以
    前者为前缀），TunnelManager.swift 里的 `bundleID` 改成一致
- App Groups 可不加（本工程用 providerConfiguration 传配置，不走共享存储）

## 3. 引入 WireGuardKit
File → Add Package Dependencies →
```
https://github.com/WireGuard/wireguard-apple
```
- Dependency 规则：Up to Next Major
- Add to Target：只给 **NvaTunnel** 加 **WireGuardKit** product
  （如果主 App 引用报错，主 App 也加无妨）

## 4. 构建 & 安装
- 真机插上 → 选 NvaRadar scheme → Run
- 首次启动：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
- App 内填配置 → 连接隧道 → 系统弹"VPN 配置"允许

## 5. 没有 Mac？云构建
- 把工程推 GitHub → Codemagic（免费额度）或 GitHub Actions macOS runner
- 需要：导出你的 p12 签名证书 + provisioning profile 配成环境变量
- 产物 ipa 用 AltStore/Sideloadly 侧载（7 天），或有账号直接 TestFlight（90 天）

## 6. 服务器侧对应操作
见仓库根 README.md「快速开始」：
1. 装 WireGuard for Windows + Npcap
2. gen_keys.ps1 生成密钥 → 手机私钥填进 App，手机公钥填进 nva-server.conf [Peer]
3. wg_server_setup.ps1 一键注册服务/转发/NAT/防火墙
4. 运行 wg_relay.py → 打印房间号 → 浏览器开 /radar/?room=房间号

## 常见坑
| 现象 | 原因 |
|---|---|
| 连接隧道立刻断 | providerBundleIdentifier 与 Tunnel target Bundle ID 不一致 |
| "Missing entitlement" | Network Extensions capability 没加到两个 target |
| 隧道通了但上不了网 | 服务器 IP 转发/NAT 没配（wg_server_setup.ps1 [2][3] 步） |
| 有流量没实体 | wg_relay.py 没跑，或 iface 名不对 |
