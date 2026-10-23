#!/usr/bin/env python3
# netstate.py — probe status konektivitas super ringan untuk widget
# "Network Speed Quota" (org.ram.netspeed).
#
# Kenapa tidak memakai state CONNECTIVITY dari NetworkManager saja?
#   State itu diverifikasi berkala (default ~300 dtk). Saat internet mati
#   tetapi WiFi masih tersambung, "full" bisa tertahan lama. Probe ini
#   mengecek sendiri tiap ~0.5 dtk dan mendeteksi link-down secara instan:
#
#     none    → tidak ada default route, atau link interface down
#     full    → ada default route + koneksi TCP ke internet berhasil
#     limited → jaringan lokal ada, tetapi internet tidak terjangkau
#
# Probe memakai TCP connect (handshake saja, tanpa mengirim data) supaya
# tidak menambah pemakaian kuota seperti probe HTTP.
#
# Output: satu baris JSON {"state": "...", "dev": "..."}.
#   state kosong ("") berarti "tidak ada pembaruan" — widget mempertahankan
#   warna terakhir alih-alih berkedip keliru saat terjadi error sesaat.
import json
import os
import socket
import subprocess
import time

CACHE_TTL = 2.0        # detik — cache hasil sukses (hemat handshake TCP)
PROBE_BUDGET = 1.0     # detik — total anggaran percobaan saat offline
PROBE_ATTEMPT = 0.5    # detik — batas satu percobaan
TARGETS = (
    ("1.1.1.1", 443),                 # Cloudflare
    ("9.9.9.9", 443),                 # Quad9
    ("2606:4700:4700::1111", 443),    # Cloudflare IPv6
)


def default_dev():
    """Interface pada default route (IPv4 dulu, lalu IPv6)."""
    for fam in ("-4", "-6"):
        try:
            out = subprocess.run(
                ["ip", fam, "-j", "route", "show", "default"],
                capture_output=True, text=True, timeout=2,
            ).stdout
            dev = json.loads(out or "[]")[0].get("dev")
            if dev:
                return dev
        except Exception:
            pass
    return None


def link_up(dev):
    """Cek link dari sysfs — instan, tanpa memanggil nmcli."""
    try:
        with open("/sys/class/net/%s/operstate" % dev) as f:
            return f.read().strip() in ("up", "unknown")
    except OSError:
        return True  # perangkat virtual bisa tak punya operstate


def cache_path():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(base, "netspeed-netstate-cache.json")


def read_cache(dev):
    try:
        with open(cache_path()) as f:
            c = json.load(f)
        if c.get("dev") == dev and c.get("ok"):
            if time.time() - c.get("ts", 0) < CACHE_TTL:
                return True
    except Exception:
        pass
    return False


def write_cache(dev):
    try:
        with open(cache_path(), "w") as f:
            json.dump({"dev": dev, "ts": time.time(), "ok": True}, f)
    except OSError:
        pass


def probe_internet(dev):
    """TCP connect ke beberapa target publik; sukses di-cache 2 dtk.

    Hasil gagal sengaja TIDAK di-cache supaya mati internet terdeteksi
    cepat, tetapi total waktu percobaan dibatasi PROBE_BUDGET."""
    if read_cache(dev):
        return True

    deadline = time.time() + PROBE_BUDGET
    for host, port in TARGETS:
        left = deadline - time.time()
        if left <= 0.05:
            break
        sock = None
        try:
            sock = socket.create_connection(
                (host, port), timeout=min(PROBE_ATTEMPT, left))
            write_cache(dev)
            return True
        except OSError:
            continue
        finally:
            if sock is not None:
                sock.close()
    return False


def main():
    dev = default_dev()
    if not dev:
        print(json.dumps({"state": "none", "dev": ""}))
        return
    if not link_up(dev):
        print(json.dumps({"state": "none", "dev": dev}))
        return
    state = "full" if probe_internet(dev) else "limited"
    print(json.dumps({"state": state, "dev": dev}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # jangan flip warna palsu saat error sesaat; widget pakai state terakhir
        print(json.dumps({"state": "", "dev": ""}))
