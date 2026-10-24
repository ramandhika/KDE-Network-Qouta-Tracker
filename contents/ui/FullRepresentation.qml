/*
    Popup widget:
      - Jaringan aktif + kuota hari ini di jaringan itu (counter per jaringan,
        reset otomatis tiap hari; pindah jaringan → angka mulai dari 0)
      - Split IP: lokal / IPv6 / publik
      - Rekap semua jaringan yang dipakai hari ini + bar kecepatan penggunaan
      - Seluruh isi popup berada dalam SATU Flickable (tidak ada Flickable
        bersarang): kalau konten lebih tinggi dari popup, tinggal scroll —
        tidak ada lagi teks yang terpotong di tepi popup.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
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

    // ukuran popup — ramping; semua label yang bisa panjang wrap dan seluruh
    // konten bisa di-scroll, jadi tidak ada teks yang meluber/terpotong
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredHeight: Kirigami.Units.gridUnit * 20
    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 17

    // padding konten di dalam area scroll
    readonly property real contentMargin: Kirigami.Units.largeSpacing * 2

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
        : ""

    // bar rekap pakai skala max usage
    readonly property real maxUsage: {
        var m = 0.0001
        for (var i = 0; i < list.length; ++i) {
            m = Math.max(m, list[i].down + list[i].up)
        }
        return m
    }

    // lebar kolom konstan (pola TextMetrics — docs KDE): angka berubah tidak menggeser layout
    // font default saja — sama persis dengan font default PC3.Label yang dipakai nilainya
    TextMetrics {
        id: valMetrics
        text: "⇣ 999.9 GB/s"
    }
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
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font.pointSize: Kirigami.Units.defaultFontPointSize - 1
        font.letterSpacing: 0.8
    }

    // Baris IP yang bisa diklik untuk menyalin nilainya ke clipboard.
    component CopyableLabel: PC3.Label {
        id: copyable
        property string value: ""

        signal copyRequested()

        Layout.fillWidth: true
        elide: Text.ElideRight
        Accessible.role: value.length > 0 ? Accessible.Button : Accessible.StaticText
        Accessible.name: text
        Accessible.description: value.length > 0 ? "Activate to copy to clipboard" : ""
        Accessible.onPressAction: copyable.copyRequested()

        TapHandler {
            enabled: copyable.value.length > 0
            cursorShape: Qt.PointingHandCursor
            onTapped: copyable.copyRequested()
        }
    }

    // Satu-satunya area scroll: seluruh isi popup. Dengan begini tinggi konten
    // tidak dipaksa mengikuti tinggi popup, jadi tidak ada teks yang kepotong.
    Flickable {
        id: popupFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentCol.height + fullRep.contentMargin * 2
        boundsBehavior: Flickable.StopAtBounds

        // Sengaja tetap Flickable, TAPI dengan scrollbar tipis (auto-hide):
        // tanpa indikator ini daftar rekap terlihat "hilang" karena baris
        // kedua dan seterusnya berada di bawah lipatan popup.
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
                spacing: Kirigami.Units.mediumSpacing
                Layout.alignment: Qt.AlignTop

                Kirigami.Icon {
                    source: {
                        if (String(d.type) === "wifi") {
                            return "network-wireless"
                        }
                        if (String(d.type) === "ethernet") {
                            return "network-wired"
                        }
                        return "network-connect"
                    }
                    fallback: "network-wireless"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    PC3.Label {
                        text: d.net || "Not connected"
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    PC3.Label {
                        visible: text.length > 0
                        text: fullRep.d.iface
                              ? fullRep.d.iface + " || " + (fullRep.d.type || "network")
                              : ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                        Layout.fillWidth: true
                        elide: Text.ElideRight
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
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            // ============ SPLIT IP (LOKAL / IPv6 / PUBLIK) ============
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                SectionLabel { text: "IP addresses" }

                // split: lokal dan publik terpisah — klik = salin ke clipboard
                CopyableLabel {
                    text: "Local: " + (fullRep.d.ip || "–")
                    value: fullRep.d.ip
                    onCopyRequested: clipHelper.copyText(value)
                }
                PC3.Label {
                    visible: fullRep.d.ip6 ? (fullRep.d.ip6.length > 0) : false
                    text: visible ? "IPv6: " + fullRep.d.ip6 : ""
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                CopyableLabel {
                    text: "Public: " + (fullRep.d.pubip || "...")
                    value: fullRep.d.pubip
                    color: Kirigami.Theme.disabledTextColor
                    onCopyRequested: clipHelper.copyText(value)
                }
            }

            // ============ KUOTA HARI INI DI JARINGAN AKTIF ============
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                SectionLabel { text: "Today's usage (" + (fullRep.dayLabel || fullRep.d.day || "") + ") resets daily" }

                PC3.Label {
                    // jaringan aktif saja — font sedikit dikecilkan + wrap,
                    // SSID panjang tidak meluber keluar kolom
                    text: (fullRep.d.net || "–")
                          + " → " + (fullRep.fmtBytes ? fullRep.fmtBytes(fullRep.curr.down + fullRep.curr.up) : "")
                    font.pointSize: Kirigami.Units.defaultFontPointSize + 3
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PC3.Label {
                        Layout.minimumWidth: valMetrics.width
                        horizontalAlignment: Text.AlignRight
                        text: "⇣ " + (fullRep.fmtBytes ? fullRep.fmtBytes(fullRep.curr.down) : "")
                        color: compact2.colDown
                    }
                    PC3.Label {
                        Layout.minimumWidth: valMetrics.width
                        horizontalAlignment: Text.AlignRight
                        text: "⇡ " + (fullRep.fmtBytes ? fullRep.fmtBytes(fullRep.curr.up) : "")
                        color: compact2.colUp
                    }
                }
                PC3.Label {
                    // rekap gabungan seluruh jaringan hari ini — wrap biar tidak overflow
                    text: "All networks today: " + (fullRep.fmtBytes
                           ? fullRep.fmtBytes(fullRep.total.down + fullRep.total.up) : "")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Units.defaultFontPointSize - 1
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }

            // ============ REKAP JARINGAN HARI INI ============
            Kirigami.Separator {
                Layout.fillWidth: true
            }
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

                SectionLabel { text: "Today's networks (" + fullRep.list.length + ")" }

                // daftar ikut scroll bersama seluruh popup (tanpa Flickable
                // bersarang) — baris panjang tidak akan terpotong
                ColumnLayout {
                    id: recapCol
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

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
                                spacing: Kirigami.Units.smallSpacing
                                Layout.fillWidth: true

                                PC3.Label {
                                    text: (row.activeNet ? "● " : "") + modelData.name
                                    font.bold: row.activeNet
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                PC3.Label {
                                    Layout.minimumWidth: usageMetrics.width
                                    horizontalAlignment: Text.AlignRight
                                    text: fullRep.fmtBytes ? fullRep.fmtBytes(row.usage) : ""
                                    // warna netral: penanda jaringan aktif cukup ● + tebal
                                    color: Kirigami.Theme.textColor
                                }
                            }

                            // bar perbandingan paket — warna netral seragam semua baris
                            // (highlight biru di bawah nama wifi aktif terlihat aneh)
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4

                                Rectangle {
                                    width: parent.width * Math.min(1, row.usage / fullRep.maxUsage)
                                    height: parent.height
                                    radius: 1
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }

                            PC3.Label {
                                visible: text.length > 0
                                text: {
                                    var p = []
                                    if (modelData.ip) {
                                        p.push(modelData.ip)
                                    }
                                    if (modelData.first && modelData.last) {
                                        p.push(Qt.formatTime(new Date(modelData.first * 1000), "HH:mm")
                                               + "–" + Qt.formatTime(new Date(modelData.last * 1000), "HH:mm"))
                                    }
                                    if (row.activeNet && fullRep.d.pubip) {
                                        p.push("public: " + fullRep.d.pubip)
                                    }
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
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }

            // ============ FOOTER ============
            PC3.Label {
                text: "Counters reset daily. History is kept for 90 days."
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Units.defaultFontPointSize - 2
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }
    }

    // kotak warna konsisten
    QtObject {
        id: compact2
        readonly property color colDown: "#3daee9"
        readonly property color colUp: "#e9783d"
    }
}
