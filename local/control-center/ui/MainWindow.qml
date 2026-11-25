import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    width: 1120
    height: 740
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "macOS Control Center — Plasma Settings"

    property var parsedState: {
        try {
            return JSON.parse(nexusBridge.stateJson);
        } catch (e) {
            return { categories: [], settings: [], values: {}, profiles: [], undoCount: 0 };
        }
    }
    property var catalogCategories: []
    property var catalogSettings: []
    property var visibleSettings: []
    property string activeCategory: "appearance"
    property string searchQuery: ""
    property bool isDark: (parsedState.values && parsedState.values["appearance.colorMode"] !== "light")

    readonly property color colBg: isDark ? "#17181d" : "#f2f3f7"
    readonly property color colSidebar: isDark ? "#1e2027" : "#e7e9f0"
    readonly property color colCard: isDark ? "#252831" : "#ffffff"
    readonly property color colBorder: isDark ? "#383c49" : "#d0d4e0"
    readonly property color colAccent: "#0a84ff"
    readonly property color colText: isDark ? "#f2f4f8" : "#181a20"
    readonly property color colSubtext: isDark ? "#9aa1b2" : "#5a6070"

    color: colBg

    function rebuildVisibleSettings() {
        const all = root.catalogSettings || [];
        const q = root.searchQuery.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < all.length; ++i) {
            const s = all[i];
            if (q.length > 0) {
                const hay = (String(s.title || "") + " " + String(s.description || "") + " " + String(s.id || "")).toLowerCase();
                if (hay.indexOf(q) >= 0)
                    out.push(s);
            } else if (s.category === root.activeCategory) {
                out.push(s);
            }
        }
        root.visibleSettings = out;
    }

    Component.onCompleted: {
        root.catalogCategories = root.parsedState.categories || [];
        root.catalogSettings = root.parsedState.settings || [];
        root.rebuildVisibleSettings();
    }

    onActiveCategoryChanged: root.rebuildVisibleSettings()
    onSearchQueryChanged: root.rebuildVisibleSettings()

    function currentValueFor(sid) {
        if (!root.parsedState || !root.parsedState.values)
            return undefined;
        return root.parsedState.values[sid];
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // === LEFT PANE: macOS Translucent Sidebar ===
        Rectangle {
            Layout.preferredWidth: 255
            Layout.fillHeight: true
            color: root.colSidebar

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Traffic-light style header + branding
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle { width: 12; height: 12; radius: 6; color: "#ff5f57" }
                    Rectangle { width: 12; height: 12; radius: 6; color: "#febc2e" }
                    Rectangle { width: 12; height: 12; radius: 6; color: "#28c840" }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: "macOS Control Center"
                        font.pixelSize: 13
                        font.bold: true
                        color: root.colText
                    }
                }

                // Live Search Box
                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: "Ayar ara..."
                    color: root.colText
                    placeholderTextColor: root.colSubtext
                    text: root.searchQuery
                    onTextChanged: root.searchQuery = text
                    background: Rectangle {
                        radius: 8
                        color: root.colCard
                        border.color: searchInput.activeFocus ? root.colAccent : root.colBorder
                        border.width: 1
                    }
                }

                // Category List
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.catalogCategories
                    delegate: Rectangle {
                        id: catRow
                        required property var modelData
                        width: ListView.view ? ListView.view.width : 220
                        height: 44
                        radius: 9
                        color: root.activeCategory === modelData.id && root.searchQuery.trim().length === 0
                            ? root.colAccent
                            : (catMouse.containsMouse ? Qt.rgba(1, 1, 1, root.isDark ? 0.06 : 0.4) : "transparent")

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 1
                            Label {
                                text: catRow.modelData.title || ""
                                font.pixelSize: 13
                                font.bold: true
                                color: root.activeCategory === catRow.modelData.id && root.searchQuery.trim().length === 0 ? "#ffffff" : root.colText
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: catRow.modelData.subtitle || ""
                                font.pixelSize: 10
                                color: root.activeCategory === catRow.modelData.id && root.searchQuery.trim().length === 0 ? "#e6f2ff" : root.colSubtext
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.searchQuery = "";
                                root.activeCategory = catRow.modelData.id;
                            }
                        }
                    }
                }
            }
        }

        // Divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: root.colBorder
        }

        // === MAIN CONTENT PANE ===
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Top Toolbar (Quick Actions: Dark/Light + Presets + Undo + Reset)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: root.colSidebar

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 10

                    Label {
                        text: root.searchQuery.trim().length > 0
                            ? "Arama Sonuçları (" + root.visibleSettings.length + ")"
                            : (function() {
                                const cats = root.catalogCategories || [];
                                for (let i = 0; i < cats.length; ++i)
                                    if (cats[i].id === root.activeCategory) return cats[i].title;
                                return "Ayarlar";
                            })()
                        font.pixelSize: 17
                        font.bold: true
                        color: root.colText
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: root.isDark ? "Açık Tema" : "Koyu Tema"
                        onClicked: nexusBridge.toggleDarkLight()
                    }
                    Button {
                        text: "Geri Al (" + (root.parsedState.undoCount || 0) + ")"
                        enabled: (root.parsedState.undoCount || 0) > 0
                        onClicked: nexusBridge.undoLast()
                    }
                    Button {
                        text: "Kategoriyi Sıfırla"
                        visible: root.activeCategory !== "profiles_recovery"
                        onClicked: nexusBridge.resetCategory(root.activeCategory)
                    }
                }
            }

            // Scrollable Settings / Profiles Content
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: root.width - 295
                    x: 18
                    y: 14
                    spacing: 12

                    // Quick Animation Presets bar when inside Animations category
                    Rectangle {
                        visible: root.activeCategory === "animations" && root.searchQuery.trim().length === 0
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 11
                        color: root.colCard
                        border.color: root.colBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            Label {
                                text: "Hızlı Animasyon Profilleri:"
                                font.bold: true
                                color: root.colText
                            }
                            Button { text: "macOS Akıcı (%85)"; onClicked: nexusBridge.applyPreset("macos_smooth") }
                            Button { text: "Seri (Snappy)"; onClicked: nexusBridge.applyPreset("snappy") }
                            Button { text: "Azaltılmış Hareket"; onClicked: nexusBridge.applyPreset("reduced_motion") }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // Profiles & Recovery Panel
                    Rectangle {
                        visible: root.activeCategory === "profiles_recovery" && root.searchQuery.trim().length === 0
                        Layout.fillWidth: true
                        implicitHeight: profCol.implicitHeight + 28
                        radius: 11
                        color: root.colCard
                        border.color: root.colBorder
                        border.width: 1

                        ColumnLayout {
                            id: profCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Label {
                                text: "Kayıtlı Profiller, Geri Alma (Undo) ve Tam Kurtarma"
                                font.pixelSize: 15
                                font.bold: true
                                color: root.colText
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                TextField {
                                    id: newProfileName
                                    Layout.fillWidth: true
                                    placeholderText: "Yeni profil adı (ör. macos-work)..."
                                    color: root.colText
                                    placeholderTextColor: root.colSubtext
                                }
                                Button {
                                    text: "Profili Kaydet"
                                    onClicked: {
                                        if (newProfileName.text.trim().length > 0) {
                                            nexusBridge.saveProfile(newProfileName.text.trim());
                                            newProfileName.text = "";
                                        }
                                    }
                                }
                                Button {
                                    text: "Tümünü Başlangıca Sıfırla"
                                    onClicked: nexusBridge.resetAll()
                                }
                            }
                            Repeater {
                                model: root.parsedState.profiles || []
                                delegate: RowLayout {
                                    id: profRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Label {
                                        Layout.fillWidth: true
                                        text: profRow.modelData.name + " (" + profRow.modelData.settingCount + " ayar)"
                                        color: root.colText
                                    }
                                    Button {
                                        text: "Yükle"
                                        onClicked: nexusBridge.loadProfile(profRow.modelData.name)
                                    }
                                    Button {
                                        text: "Sil"
                                        onClicked: nexusBridge.deleteProfile(profRow.modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    // Setting Cards Repeater
                    Repeater {
                        model: root.visibleSettings
                        delegate: Rectangle {
                            id: sCard
                            required property var modelData
                            readonly property var curVal: root.currentValueFor(modelData.id)

                            Layout.fillWidth: true
                            implicitHeight: cardInner.implicitHeight + 22
                            radius: 11
                            color: root.colCard
                            border.color: root.colBorder
                            border.width: 1

                            RowLayout {
                                id: cardInner
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 14

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Label {
                                        text: sCard.modelData.title || sCard.modelData.id
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: root.colText
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: sCard.modelData.description || ""
                                        font.pixelSize: 11
                                        color: root.colSubtext
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // Boolean Switch
                                Switch {
                                    visible: sCard.modelData.type === "boolean"
                                    checked: Boolean(sCard.curVal)
                                    onToggled: nexusBridge.setSetting(sCard.modelData.id, checked)
                                }

                                // Enum ComboBox
                                ComboBox {
                                    visible: sCard.modelData.type === "enum"
                                    Layout.preferredWidth: 190
                                    model: sCard.modelData.choices || []
                                    currentIndex: {
                                        const ch = sCard.modelData.choices || [];
                                        const idx = ch.indexOf(String(sCard.curVal));
                                        return idx >= 0 ? idx : 0;
                                    }
                                    onActivated: index => {
                                        const ch = sCard.modelData.choices || [];
                                        if (index >= 0 && index < ch.length)
                                            nexusBridge.setSetting(sCard.modelData.id, ch[index]);
                                    }
                                }

                                // Integer SpinBox
                                SpinBox {
                                    visible: sCard.modelData.type === "integer"
                                    from: sCard.modelData.min !== undefined ? sCard.modelData.min : 0
                                    to: sCard.modelData.max !== undefined ? sCard.modelData.max : 100
                                    value: Number.isFinite(Number(sCard.curVal)) ? Math.round(Number(sCard.curVal)) : from
                                    onValueModified: nexusBridge.setSetting(sCard.modelData.id, value)
                                }

                                // Float Number Field + Apply
                                RowLayout {
                                    visible: sCard.modelData.type === "number"
                                    spacing: 6
                                    TextField {
                                        id: numInput
                                        Layout.preferredWidth: 80
                                        text: sCard.curVal !== undefined ? String(sCard.curVal) : ""
                                        color: root.colText
                                        onAccepted: nexusBridge.setSetting(sCard.modelData.id, Number(text))
                                    }
                                    Button {
                                        text: "Uygula"
                                        onClicked: nexusBridge.setSetting(sCard.modelData.id, Number(numInput.text))
                                    }
                                }

                                // String / Filepath Field + Apply
                                RowLayout {
                                    visible: sCard.modelData.type === "string" || sCard.modelData.type === "filepath"
                                    spacing: 6
                                    TextField {
                                        id: strInput
                                        Layout.preferredWidth: 260
                                        text: sCard.curVal !== undefined ? String(sCard.curVal) : ""
                                        color: root.colText
                                        onAccepted: nexusBridge.setSetting(sCard.modelData.id, text)
                                    }
                                    Button {
                                        text: "Uygula"
                                        onClicked: nexusBridge.setSetting(sCard.modelData.id, strInput.text)
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 24 }
                }
            }

            // Bottom Status Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: root.colSidebar
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    text: nexusBridge.statusMessage
                    font.pixelSize: 11
                    color: root.colSubtext
                }
            }
        }
    }
}
