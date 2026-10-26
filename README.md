# NVA iOS 版 — 总体方案

## 架构

        iPhone (游戏)                                你的 Windows 服务器
   ┌─────────────────────┐    WireGuard 隧道    ┌──────────────────────────┐
   │  NVA Radar App      │ ───────────────────► │ WireGuard 服务端 (51820)  │
   │  (WireGuardKit)     │   10.66.0.x 隧道网   │   + IP 转发 + NAT         │
   └─────────────────────┘                      │ wg_relay.py 抓包→NVJ1     │
                                                │   └► POST /journal        │
                                                │ nva server.py (解析+雷达)  │
                                                └──────────────────────────┘

为什么用 WireGuardKit：iPhone 没有像安卓 VpnService 那样方便的"抓包转发"权限，
自己写用户态 TCP/UDP 转发栈等于重写一个小火箭。WireGuard 是苹果官方生态支持的
VPN 协议（WireGuardKit 官方库），游戏流量经隧道到服务器，服务器端抓包解析，
后端解析链路（server.py / decoder / ErCore）一行都不用改。

## 组成

    server/                     ← 服务器侧（跑在你的 Windows 服务器上）
      wg_server_setup.ps1       一键：装好的 WireGuard 服务端注册 + IP转发 + NAT + 防火墙
      nva-server.conf.tpl       服务端 WireGuard 配置模板（生成密钥后填入）
      wg_relay.py               嗅探隧道流量 → NVJ1 打包 → 上报 /journal（常驻运行）

    ios/                        ← iPhone 侧（Xcode 工程源码）
      README_XCODE.md           一步步建工程、签名、云构建说明
      Sources/NvaRadarApp.swift SwiftUI 入口
      Sources/ContentView.swift UI：填配置 → 开隧道 → 显示房间号/雷达链接
      Sources/API.swift         register / room/create
      Sources/TunnelManager.swift NETunnelProviderManager 管理
      Extension/PacketTunnelProvider.swift  隧道扩展（WireGuardKit）
      Extension/Info.plist      扩展的 Info.plist 内容

## 手机流量路径说明（重要）

iPhone 开启 NVA 隧道后，**全部流量走服务器出去**（和连了一个 VPN 一样）。
游戏延迟 = 你到服务器的延迟 + 服务器到游戏服的延迟。国内同区域一般 +5~20ms，
可接受；如果想只让游戏走隧道，需在 iPhone 的 VPN 配置里加按需路由（后续优化）。

## 快速开始

### 第一步：服务器（10 分钟）
1. 服务器安装两个东西：
   - WireGuard for Windows（https://www.wireguard.com/install/）
   - Npcap（https://npcap.com/，装时勾选 "Support raw 802.11" 可不勾）
2. 管理员 PowerShell 运行 `server/gen_keys.ps1` 生成服务端密钥
3. 按 `server/nva-server.conf.tpl` 填好配置（每台 iPhone 一段 [Peer]）
4. 管理员运行 `server/wg_server_setup.ps1`（注册隧道服务、开转发、加 NAT、放防火墙）
5. 管理员运行：`runtime\python.exe server/wg_relay.py --iface "NVA WG"`（接口名见配置）
   → 它会打印房间号；雷达直接开 http://120.26.174.238/radar/?room=房间号

### 第二步：iPhone App（需要开发者账号）
1. Mac/云构建上按 `ios/README_XCODE.md` 建工程、引 WireGuardKit、签名
2. App 里填：服务器地址、WireGuard 配置（服务器公钥 / 你的私钥 / 分配的隧道 IP）
3. 开关一开，隧道即通；房间号在服务器侧由 wg_relay.py 给出

## 成本提醒（必须知道）
- Apple Developer 账号 688 元/年：没有它，App 装上 7 天就掉签
- 编译要 Mac，没有 Mac 用 Codemagic / GitHub Actions 的 macOS 云构建

## 打包 ipa（本仓库已配好全自动云构建）

不用买任何东西就能先拿到 **未签名 ipa**：

1. 把本目录整个推到 GitHub（公开仓库免费用 macOS runner）
2. 仓库页 → Actions → 选 **build-ipa** → Run workflow
3. 跑完在 Artifacts 下载 `NvaRadar-unsigned.ipa`

但注意苹果的硬门槛：
- **未签名 ipa 装不上手机**。要用 Sideloadly/AltStore 用你自己的 Apple ID 现场重签——
  而免费 Apple ID 的描述文件**不支持 VPN 类 App（Network Extension）**，重签会失败。
- 也就是说：**想真正装到 iPhone 上用，必须买 688 元/年的开发者账号**，没有绕开的办法。
- 买了账号后：Actions 里配好 P12/描述文件的 Secrets，`build-signed` job 自动出**正式签名 ipa**，
  TestFlight 分发最省心（上传一次，全员长期可用）。

git 推送注意：`.github/` 是隐藏目录，整个目录一起 `git add .` 即可。
