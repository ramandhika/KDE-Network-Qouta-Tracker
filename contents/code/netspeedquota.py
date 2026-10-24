#!/usr/bin/env python3
# netspeedquota.py — helper untuk widget Plasma "Network Speed Quota" (org.ram.netspeed)
#
# Perilaku:
#   * Byte rx/tx dibaca dari /proc/net/dev per interval polling (default 1 dtk).
#   * Hanya interface yang MENJADI DEFAULT ROUTE yang dihitung (jaringan yang
#     sedang dipakai) → antre VPN/tunnel tidak dihitung dobel.
#   * Kuota per hari disimpan PER JARINGAN (SSID/ethernet) di
#     ~/.local/state/netspeed-quota/daily/YYYY-MM-DD.json → reset otomatis tiap hari.
#   * Nama jaringan: SSID WiFi (dibaca tiap poll via `iw link`) atau
#     "Ethernet (iface)" → tiap SSID punya entri rekap sendiri.
#   * IP lokal diperoleh dari `ip -j addr`, IP publik dari api.ipify.org (cache).
#   * Output: JSON satu baris (dibaca widget lewat DataEngine "executable").
#
# Memastikan beberapa instance widget tidak dobel menghitung: flock di state dir.
import datetime
import json
import os
import subprocess
import sys
import time
from fcntl import flock, LOCK_EX

HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, ".local", "state", "netspeed-quota")
DAILY_DIR = os.path.join(STATE_DIR, "daily")
STATE_PATH = os.path.join(STATE_DIR, "state.json")

STALE_DEV = 600        # det  — cache tipe perangkat (nmcli)
STALE_NETNAME = 300    # det  — cache IP lokal per interface (identitas jaringan selalu segar)
PUBLIC_STALE = 12 * 3600  # det — refresh IP publik
MAX_KEEP_DAYS = 90     # berkas rekap harian disimpan selama ini

USE_PUBLIC_IP = "--no-pubip" not in sys.argv


def run(cmd, timeout=5):
    try:
        p = subprocess.run(
            cmd, timeout=timeout, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        if p.returncode == 0:
            return p.stdout.strip()
    except Exception:
        pass
    return None


def read_counters():
    """Parse /proc/net/dev -> {iface: (rx_bytes, tx_bytes)}"""
    out = {}
    try:
        with open("/proc/net/dev") as f:
            lines = f.read().splitlines()
    except Exception:
        return out
    for line in lines[2:]:
        if ":" not in line:
            continue
        iface, rest = line.split(":", 1)
        iface = iface.strip()
        fields = rest.split()
        if len(fields) >= 9:
            try:
                out[iface] = (int(fields[0]), int(fields[8]))
            except ValueError:
                pass
    return out


EXCLUDE_PFX = ("lo", "p2p-", "veth", "virbr", "docker", "wg-", "tailscale", "br-", "zt")


def iface_relevant(iface):
    return not iface.startswith(EXCLUDE_PFX)


def default_dev():
    js = run(["ip", "-j", "-4", "route", "show", "default"])
    if not js:
        return None
    try:
        return json.loads(js)[0].get("dev")
    except Exception:
        return None


def local_ips(dev):
    js = run(["ip", "-j", "-o", "addr", "show", "dev", dev])
    if not js:
        return []
    try:
        out = []
        for dump in json.loads(js):
            for a in dump.get("addr_info", []):
                if a.get("scope") == "global":
                    out.append(a)
        return out
    except Exception:
        return []


def device_types():
    txt = run(["nmcli", "-t", "-f", "DEVICE,TYPE", "device"], timeout=6)
    m = {}
    if txt:
        for line in txt.splitlines():
            parts = line.split(":")
            if len(parts) == 2 and parts[0] not in ("", "LO"):
                m[parts[0]] = parts[1]
    return m


def _num(val):
    try:
        return float(val.split()[0])
    except (ValueError, IndexError):
        return None


def wifi_link(dev):
    """Detail AP yang benar-benar tersambung. `iw link` ~1 ms dan tidak
    memicu scan (nmcli `wifi list` ~13 ms dan bisa scan)."""
    txt = run(["iw", "dev", dev, "link"], timeout=2)
    info = {}
    for line in (txt or "").splitlines():
        line = line.strip()
        if line.startswith("SSID: "):
            info["ssid"] = line[6:]
        elif line.startswith("freq: "):
            info["freq"] = _num(line[6:])
        elif line.startswith("signal: "):
            info["signal"] = _num(line[8:])
        elif line.startswith("rx bitrate: "):
            info["rate"] = _num(line[12:])
    return info


def wifi_ssid(dev):
    # 1) SSID sebenarnya dari AP aktif (tanpa scan bila hasil NM masih segar)
    txt = run(["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi", "list",
               "ifname", dev, "--rescan", "no"], timeout=6)
    if txt:
        for line in txt.splitlines():
            if line.startswith("yes:"):
                return line[4:].replace("\\:", ":")
    # 2) fallback: nama profil koneksi (umumnya sama dengan SSID)
    txt = run(["nmcli", "-t", "device", "show", dev], timeout=6)
    if txt:
        for line in txt.splitlines():
            if line.startswith("GENERAL.CONNECTION:"):
                return line.split(":", 1)[1].strip()
    return ""


TYPE_NAME = {
    "wifi": "WiFi",
    "ethernet": "Ethernet",
    "tun": "VPN",
    "tap": "VPN",
    "gsm": "Seluler",
    "bluez": "Bluetooth",
    "bridge": "Bridge",
    "vlan": "VLAN",
}


def net_name_of(dev, devtype, ssid):
    if devtype == "wifi":
        return ssid or f"WiFi ({dev})"
    return f"{TYPE_NAME.get(devtype, devtype)} ({dev})"


def public_ip_cached(st, key):
    pub = st.setdefault("public", {})
    ts = time.time()
    if pub.get("ip") and pub.get("key") == key and ts - pub.get("ts", 0) < PUBLIC_STALE:
        return pub["ip"]
    ip = run(["curl", "-s", "-m", "3", "https://api.ipify.org"], timeout=5)
    if ip and len(ip) < 64:
        pub.update(ip=ip, key=key, ts=ts)
    return pub.get("ip") or ""


def nm_connectivity():
    """Status konektivitas NetworkManager tanpa pemicu check: full/portal/limited/none."""
    txt = run(["nmcli", "-t", "-f", "CONNECTIVITY", "general"], timeout=4)
    return txt if txt in ("full", "portal", "limited", "none") else ""


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def save_json_atomic(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(tmp, path)


def prune_old_days():
    cutoff = time.time() - MAX_KEEP_DAYS * 86400
    try:
        for fn in os.listdir(DAILY_DIR):
            p = os.path.join(DAILY_DIR, fn)
            if os.stat(p).st_mtime < cutoff:
                os.remove(p)
    except OSError:
        pass


def main():
    os.makedirs(DAILY_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, ".lock"), "a") as lock:
        flock(lock, LOCK_EX)

        ts = time.time()
        day = datetime.datetime.now().strftime("%Y-%m-%d")

        st = load_json(STATE_PATH, {})
        if not isinstance(st, dict):
            st = {}
        res = st.get("res") if isinstance(st.get("res"), dict) else {}
        st["res"] = res  # pastikan tersimpan: supaya SSID/ganti nama ter-record alias
        last = st.get("counters") if isinstance(st.get("counters"), dict) else {}

        counters = {i: c for i, c in read_counters().items() if iface_relevant(i)}

        # --- delta & kecepatan per interface ---
        dt = ts - (st.get("lastTs") or ts)
        dt = dt if dt > 0 else 0
        speed, deltas = {}, {}
        for i, (rx, tx) in counters.items():
            prx, ptx = last.get(i, (rx, tx))
            if rx < prx or tx < ptx:      # reboot: counter ter-reset
                drx, dtx = 0, 0
            else:
                drx, dtx = rx - prx, tx - ptx
            deltas[i] = (drx, dtx)
            if dt > 0:
                speed[i] = {"down": drx / dt, "up": dtx / dt}
        st["counters"] = counters
        st["lastTs"] = ts

        dev = default_dev()
        if not dev:
            dev = st.get("lastDev")       # netdown sementara: pakai jaringan terakhir
            st["retain"] = True
        else:
            st.pop("retain", None)
        st["lastDev"] = dev

        # --- tipe perangkat (cache, hemat pemanggilan nmcli) ---
        devtypes = st.get("devtypes") if isinstance(st.get("devtypes"), dict) else {}
        if not devtypes or ts - (st.get("devTs") or 0) > STALE_DEV:
            for d, t in device_types().items():
                devtypes[d] = t
            st["devtypes"] = devtypes
            st["devTs"] = ts
        devtype = devtypes.get(dev, "") if dev else ""
        if dev and not devtype:
            devtype = "wifi" if dev.startswith("wl") else "ethernet"

        # --- berkas rekap harian (reset otomatis per hari) ---
        daily_path = os.path.join(DAILY_DIR, day + ".json")
        daily = load_json(daily_path, None)
        if not isinstance(daily, dict) or daily.get("date") != day:
            daily = {"date": day, "list": {}, "total": {"down": 0, "up": 0}}
        entries = daily["list"]

        active = None
        winfo = {}
        if dev:
            r = res.setdefault(dev, {"type": devtype})

            # Identitas jaringan dibaca SETIAP poll (~1 ms, tanpa scan). Dulu
            # nama/SSID di-cache 300 dtk sehingga ganti WiFi tidak terlihat dan
            # delta WiFi baru dicatat ke entri WiFi lama (dua WiFi menyatu).
            ssid = ""
            if devtype == "wifi":
                winfo = wifi_link(dev)
                ssid = winfo.get("ssid") or r.get("ssid") or wifi_ssid(dev)
                r["ssid"] = ssid
            name = net_name_of(dev, devtype, ssid)
            switched = name != r.get("name")
            r["name"] = name
            r["type"] = devtype

            # IP lokal: refresh saat jaringan berganti atau cache tua
            if switched or ts - r.get("ts", 0) > STALE_NETNAME:
                ips = local_ips(dev)
                r["ip"] = next((a["local"] for a in ips
                                if a["family"] == "inet"), "")
                r["ip6"] = next((a["local"] for a in ips
                                 if a["family"] == "inet6"
                                 and a.get("scope") == "global"), "")
                r["ts"] = ts

            e = entries.get(name)
            if e is None:
                e = entries.setdefault(name, {
                    "name": name, "type": devtype, "iface": dev,
                    "ip": r.get("ip", ""), "ip6": r.get("ip6", ""),
                    "down": 0.0, "up": 0.0, "first": ts, "last": ts,
                })
            drx, dtx = deltas.get(dev, (0, 0))
            if e.get("ip") != r.get("ip", "") or e.get("ip6") != r.get("ip6", ""):
                e["ip"], e["ip6"] = r.get("ip", ""), r.get("ip6", "")
            e["type"] = devtype
            e["down"] += drx
            e["up"] += dtx
            e["last"] = ts
            active = e

        # total = jumlah seluruh entri hari ini
        daily["total"] = {
            "down": sum(x.get("down", 0) for x in entries.values()),
            "up": sum(x.get("up", 0) for x in entries.values()),
        }
        daily["date"] = day

        if st.get("today", day) != day:
            prune_old_days()
        st["today"] = day

        # catat dulu delta & state SEBELUM fetch pubip (fetch bisa 3 s)
        save_json_atomic(daily_path, daily)
        save_json_atomic(STATE_PATH, st)

        pubip = ""
        if USE_PUBLIC_IP and active:
            key = "net:" + active["name"]
            pubip = public_ip_cached(st, key)
            # simpan cache pubip tanpa mengubah counter yang sudah dicatat
            save_json_atomic(STATE_PATH, st)

    # --- keluaran JSON untuk widget (di luar lock, hanya membaca hasil) ---
    lst = sorted(
        (
            {
                "name": v.get("name", k), "type": v.get("type", ""),
                "iface": v.get("iface", ""), "ip": v.get("ip", ""),
                "ip6": v.get("ip6", ""), "down": v.get("down", 0),
                "up": v.get("up", 0), "first": v.get("first", 0),
                "last": v.get("last", 0),
            }
            for k, v in entries.items()
        ),
        key=lambda x: x.get("last", 0), reverse=True,
    )
    out = {
        "ok": 1,
        "day": day,
        "net": active["name"] if active else None,
        "iface": dev or "",
        "type": devtype or "",
        "ip": (res.get(dev, {}) or {}).get("ip", "") if dev else "",
        "ip6": (res.get(dev, {}) or {}).get("ip6", "") if dev else "",
        "pubip": pubip,
        "wifi": winfo if devtype == "wifi" else {},
        "netstate": nm_connectivity(),
        "speed": speed.get(dev, {"down": 0, "up": 0}) if dev else {"down": 0, "up": 0},
        "curr": ({"down": active["down"], "up": active["up"]} if active else {"down": 0, "up": 0}),
        "list": lst,
        "total": daily["total"],
    }
    print(json.dumps(out, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # selalu output JSON valid agar QML aman
        print(json.dumps({"ok": 0, "err": str(exc)}))
