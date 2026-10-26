# ============================================================
#  【一次性】在服务器上装 NVA 管理代理（端口 8888，带令牌）
#  装好后我就能直接远程操作这台服务器，不用你再动手
#
#  用法：远程桌面进服务器 → 管理员 PowerShell → 整段粘贴执行
#        （不用单独保存成文件，直接粘进去回车即可）
#
#  安全组里 8888 必须放行（你这个已经放行了）
# ============================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$dir = 'C:\nva\agent'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$agent = @'
# -*- coding: utf-8 -*-
import json, os, subprocess, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "nva8848a7"
PORT = 8888


def run_ps(cmd, timeout=180):
    try:
        p = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", cmd],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        return p.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return "ERR %r" % (e,)


class H(BaseHTTPRequestHandler):

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if q.get("t", [""])[0] != TOKEN:
            return self._send(403, "denied")
        if u.path == "/ping":
            return self._send(200, "nva-agent ok|" + os.environ.get("COMPUTERNAME", "?") + "|" + os.getcwd())
        if u.path == "/exec":
            return self._send(200, run_ps(q.get("cmd", [""])[0], int(q.get("to", ["180"])[0])))
        if u.path == "/get":
            p = q.get("p", [""])[0]
            try:
                with open(p, "rb") as f:
                    raw = f.read()
                return self._send(200, raw, "application/octet-stream")
            except Exception as e:
                return self._send(404, "ERR %r" % (e,))
        if u.path == "/ls":
            p = q.get("p", ["."])[0]
            try:
                items = []
                for n in os.listdir(p):
                    fp = os.path.join(p, n)
                    items.append({"n": n, "d": os.path.isdir(fp),
                                  "s": (os.path.getsize(fp) if os.path.isfile(fp) else 0)})
                return self._send(200, json.dumps(items, ensure_ascii=False), "application/json")
            except Exception as e:
                return self._send(500, "ERR %r" % (e,))
        self._send(404, "no route")

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if q.get("t", [""])[0] != TOKEN:
            return self._send(403, "denied")
        n = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(n)
        p = q.get("p", [""])[0]
        if not p:
            return self._send(400, "need p")
        try:
            d = os.path.dirname(p)
            if d:
                os.makedirs(d, exist_ok=True)
            with open(p, "wb") as f:
                f.write(data)
            return self._send(200, "written %d" % os.path.getsize(p))
        except Exception as e:
            return self._send(500, "ERR %r" % (e,))

    def log_message(self, fmt, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), H).serve_forever()
'@

Set-Content -Path "$dir\nva_agent.py" -Value $agent -Encoding UTF8

# 找可用的 python（优先用后端自带的便携运行时，服务器上不装 Python 也能跑）
$py = 'C:\nva\nva_backend\runtime\python.exe'
if (-not (Test-Path $py)) {
    $found = (Get-Command python -ErrorAction SilentlyContinue).Source
    if ($found) { $py = $found } else { $py = 'python' }
}
Write-Host "使用解释器: $py" -ForegroundColor Cyan

$bat = "@echo off`r`n:loop`r`n`"$py`" `"$dir\nva_agent.py`" >> `"$dir\agent.log`" 2>&1`r`ntimeout /t 3 /nobreak >nul`r`ngoto loop"
Set-Content -Path "$dir\run_agent.bat" -Value $bat -Encoding ASCII

# 防火墙放行 8888
netsh advfirewall firewall delete rule name="NVA-Agent-8888" | Out-Null
netsh advfirewall firewall add rule name="NVA-Agent-8888" dir=in action=allow protocol=TCP localport=8888 | Out-Null
Remove-NetFirewallRule -DisplayName "NVA-Agent-8888" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "NVA-Agent-8888" -DisplayName "NVA-Agent-8888" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 8888 -ErrorAction SilentlyContinue | Out-Null
Write-Host "[OK] 防火墙已放行 TCP 8888" -ForegroundColor Green

# 注册开机自启（SYSTEM 权限）+ 立即启动
schtasks /delete /tn "NVA-Agent" /f 2>$null | Out-Null
schtasks /create /tn "NVA-Agent" /tr "`"$dir\run_agent.bat`"" /sc onstart /delay 0000:10 /ru SYSTEM /rl HIGHEST /f | Out-Null
schtasks /run /tn "NVA-Agent" | Out-String
Write-Host "[OK] 计划任务 NVA-Agent 已注册并启动" -ForegroundColor Green

Start-Sleep -Seconds 6
try {
    $r = Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:8888/ping?t=nva8848a7" -TimeoutSec 10
    Write-Host ("[本地自检] " + $r.Content) -ForegroundColor Green
} catch {
    Write-Host ("[本地自检失败] " + $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "装好了。把下面这个结果发我，我就能接管：" -ForegroundColor Cyan
try {
    Invoke-WebRequest -UseBasicParsing "http://120.26.174.238:8888/ping?t=nva8848a7" -TimeoutSec 10 | Select-Object -ExpandProperty Content
} catch { "外网自检失败: " + $_.Exception.Message }
