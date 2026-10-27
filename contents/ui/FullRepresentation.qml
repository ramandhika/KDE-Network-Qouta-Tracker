/*
    Popup widget — revamp UI/UX (semua fitur tetap ada):
      - Header: status koneksi (dot), nama jaringan, iface/tipe, detail WiFi
      - Card "TODAY": total jaringan aktif + split ⇣/⇡ + total semua jaringan
      - IP: Local / IPv6 / Public — klik baris = salin (dengan umpan balik ✓)
      - Rekap jaringan hari ini: nama, pemakaian, bar perbandingan, IP + jam
      - Footer: info reset harian

    Prinsip efisiensi:
      - Satu area scroll (tidak ada Flickable bersarang)
      - Key/value sejajar kanan (label kiri, nilai kanan) → mudah dipindai
      - Tanpa garis pemisah berlebih; hierarki lewat spacing + card + tipografi
      - Nilai berubah (byte/jam) tidak menggeser layout (kolom terukur)
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: fullRep

    // disuntik dari main.qml
    property var d: ({})
    property var curr: ({"down": 0, "up": 0})
    property var total: ({"down": 0, "up": 0})
    property var fmtBytes: null
    property var fmtRate: null

    readonly property var list: d.list || []
    readonly property var wifi: d.wifi || ({})

    // ukuran popup — ramping; semua label bisa wrap/elide dan konten scroll,
    // jadi tidak ada teks yang meluber/terpotong
    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
    Layout.preferredHeight: Kirigami.Units.gridUnit * 20
    Layout.minimumWidth: Kirigami.Units.gridUnit * 9
    Layout.minimumHeight: Kirigami.Units.gridUnit * 17

    readonly property real contentMargin: Kirigami.Units.largeSpacing * 1.5

    // ---- warna ----
    readonly property color colDown: "#3daee9"
    readonly property color colUp: "#e9783d"
    // kartu halus: kontras tipis dari background, aman di tema terang/gelap
    readonly property color cardColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                               Kirigami.Theme.textColor.g,
                                               Kirigami.Theme.textColor.b, 0.06)

    // dot status — sama dengan indikator panel
    readonly property color statusColor: {
        var st = String(d.netstate || "")
        if (st === "full")
            return "#2ecc71"
        if (st === "portal" || st === "limited")
            return "#f1c40f"
        if (st === "none")
            return "#e74c3c"
        return Kirigami.Theme.disabledTextColor
    }

    // ---- umpan balik salin ----
    property string copiedField: ""

    Timer {
        id: copyTimer
        interval: 1400
        onTriggered: fullRep.copiedField = ""
    }

    function copyField(field, value) {
        if (!value)
            return
        clipHelper.copyText(value)
        fullRep.copiedField = field
        copyTimer.restart()
    }

    // ---- data turunan ----
    readonly property var dateObj: {
        var s = String(d.day || "")
        if (s.length === 10 && s[4] === "-" && s[7] === "-") {
            return new Date(parseInt(s.slice(0, 4)),
                            parseInt(s.slice(5, 7)) - 1,
                            parseInt(s.slice(8, 10)))
        }
        return null
    }
    readonly property string dayLabel: dateObj
        ? Qt.formatDate(dateObj, "dddd, d MMMM yyyy")
        : String(d.day || "")

    readonly property real maxUsage: {
        var m = 0.0001
        for (var i = 0; i < list.length; ++i) {
            m = Math.max(m, list[i].down + list[i].up)
        }
        return m
    }

    readonly property bool hasIp: String(d.ip || "").length > 0
    readonly property bool hasIp6: String(d.ip6 || "").length > 0
    readonly property bool hasPublicIp: String(d.pubip || "").length > 0

    // lebar kolom tetap agar nilai yang berubah tidak menggeser layout
    TextMetrics {
        id: usageMetrics
        text: "999.9 GB"
    }

    // Clipboard: QML tidak punya API clipboard langsung. TextEdit 0x0 dengan
    // seleksi + copy() adalah pola standar plasmoid (tetap "visible" agar
    // QTextControl punya seleksi aktif).
    TextEdit {
        id: clipHelper
        width: 0
        height: 0
        opacity: 0
        readOnly: true

        function copyText(t) {
            if (!t)
                return
            text = t
            selectAll()
            copy()
        }
    }

    // ---- subkomponen ----
    component SectionLabel: PC3.Label {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: Kirigami.Theme.disabledTextColor
        font.pointSize: Kirigami.Units.defaultFontPointSize - 2
        font.letterSpacing: 0.6
    }

    // Baris key/value; seluruh baris bisa diklik untuk menyalin nilainya.
    component CopyRow: RowLayout {
        id: copyRow
        property string label: ""
        property string value: ""
        property string field: ""

        readonly property bool copied: fullRep.copiedField === field
        readonly property bool hasValue: value.length > 0

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Accessible.role: hasValue ? Accessible.Button : Accessible.StaticText
        Accessible.name: label + ": " + (hasValue ? value : "not available")
        Accessible.description: hasValue ? "Activate to copy to clipboard" : ""
        Accessible.onPressAction: fullRep.copyField(field, value)

        PC3.Label {
            text: copyRow.label
            color: Kirigami.Theme.disabledTextColor
            font.pointSize: Kirigami.Units.defaultFontPointSize - 1
            Layout.alignment: Qt.AlignVCenter
        }
        PC3.Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            text: copyRow.hasValue ? copyRow.value : "—"
            color: copyRow.hasValue ? Kirigami.Theme.textColor
                                   : Kirigami.Theme.disabledTextColor
        }
        PC3.Label {
            Layout.alignment: Qt.AlignVCenter
            visible: copyRow.hasValue
            text: copyRow.copied ? "✓" : "⧉"
            color: copyRow.copied ? Kirigami.Theme.positiveTextColor
                                  : Kirigami.Theme.disabledTextColor
        }

        TapHandler {
            enabled: copyRow.hasValue
            cursorShape: Qt.PointingHandCursor
            onTapped: fullRep.copyField(copyRow.field, copyRow.value)
        }
    }

    // Satu-satunya area scroll: seluruh isi popup.
    Flickable {
        id: popupFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentCol.height + fullRep.contentMargin * 2
        boundsBehavior: Flickable.StopAtBounds

        PC3.ScrollBar.vertical: PC3.ScrollBar {}

        ColumnLayout {
            id: contentCol
            x: fullRep.contentMargin
            y: fullRep.contentMargin
            width: popupFlick.width - fullRep.contentMargin * 2
            height: implicitHeight
            spacing: Kirigami.Units.mediumSpacing

            // ============ HEADER ============
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: {
                        if (String(d.type) === "wifi")
                            return "network-wireless"
                        if (String(d.type) === "ethernet")
                            return "network-wired"
                        return "network-connect"
                    }
                    fallback: "network-wireless"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            Layout.fillWidth: true
                            text: d.net || "Not connected"
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: Math.round(Kirigami.Units.iconSizes.small * 0.55)
                            height: width
                            radius: width / 2
                            color: fullRep.statusColor
                        }
                    }
                    PC3.Label {
                        visible: text.length > 0
                        text: d.iface ? d.iface + " · " + (d.type || "network") : ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    PC3.Label {
                        // detail AP dari `iw link` — ikut berubah tiap poll
                        visible: text.length > 0
                        text: {
                            var p = []
                            if (fullRep.wifi.signal !== undefined
                                    && fullRep.wifi.signal !== null) {
                                p.push(Math.round(fullRep.wifi.signal) + " dBm")
                            }
                            if (fullRep.wifi.freq) {
                                p.push((fullRep.wifi.freq / 1000).toFixed(1) + " GHz")
                            }
                            if (fullRep.wifi.rate) {
                                p.push(Math.round(fullRep.wifi.rate) + " Mbit/s")
                            }
                            return p.join(" · ")
                        }
                        color: Kirigami.Theme.disabledTextColor
                        font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // ============ CARD: TODAY (jaringan aktif) ============
            Rectangle {
                Layout.fillWidth: true
                radius: Kirigami.Units.smallSpacing + 2
                color: fullRep.cardColor
                implicitHeight: todayCol.implicitHeight + Kirigami.Units.largeSpacing * 1.5

                ColumnLayout {
                    id: todayCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing * 0.75
                    spacing: Kirigami.Units.smallSpacing * 0.5

                    PC3.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "TODAY · " + (fullRep.d.net || "—")
                        color: Kirigami.Theme.disabledTextColor
                        font.pointSize: Kirigami.Units.defaultFontPointSize - 2
                        font.letterSpacing: 0.6
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        text: fullRep.fmtBytes
                              ? fullRep.fmtBytes(fullRep.curr.down + fullRep.curr.up)
                              : "—"
                        font.pointSize: Kirigami.Units.defaultFontPointSize + 8
                        font.bold: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Label {
                            text: "⇣ " + (fullRep.fmtBytes ? fullRep.fmtBytes(fullRep.curr.down) : "")
                            color: fullRep.colDown
                            font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                        }
                        PC3.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: "⇡ " + (fullRep.fmtBytes ? fullRep.fmtBytes(fullRep.curr.up) : "")
                            color: fullRep.colUp
                            font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                        }
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "All networks today: "
                              + (fullRep.fmtBytes
                                 ? fullRep.fmtBytes(fullRep.total.down + fullRep.total.up) : "—")
                        color: Kirigami.Theme.disabledTextColor
                        font.pointSize: Kirigami.Units.defaultFontPointSize - 2
                    }
                }
            }

            // ============ IP ADDRESSES ============
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 0.5

                SectionLabel { text: "IP ADDRESSES" }

                CopyRow {
                    label: "Local"
                    value: fullRep.d.ip || ""
                    field: "local"
                }
                CopyRow {
                    visible: fullRep.hasIp6
                    label: "IPv6"
                    value: fullRep.d.ip6 || ""
                    field: "ipv6"
                }
                CopyRow {
                    label: "Public"
                    value: fullRep.d.pubip || ""
                    field: "public"
                }
            }

            // ============ REKAP JARINGAN HARI INI ============
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                SectionLabel {
                    text: "TODAY'S NETWORKS (" + fullRep.list.length + ")"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    Repeater {
                        model: fullRep.list

                        delegate: ColumnLayout {
                            id: row
                            required property var modelData
                            readonly property real usage: modelData.down + modelData.up
                            readonly property bool activeNet:
                                fullRep.d.net === modelData.name

                            spacing: 2
                            Layout.fillWidth: true

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PC3.Label {
                                    Layout.fillWidth: true
                                    text: (row.activeNet ? "● " : "") + modelData.name
                                    font.bold: row.activeNet
                                    elide: Text.ElideRight
                                }
                                PC3.Label {
                                    Layout.minimumWidth: usageMetrics.width
                                    horizontalAlignment: Text.AlignRight
                                    text: fullRep.fmtBytes ? fullRep.fmtBytes(row.usage) : ""
                                    color: Kirigami.Theme.textColor
                                }
                            }

                            // bar perbandingan pemakaian — netral, seragam
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 3

                                Rectangle {
                                    width: parent.width * Math.min(1, row.usage / fullRep.maxUsage)
                                    height: parent.height
                                    radius: height / 2
                                    color: Kirigami.Theme.disabledTextColor
                                    opacity: 0.8
                                }
                            }

                            PC3.Label {
                                visible: text.length > 0
                                text: {
                                    var p = []
                                    if (modelData.ip)
                                        p.push(modelData.ip)
                                    if (modelData.first && modelData.last) {
                                        p.push(Qt.formatTime(new Date(modelData.first * 1000), "HH:mm")
                                               + "–" + Qt.formatTime(new Date(modelData.last * 1000), "HH:mm"))
                                    }
                                    if (row.activeNet && fullRep.d.pubip)
                                        p.push("public: " + fullRep.d.pubip)
                                    return p.join(" · ")
                                }
                                color: Kirigami.Theme.disabledTextColor
                                font.pointSize: Kirigami.Units.defaultFontPointSize - 2
                                Layout.fillWidth: true
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }

                PC3.Label {
                    visible: fullRep.list.length === 0
                    text: "No networks recorded today yet."
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }

            // ============ FOOTER ============
            PC3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Reset daily · history kept 90 days"
                      + (fullRep.dayLabel.length > 0 ? "\n" + fullRep.dayLabel : "")
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Units.defaultFontPointSize - 2
            }
        }
    }
}
