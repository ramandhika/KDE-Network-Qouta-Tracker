/*
    Network Speed Quota — main.qml
    Tampilan panel meniru widget "Network Speed" stok (org.kde.plasma.systemmonitor.net).
    Hover & popup → kuota hari ini di jaringan yang SEDANG DIPAKAI (counter per
    jaringan, ter-reset otomatis tiap hari), rekap semua jaringan hari ini, dan
    split IP (lokal / publik).
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // ---- data dari helper (JSON) ----
    property var d: ({})

    // status konektivitas cepat untuk dot panel (probe sendiri ~3 dtk,
    // tidak menunggu verifikasi berkala dari NetworkManager)
    property string netstateFast: ""

    readonly property var speed: d.speed || ({"down": 0, "up": 0})
    readonly property var total: d.total || ({"down": 0, "up": 0})
    // kuota hari ini di jaringan aktif (reset saat ganti jaringan → mulai dari 0)
    readonly property var curr: d.curr || ({"down": 0, "up": 0})

    // ---- format helper (dipakai semua representation) ----
    function fmtBytes(b) {
        var v = Number(b) || 0
        var i = 0
        var units = ["B", "KB", "MB", "GB", "TB"]
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024
            ++i
        }
        var num = (i >= 2) ? Number(v).toFixed(v >= 100 ? 0 : 1) : String(Math.round(v))
        return num + " " + units[i]
    }
    function fmtRate(bs) {
        return fmtBytes(bs) + "/s"
    }

    Plasmoid.title: d.net || "Network Speed Quota"
    Plasmoid.icon: d.type === "wifi" ? "network-wireless" : "network-wired"

    // Hover: kuota hari ini di jaringan aktif + split IP
    toolTipMainText: d.net || "Tidak terhubung"
    toolTipSubText: "Hari ini: " + fmtBytes(curr.down + curr.up)
        + (d.ip ? " || IP Lokal: " + d.ip : "")
        + (d.pubip ? " || IP Publik: " + d.pubip : "")

    switchWidth: Kirigami.Units.gridUnit * 9
    switchHeight: Kirigami.Units.gridUnit * 9

    compactRepresentation: CompactRepresentation {
        d: root.d
        netstateFast: root.netstateFast
        speed: root.speed
        total: root.total
        fmtBytes: root.fmtBytes
        fmtRate: root.fmtRate
    }
    fullRepresentation: FullRepresentation {
        d: root.d
        curr: root.curr
        total: root.total
        fmtBytes: root.fmtBytes
        fmtRate: root.fmtRate
    }

    P5Support.DataSource {
        id: ds
        engine: "executable"
        readonly property url scriptUrl: Qt.resolvedUrl("../code/netspeedquota.py")
        readonly property string basePath: scriptUrl.toString().replace(/^(file:\/\/|file:\/\/\/)/, "/")

        // sumber: `python3 <path> [--no-pubip]`
        readonly property string script:
            "sh -c 'python3 \"" + basePath + "\""
            + (Plasmoid.configuration.usePublicIp ? "" : " --no-pubip") + "'"

        connectedSources: [script]

        interval: Math.max(500, Plasmoid.configuration.updateInterval)

        onNewData: (source, data) => {
            if (source !== connectedSources[0]) {
                disconnectSource(source)
                return
            }
            // engine "executable": data = {"exit code", "exit status", stdout, stderr}
            // → parse data.stdout. Bila gagal: pertahankan data valid terakhir.
            try {
                var parsed = JSON.parse(String(data.stdout))
                if (parsed && typeof parsed === "object") {
                    root.d = parsed
                    if (parsed.ok !== 1) {
                        console.warn("netspeedquota:", parsed.err || "helper error")
                    }
                }
            } catch (e) {
                console.warn("netspeedquota: JSON tidak valid dari helper — diabaikan")
            }
        }
    }

    // Probe ringan khusus dot status: responsif (3 dtk — sejalan budget respons)
    // dan mendeteksi link-down instan lewat sysfs (lihat contents/code/netstate.py).
    P5Support.DataSource {
        id: fastNetState
        engine: "executable"
        readonly property url scriptUrl: Qt.resolvedUrl("../code/netstate.py")
        readonly property string basePath: scriptUrl.toString().replace(/^(file:\/\/|file:\/\/\/)/, "/")
        readonly property string script: "sh -c 'python3 \"" + basePath + "\"'"

        connectedSources: [script]
        interval: 3000

        onNewData: (source, data) => {
            if (source !== connectedSources[0]) {
                disconnectSource(source)
                return
            }
            try {
                var parsed = JSON.parse(String(data.stdout))
                if (parsed && typeof parsed.state === "string" && parsed.state.length > 0) {
                    root.netstateFast = parsed.state
                }
            } catch (e) {
                // biarkan state terakhir — jangan berkedip merah palsu
            }
        }
    }
}
