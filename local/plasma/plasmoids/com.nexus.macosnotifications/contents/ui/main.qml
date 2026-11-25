pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.layershell as LayerShell
import org.kde.notificationmanager as NotificationManager

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property bool hasUnread: historyModel.count > 0
    readonly property bool isLightTheme: Kirigami.Theme.backgroundColor.hslLightness > 0.55

    readonly property color cardBg: isLightTheme
        ? Qt.rgba(0.96, 0.96, 0.98, 0.88)
        : Qt.rgba(0.14, 0.15, 0.19, 0.86)
    readonly property color cardBorder: isLightTheme
        ? Qt.rgba(0.0, 0.0, 0.0, 0.14)
        : Qt.rgba(1.0, 1.0, 1.0, 0.22)
    readonly property color cardBorderHover: isLightTheme
        ? Qt.rgba(0.0, 0.0, 0.0, 0.24)
        : Qt.rgba(1.0, 1.0, 1.0, 0.34)
    readonly property color primaryText: isLightTheme ? "#1d1d1f" : "#ffffff"
    readonly property color secondaryText: isLightTheme
        ? Qt.rgba(0.11, 0.11, 0.12, 0.80)
        : Qt.rgba(0.95, 0.96, 0.99, 0.86)
    readonly property color metaText: isLightTheme
        ? Qt.rgba(0.11, 0.11, 0.12, 0.52)
        : Qt.rgba(1.0, 1.0, 1.0, 0.54)
    readonly property color iconPlateBg: isLightTheme
        ? Qt.rgba(0.0, 0.0, 0.0, 0.05)
        : Qt.rgba(1.0, 1.0, 1.0, 0.08)

    Layout.preferredWidth: hasUnread ? 24 : 0
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth
    Layout.fillHeight: true

    function stripHtml(raw) {
        if (!raw) {
            return "";
        }
        return String(raw)
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/<[^>]+>/g, "")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .trim();
    }

    function relativeTime(dt) {
        if (!dt) {
            return "şimdi";
        }
        const diffSec = Math.max(0, Math.floor((Date.now() - dt.getTime()) / 1000));
        if (diffSec < 60) {
            return "şimdi";
        }
        const mins = Math.floor(diffSec / 60);
        if (mins < 60) {
            return mins + " dk";
        }
        const hrs = Math.floor(mins / 60);
        return hrs + " sa";
    }

    NotificationManager.Notifications {
        id: popupModel
        showExpired: false
        showDismissed: false
        showNotifications: true
        showJobs: true
        limit: 4
        sortMode: NotificationManager.Notifications.SortByTypeAndUrgency
        sortOrder: Qt.DescendingOrder
        urgencies: NotificationManager.Notifications.LowUrgency
            | NotificationManager.Notifications.NormalUrgency
            | NotificationManager.Notifications.CriticalUrgency
    }

    NotificationManager.Notifications {
        id: historyModel
        showExpired: true
        showDismissed: false
        showNotifications: true
        showJobs: true
        limit: 20
        sortMode: NotificationManager.Notifications.SortByTypeAndUrgency
        sortOrder: Qt.DescendingOrder
        urgencies: NotificationManager.Notifications.LowUrgency
            | NotificationManager.Notifications.NormalUrgency
            | NotificationManager.Notifications.CriticalUrgency
    }

    // Subtle top-bar bell badge (only visible when history has items; click toggles macOS Notification Center sheet)
    property bool centerOpen: false

    Item {
        visible: root.hasUnread
        anchors.fill: parent

        Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 20
            radius: 4
            color: bellMouse.containsMouse || root.centerOpen ? Qt.rgba(1, 1, 1, 0.16) : "transparent"

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: "notifications-symbolic"
                color: "#ffffff"
                isMask: true
            }

            Rectangle {
                visible: historyModel.count > 0
                width: 6
                height: 6
                radius: 3
                color: "#ff453a"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 2
                anchors.rightMargin: 2
            }

            MouseArea {
                id: bellMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.centerOpen = !root.centerOpen
            }
        }
    }

    // === LIVE macOS SONOMA FLOATING NOTIFICATION BANNERS (Top-Right LayerShell) ===
    Window {
        id: bannerWindow
        visible: popupModel.count > 0 && !root.centerOpen
        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint

        width: 376
        height: Math.max(10, bannerCol.implicitHeight + 22)

        LayerShell.Window.layer: LayerShell.Window.LayerTop
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
        LayerShell.Window.margins.top: 6
        LayerShell.Window.margins.right: 8
        LayerShell.Window.exclusionZone: 0
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
        LayerShell.Window.scope: "macos-notifications"

        Column {
            id: bannerCol
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 8
            anchors.rightMargin: 8
            width: 356
            spacing: 10

            Repeater {
                model: popupModel

                delegate: Item {
                    id: bannerItem
                    required property int index
                    required property var model

                    readonly property string appName: model.applicationName || "Bildirim"
                    readonly property string summaryText: model.summary || appName
                    readonly property string bodyText: root.stripHtml(model.body || "")
                    readonly property var iconSrc: model.image || model.iconName || model.applicationIconName || "dialog-information"
                    readonly property var actionNamesList: model.actionNames || []
                    readonly property var actionLabelsList: model.actionLabels || []
                    readonly property bool isCritical: model.urgency === NotificationManager.Notifications.CriticalUrgency
                    readonly property int effectiveTimeout: {
                        if (isCritical) {
                            return 0;
                        }
                        const t = Number(model.timeout || 0);
                        return t > 0 ? Math.max(2500, Math.min(t, 12000)) : 5500;
                    }

                    width: bannerCol.width
                    height: cardRect.implicitHeight

                    property real slideOffset: 38
                    property real fadeVal: 0.0

                    Component.onCompleted: {
                        slideOffset = 0;
                        fadeVal = 1.0;
                    }

                    Behavior on slideOffset {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on fadeVal {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    Timer {
                        id: expireTimer
                        interval: bannerItem.effectiveTimeout > 0 ? bannerItem.effectiveTimeout : 5500
                        running: bannerItem.effectiveTimeout > 0 && !cardHover.hovered
                        repeat: false
                        onTriggered: {
                            if (bannerItem.index >= 0 && bannerItem.index < popupModel.count) {
                                popupModel.expire(popupModel.index(bannerItem.index, 0));
                            }
                        }
                    }

                    HoverHandler {
                        id: cardHover
                    }

                    // Soft ambient elevation shadow
                    Rectangle {
                        anchors.fill: cardRect
                        anchors.margins: -1
                        anchors.topMargin: 2
                        radius: cardRect.radius + 1
                        color: root.isLightTheme ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.36)
                        x: bannerItem.slideOffset
                        opacity: bannerItem.fadeVal
                    }

                    // Main macOS Sonoma Frosted-Glass Pill
                    Rectangle {
                        id: cardRect
                        x: bannerItem.slideOffset
                        opacity: bannerItem.fadeVal
                        width: parent.width
                        implicitHeight: Math.max(68, contentCol.implicitHeight + 24)
                        height: implicitHeight
                        radius: 18
                        color: root.cardBg
                        border.width: 1
                        border.color: bannerItem.isCritical
                            ? Qt.rgba(1.0, 0.27, 0.23, 0.72)
                            : (cardHover.hovered ? root.cardBorderHover : root.cardBorder)

                        // Subtle macOS top specular edge
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 1
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            height: 1
                            color: root.isLightTheme ? Qt.rgba(1, 1, 1, 0.65) : Qt.rgba(1, 1, 1, 0.16)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const idx = popupModel.index(bannerItem.index, 0);
                                if (bannerItem.model.hasDefaultAction) {
                                    popupModel.invokeDefaultAction(idx);
                                } else {
                                    popupModel.expire(idx);
                                }
                            }
                        }

                        RowLayout {
                            id: contentRow
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            spacing: 12

                            // Left: macOS Rounded App Icon
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignVCenter
                                radius: 10
                                color: root.iconPlateBg

                                Kirigami.Icon {
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    source: bannerItem.iconSrc
                                    roundToIconSize: false
                                    smooth: true
                                }
                            }

                            // Center: Title, Timestamp, Body, Action Pills
                            ColumnLayout {
                                id: contentCol
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: bannerItem.summaryText
                                        color: root.primaryText
                                        font.family: "Inter"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        text: bannerItem.appName !== bannerItem.summaryText
                                            ? bannerItem.appName + " · " + root.relativeTime(bannerItem.model.created)
                                            : root.relativeTime(bannerItem.model.created)
                                        color: root.metaText
                                        font.family: "Inter"
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    visible: bannerItem.bodyText.length > 0
                                    Layout.fillWidth: true
                                    text: bannerItem.bodyText
                                    color: root.secondaryText
                                    font.family: "Inter"
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 3
                                    lineHeight: 1.22
                                }

                                // Optional macOS action pill buttons
                                Row {
                                    visible: bannerItem.actionLabelsList.length > 0
                                    Layout.topMargin: 5
                                    spacing: 6

                                    Repeater {
                                        model: Math.min(bannerItem.actionLabelsList.length, 3)
                                        delegate: Rectangle {
                                            id: actBtn
                                            required property int index
                                            height: 24
                                            width: actLbl.implicitWidth + 18
                                            radius: 8
                                            color: root.isLightTheme
                                                ? (actMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                                                : (actMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.14))

                                            Text {
                                                id: actLbl
                                                anchors.centerIn: parent
                                                text: String(bannerItem.actionLabelsList[actBtn.index] || "")
                                                color: root.primaryText
                                                font.family: "Inter"
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                            }

                                            MouseArea {
                                                id: actMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const actionId = String(bannerItem.actionNamesList[actBtn.index] || "");
                                                    if (actionId.length > 0) {
                                                        popupModel.invokeAction(popupModel.index(bannerItem.index, 0), actionId);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // macOS Hover Close Pill (Top-Left corner, appears smoothly on hover)
                        Rectangle {
                            id: closePill
                            x: -6
                            y: -6
                            width: 20
                            height: 20
                            radius: 10
                            color: root.isLightTheme
                                ? (closeMouse.containsMouse ? Qt.rgba(0.84, 0.85, 0.88, 0.98) : Qt.rgba(0.92, 0.93, 0.95, 0.96))
                                : (closeMouse.containsMouse ? Qt.rgba(0.32, 0.34, 0.40, 0.96) : Qt.rgba(0.20, 0.22, 0.27, 0.94))
                            border.width: 1
                            border.color: root.cardBorderHover
                            opacity: cardHover.hovered || closeMouse.containsMouse ? 1.0 : 0.0
                            visible: opacity > 0.01

                            Behavior on opacity {
                                NumberAnimation { duration: 130 }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: root.primaryText
                                font.family: "Inter"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (bannerItem.index >= 0 && bannerItem.index < popupModel.count) {
                                        popupModel.close(popupModel.index(bannerItem.index, 0));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // === macOS NOTIFICATION CENTER DRAWER (Click top-bar bell to inspect/clear history) ===
    Window {
        id: centerWindow
        visible: root.centerOpen
        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint

        width: 376
        height: Math.min(620, Math.max(150, headerRow.implicitHeight + histListCol.implicitHeight + 56))

        LayerShell.Window.layer: LayerShell.Window.LayerTop
        LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
        LayerShell.Window.margins.top: 6
        LayerShell.Window.margins.right: 8
        LayerShell.Window.exclusionZone: 0
        LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
        LayerShell.Window.scope: "macos-notification-center"

        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            radius: 20
            color: root.isLightTheme
                ? Qt.rgba(0.95, 0.96, 0.98, 0.92)
                : Qt.rgba(0.12, 0.13, 0.17, 0.90)
            border.width: 1
            border.color: root.cardBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    id: headerRow
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "Bildirim Merkezi"
                        color: root.primaryText
                        font.family: "Inter"
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Rectangle {
                        height: 22
                        width: clearLbl.implicitWidth + 16
                        radius: 11
                        color: root.isLightTheme
                            ? (clearMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                            : (clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))
                        Text {
                            id: clearLbl
                            anchors.centerIn: parent
                            text: "Temizle"
                            color: root.primaryText
                            font.family: "Inter"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                historyModel.clear(NotificationManager.Notifications.ClearExpired);
                                root.centerOpen = false;
                            }
                        }
                    }
                    Rectangle {
                        height: 22
                        width: 22
                        radius: 11
                        color: root.isLightTheme
                            ? (closeCenterMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                            : (closeCenterMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12))
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: root.primaryText
                            font.pixelSize: 13
                            font.bold: true
                        }
                        MouseArea {
                            id: closeCenterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.centerOpen = false
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: histListCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: histListCol
                        width: parent.width
                        spacing: 8

                        Text {
                            visible: historyModel.count === 0
                            width: parent.width
                            topPadding: 20
                            bottomPadding: 20
                            horizontalAlignment: Text.AlignHCenter
                            text: "Yeni bildirim yok"
                            color: root.metaText
                            font.family: "Inter"
                            font.pixelSize: 12
                        }

                        Repeater {
                            model: historyModel
                            delegate: Rectangle {
                                id: histCard
                                required property int index
                                required property var model
                                width: histListCol.width
                                height: histRow.implicitHeight + 18
                                radius: 14
                                color: root.isLightTheme ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: root.isLightTheme ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.10)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (histCard.index >= 0 && histCard.index < historyModel.count) {
                                            historyModel.close(historyModel.index(histCard.index, 0));
                                        }
                                    }
                                }

                                RowLayout {
                                    id: histRow
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 10

                                    Kirigami.Icon {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        source: histCard.model.iconName || histCard.model.applicationIconName || "dialog-information"
                                        roundToIconSize: false
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                Layout.fillWidth: true
                                                text: histCard.model.summary || histCard.model.applicationName || "Bildirim"
                                                color: root.primaryText
                                                font.family: "Inter"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: root.relativeTime(histCard.model.created)
                                                color: root.metaText
                                                font.family: "Inter"
                                                font.pixelSize: 10
                                            }
                                        }
                                        Text {
                                            visible: root.stripHtml(histCard.model.body || "").length > 0
                                            Layout.fillWidth: true
                                            text: root.stripHtml(histCard.model.body || "")
                                            color: root.secondaryText
                                            font.family: "Inter"
                                            font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
