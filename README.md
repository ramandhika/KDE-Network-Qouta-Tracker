# Network Speed Quota — KDE Plasma 6

Widget panel KDE Plasma 6 untuk memantau **kecepatan jaringan realtime** dan **kuota harian per jaringan** langsung dari panel, plus popup rekap pemakaian semua jaringan hari ini.

> Counter dihitung per jaringan (SSID WiFi / Ethernet), **reset otomatis tiap hari**, dan hanya mencatat interface yang sedang menjadi default route — jadi trafik VPN/tunnel tidak terhitung dobel.

---

## Fitur

- **Panel**: kecepatan `⇣` unduh dan `⇡` unggah (lebar kolom terkunci — angka berubah tiap detik tidak menggeser layout), dot status konektivitas (hijau = penuh, kuning = portal/terbatas, merah = putus).
- **Popup (satu area scroll, teks wrap — tidak ada yang terpotong)**:
  - Jaringan aktif + kuota hari ini di jaringan tersebut.
  - Split IP: **Lokal**, **IPv6**, **Publik**.
  - Pemakaian `⇣` / `⇡` hari ini di jaringan aktif.
  - **Rekap Jaringan Hari Ini**: semua jaringan yang dipakai hari ini + bar perbandingan pemakaian, diurutkan dari yang terakhir aktif.
- **Counter harian per jaringan**: pindah WiFi → angka jaringan baru mulai dari 0; pindah balik → angka lama tetap.
- Reset otomatis saat ganti hari (tanggal lokal), arsip harian disimpan **90 hari**.
- Beberapa instance widget tidak menghitung dobel (`flock` pada state dir).
- Konfigurasi: interval update, IP publik on/off, tampilkan total hari ini di panel.

---

## Kebutuhan

| Komponen | Keterangan |
|---|---|
| KDE Plasma | 6.0 atau lebih baru (Wayland/X11) |
| Linux | `fcntl`/`/proc/net/dev` — khusus Linux |
| Python | 3.8+ (`python3`) |
| NetworkManager | `nmcli` untuk nama SSID & status konektivitas |
| iproute2 | perintah `ip` (routing & IP lokal) |
| curl | opsional — mengambil IP publik dari `api.ipify.org` |
| Sensor KSysGuard | untuk kecepatan panel (tersedia di instalasi Plasma standar) |

---

## Instalasi

### 1. Clone repositori

```bash
git clone https://github.com/ramandhika/KDE-Network-Qouta-Tracker.git
cd KDE-Network-Qouta-Tracker
```

### 2. Pasang widget

**Cara utama (disarankan) — `kpackagetool6`:**

```bash
kpackagetool6 --type Plasma/Applet --install .
```

Jika widget sudah pernah terpasang dan ingin memperbarui:

```bash
kpackagetool6 --type Plasma/Applet --upgrade .
```

**Cara manual (tanpa kpackagetool6):**

```bash
mkdir -p ~/.local/share/plasma/plasmoids/org.ram.netspeed
cp -r metadata.json contents ~/.local/share/plasma/plasmoids/org.ram.netspeed/
```

### 3. Muat ulang Plasma

```bash
systemctl --user restart plasma-plasmashell.service
```

Alternatif: logout lalu login kembali. (Kalau menjalankan plasmashell manual: `plasmashell --replace &`.)

### 4. Tambahkan ke panel

1. Klik kanan panel → **Enter Edit Mode** (atau **Add Widgets / Tambah Widget**).
2. Cari **“Network Speed Quota”**.
3. Drag ke panel, lalu klik widget untuk membuka popup.

Selesai — tidak perlu konfigurasi tambahan; helper Python dijalankan otomatis oleh widget.

---

## Konfigurasi

Klik kanan widget → **Configure Network Speed Quota…**

| Opsi | Default | Keterangan |
|---|---|---|
| `updateInterval` | `1000` ms | Interval pembaruan data (minimal 500 ms) |
| `usePublicIp` | `true` | Ambil IP publik via `api.ipify.org` (cache 12 jam). Matikan bila offline atau tidak ingin keluar jaringan |
| `showTodayInPanel` | `false` | Tampilkan total kuota hari ini di panel (baris “Today” di bawah kecepatan) |

---

## Cara kerja & data

- Byte `rx/tx` dibaca dari **`/proc/net/dev`** setiap interval; hanya interface **default route** yang dihitung.
- Nama jaringan: SSID WiFi via `nmcli`, atau `Ethernet (iface)` / tipe lain.
- Data harian: `~/.local/state/netspeed-quota/daily/YYYY-MM-DD.json`
  State internal: `~/.local/state/netspeed-quota/state.json`
- Rekap lebih tua dari 90 hari dipangkas otomatis.
- Satu-satunya koneksi keluar adalah permintaan IP publik ke `api.ipify.org` (dapat dimatikan pada konfigurasi).
- Helper selalu mengeluarkan JSON valid (termasuk saat error), sehingga widget tidak crash.

---

## Troubleshooting

| Gejala | Solusi |
|---|---|
| Widget tidak muncul di daftar | Pastikan Plasma 6; ulangi langkah 3; cek `kpackagetool6 --type Plasma/Applet --list \| grep org.ram.netspeed` |
| Kecepatan panel selalu 0 | Sensor KSysGuard belum siap — widget otomatis fallback ke data helper; pastikan `libksysguard` terpasang |
| Nama jaringan kosong | NetworkManager tidak aktif atau `nmcli` butuh izin polkit |
| IP publik kosong | `curl`/`api.ipify.org` diblokir — matikan `usePublicIp` |
| “Tidak terhubung” padahal online | Cek `ip route show default`; VPN split-tunnel bisa mengubah default route |
| Ingin melihat log | `journalctl --user -u plasma-plasmashell -f` atau jalankan `plasmashell --replace` dari terminal |

Cek manual helper (output JSON):

```bash
python3 ~/.local/share/plasma/plasmoids/org.ram.netspeed/contents/code/netspeedquota.py
```

---

## Struktur repositori

```
metadata.json
contents/
├── code/
│   └── netspeedquota.py        # helper pengumpul data → JSON (DataEngine executable)
├── config/
│   └── main.xml                # skema konfigurasi (KConfigXT)
└── ui/
    ├── main.qml                # PlasmoidItem, DataSource, format helper
    ├── CompactRepresentation.qml  # tampilan di panel
    └── FullRepresentation.qml     # popup (satu area scroll)
LICENSE
README.md
```

Repositori ini **langsung merupakan paket KPackage** — `metadata.json` dan `contents/` berada di root, sehingga bisa dipasang dengan `kpackagetool6 --type Plasma/Applet --install .`.

---

## Uninstall

```bash
kpackagetool6 --type Plasma/Applet --remove org.ram.netspeed
rm -rf ~/.local/state/netspeed-quota      # hapus juga riwayat kuota harian
```

---

## Lisensi

GPL-2.0-or-later — lihat [LICENSE](LICENSE).
