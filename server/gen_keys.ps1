# -*- coding: utf-8 -*-
# gen_keys.ps1 —— 生成 WireGuard 密钥对（用 wg.exe，装 WireGuard 自带）
# 输出：服务端密钥对 + 一对手机密钥示例
$wg = "C:\Program Files\WireGuard\wg.exe"
if (-not (Test-Path $wg)) { $wg = "wg.exe" }

Write-Host "== 服务端密钥对（填进 nva-server.conf）==" -ForegroundColor Cyan
$priv = & $wg genkey
$pub  = $priv | & $wg pubkey
Write-Host ("PrivateKey(服务端私钥) = " + $priv.Trim())
Write-Host ("PublicKey (服务端公钥) = " + $pub.Trim())
Write-Host ""
Write-Host "== 手机密钥对 x2（私钥填进 iPhone App，公钥填进服务端 conf 的 [Peer]）==" -ForegroundColor Cyan
foreach ($n in 1..2) {
    $p = & $wg genkey
    $u = $p | & $wg pubkey
    Write-Host ("手机{0}: 私钥={1}  公钥={2}" -f $n, $p.Trim(), $u.Trim())
}
Write-Host ""
Read-Host "按回车关闭"
