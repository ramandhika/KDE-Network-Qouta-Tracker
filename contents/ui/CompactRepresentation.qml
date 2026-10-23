/*
    Panel (kiri → kanan): [dot internet] [⇣ download] [⇡ upload]  (+ baris "Today" opsional)
    - Kecepatan = sensor ksysguard (network/all/*) sama dengan widget stok (1 dtk).
    - FIXED width per item: kolom ⇣/⇡ dikunci ke lebar nilai realistis terlebar
      (diukur TextMetrics) dengan clamp sweet spot 4.5–6 GU — angka berubah tiap
      detik tidak menggeser layout panel, tapi panel tidak melebar sembarangan.
    - Dot indikator (netstate = nmcli CONNECTIVITY):
        hijau = full, kuning = portal/limited, merah = none.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as SG

RowLayout {
    id: compact

    // disuntik dari main.qml
    property var d: ({})
    property var speed: ({"down": 0, "up": 0})
    property var total: ({"down": 0, "up": 0})
    property var fmtBytes: null
    property var fmtRate: null

    readonly property bool showToday:
        Plasmoid.configuration.showTodayInPanel

    readonly property color colDown: "#3daee9"
    readonly property color colUp: "#e9783d"

    readonly property bool sensorsReady:
        downSensor.status === SG.Sensor.Ready && upSensor.status === SG.Sensor.Ready

    // warna dot konnektivitas
    readonly property color dotColor: {
        var st = String(d.netstate || "")
        if (st === "full") return "#2ecc71"
        if (st === "portal" || st === "limited") return "#f1c40f"
        if (st === "none") return "#e74c3c"
        return Kirigami.Theme.disabledTextColor
    }

    // ukuran fixed
    readonly property real iconWidth: Kirigami.Units.iconSizes.small

    TextMetrics {
        id: downMetrics
        text: "⇣ 999.9 KiB/s"
    }
    TextMetrics {
        id: upMetrics
        text: "⇡ 999.9 KiB/s"
    }
    // sweet spot: paling lebar di antara kedua kolom diukur dari string nilai
    // realistis terlebar, lalu di-clamp agar tidak sempit (min 4.5 GU)
    // dan tidak kegedean (max 6 GU)
    readonly property real colWidth: {
        var measured = Math.max(downMetrics.width, upMetrics.width)
                       + Kirigami.Units.smallSpacing * 2
        return Math.max(Kirigami.Units.gridUnit * 4.5,
                        Math.min(Kirigami.Units.gridUnit * 6, measured))
    }

    SG.Sensor {
        id: downSensor
        sensorId: "network/all/download"
    }
    SG.Sensor {
        id: upSensor
        sensorId: "network/all/upload"
    }

    // klik widget → buka/tutup popup (pointer handler: bukan anak layout)
    TapHandler {
        onTapped: root.expanded = !root.expanded
    }

    spacing: Kirigami.Units.smallSpacing * 1.5

    // dot indikator internet (kiri) — fixed
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: compact.iconWidth
        Layout.preferredHeight: compact.iconWidth
        width: compact.iconWidth
        height: compact.iconWidth
        radius: width / 2
        color: compact.dotColor
    }

    // kecepatan berdampingan kiri-kanan, lebar kolom fixed
    RowLayout {
        spacing: compact.spacing * 2
        Layout.alignment: Qt.AlignVCenter

        PC3.Label {
            Layout.preferredWidth: compact.colWidth
            text: compact.sensorsReady
                  ? "⇣ " + downSensor.formattedValue
                  : "⇣ " + (compact.fmtRate ? compact.fmtRate(compact.speed.down) : "")
            color: compact.colDown
            Layout.alignment: Qt.AlignVCenter
        }

        PC3.Label {
            Layout.preferredWidth: compact.colWidth
            text: compact.sensorsReady
                  ? "⇡ " + upSensor.formattedValue
                  : "⇡ " + (compact.fmtRate ? compact.fmtRate(compact.speed.up) : "")
            color: compact.colUp
            Layout.alignment: Qt.AlignVCenter
        }
    }

    PC3.Label {
        visible: compact.showToday
        text: visible
              ? "Today: " + (compact.fmtBytes
                             ? compact.fmtBytes(compact.total.down + compact.total.up)
                             : "")
              : ""
        color: Kirigami.Theme.disabledTextColor
        font.pointSize: Kirigami.Units.defaultFontPointSize - 1.5
        Layout.alignment: Qt.AlignHCenter
    }
}
