# ============================================================
#  NVA WireGuard 服务端配置模板
#  复制为 nva-server.conf，填入 gen_keys.ps1 生成的密钥后启用
#  放到 C:\nva\wg\nva-server.conf
# ============================================================

[Interface]
# gen_keys.ps1 生成的【服务端私钥】
PrivateKey = <SERVER_PRIVATE_KEY>
# 手机连接的端口（防火墙已放行 UDP 51820）
ListenPort = 51820
# 隧道网段（服务器自己占 10.66.0.1）
Address = 10.66.0.1/24

# ---------- 以下每台 iPhone 一段，复制改 IP ----------

[Peer]
# 【手机A公钥】（手机 App 里生成后发给你）
PublicKey = <PHONE_A_PUBLIC_KEY>
# 分配给手机A的隧道 IP（不重复即可）
AllowedIPs = 10.66.0.2/32

[Peer]
PublicKey = <PHONE_B_PUBLIC_KEY>
AllowedIPs = 10.66.0.3/32
