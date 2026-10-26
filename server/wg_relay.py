#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""wg_relay.py —— WireGuard 隧道抓包 → NVJ1 → 上报 nva 服务器（iOS 版数据源）

管理员运行：
    runtime\\python.exe wg_relay.py --iface "nva-server"

流程：register → room/create → sniff 隧道 UDP → 按四元组 pair_id 打包 →
每 ~2s / 96KB flush 一次 gzip NVJ1 → POST /api/room/{room}/journal
"""
import argparse
import gzip
import json
import struct
import sys
import threading
import time
import urllib.request
import zlib

try:
    from scapy.all import sniff, IP, UDP
except ImportError:
    print("缺 scapy：runtime\\Scripts\\pip install scapy")
    sys.exit(1)

ap = argparse.ArgumentParser()
ap.add_argument("--server", default="http://127.0.0.1")
ap.add_argument("--iface", required=True, help="WireGuard 隧道接口名（wg_server_setup.ps1 会打印）")
ap.add_argument("--wg-net", default="10.66.0.", help="隧道网段前缀（判定方向用）")
ap.add_argument("--flush-ms", type=int, default=2000)
ap.add_argument("--flush-bytes", type=int, default=96 * 1024)
a = ap.parse_args()

state = {"token": None, "room": None, "seq": 0, "sent": 0, "pkts": 0}
lock = threading.Lock()
buf = {}            # pair_id -> {"quad": quad, "recs": [(rtype, ts_ms, payload), ...]}
buf_bytes = 0


def http(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def register():
    reg = http(a.server + "/api/device/register",
               json.dumps({"device_uid": "wg-relay", "platform": "windows",
                           "device_name": "wg-relay", "app_version": "1.0",
                           "os_version": "Windows"}).encode(),
               {"Content-Type": "application/json"})
    state["token"] = reg["token"]
    room = http(a.server + "/api/room/create", b'{"name":"wg-ios"}',
                {"Content-Type": "application/json",
                 "Authorization": "Bearer " + state["token"]})
    state["room"] = room["code"]
    print("房间号: %s   雷达: %s/radar/?room=%s   (解析页: %s/parser/%s/)" % (
        room["code"], a.server, room["code"], a.server, room["code"]), flush=True)


def ip_to_u32(s):
    x, y, z, w = (int(v) for v in s.split("."))
    return x | (y << 8) | (z << 16) | (w << 24)


def pair_crc(q):
    # 与手机端/服务器 decoder 一致：crc32-le of struct.pack("<IHIH", quad)
    return zlib.crc32(struct.pack("<IHIH", *q)) & 0xFFFFFFFF


def on_pkt(pkt):
    if IP not in pkt or UDP not in pkt:
        return
    ip, u = pkt[IP], pkt[UDP]
    src, dst = ip.src, ip.dst
    is_up = src.startswith(a.wg_net)          # 手机 → 游戏服 = 上行
    ts_ms = int(time.time() * 1000)
    if is_up:
        quad = (ip_to_u32(src), int(u.sport), ip_to_u32(dst), int(u.dport))
        rtype = 1
    else:
        quad = (ip_to_u32(dst), int(u.dport), ip_to_u32(src), int(u.sport))
        rtype = 2
    pid = pair_crc(quad)
    payload = bytes(u.payload)
    if not payload:
        return
    global buf_bytes
    with lock:
        e = buf.get(pid)
        if e is None:
            e = {"quad": quad, "recs": []}
            buf[pid] = e
        e["recs"].append((rtype, ts_ms, payload))
        buf_bytes += len(payload) + 22
        state["pkts"] += 1


def build_and_flush():
    global buf_bytes
    with lock:
        if not buf:
            return
        items = list(buf.items())
        buf.clear()
        buf_bytes = 0
    quads, recs, seen = [], [], set()
    for pid, e in items:
        if pid not in seen:
            seen.add(pid)
            quads.append(e["quad"])
        for (t, ts, p) in e["recs"]:
            recs.append((t, pid, ts, p))
    out = bytearray(b"NVJ1")
    out.append(len(quads))
    for q in quads:
        out += struct.pack("<IHIH", *q)
    for (t, pid, ts, p) in recs:
        out += struct.pack(">BB", t, t) + struct.pack(">IQH", pid, ts, len(p)) + p
    body = gzip.compress(bytes(out))
    state["seq"] += 1
    h = {"Content-Type": "application/octet-stream",
         "Authorization": "Bearer " + (state["token"] or ""),
         "X-Nva-Batch": str(state["seq"])}
    try:
        r = http("%s/api/room/%s/journal" % (a.server, state["room"]), body, h)
        state["sent"] += 1
        if state["sent"] % 10 == 0:
            print("已上报 %d 批 / %d 包 (entities=%s)" % (
                state["sent"], state["pkts"], r.get("entities")), flush=True)
    except Exception as e:
        print("上报失败:", e, flush=True)


def flusher():
    while True:
        time.sleep(a.flush_ms / 1000.0)
        with lock:
            n = buf_bytes
        if n:
            build_and_flush()


def main():
    register()
    threading.Thread(target=flusher, daemon=True).start()
    bpf = "udp and (net %s0.0/24)" % a.wg_net
    print("嗅探接口 %s, 过滤 %s  (Ctrl+C 退出)" % (a.iface, bpf), flush=True)
    try:
        sniff(iface=a.iface, filter=bpf, prn=on_pkt, store=False)
    except KeyboardInterrupt:
        pass
    finally:
        build_and_flush()


if __name__ == "__main__":
    main()
