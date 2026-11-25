import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

Item {
    id: itemRoot

    property int itemIndex: 0
    property real baseSize: 48
    property real targetSize: 48
    property real currentSize: targetSize
    property string titleText: ""
    property var iconSource: ""
    property bool isWindow: false
    property bool isLauncher: false
    property bool hasLauncher: false
    property bool isActive: false
    property bool isMinimized: false
    property bool isGroupParent: false
    property int childCount: 0
    property bool isDemandingAttention: false
    property bool isTrash: false
    property bool showTooltip: true

    signal activated(int button)
    signal hoverMoved(real localX, real localY)
    signal hoverLeft()
    signal geometrySyncRequested()

    Behavior on currentSize {
        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }
    }

    readonly property int slotPadding: 4
    readonly property int indicatorReserve: 6

    implicitWidth: Math.round(currentSize + slotPadding)
    implicitHeight: parent ? parent.height : Math.round(currentSize + indicatorReserve + 4)
    width: implicitWidth
    height: implicitHeight

    onXChanged: geometrySyncRequested()
    onYChanged: geometrySyncRequested()
    onWidthChanged: geometrySyncRequested()
    onHeightChanged: geometrySyncRequested()

    Item {
        id: iconBox
        width: Math.round(itemRoot.currentSize)
        height: Math.round(itemRoot.currentSize)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: indicatorDot.top
        anchors.bottomMargin: 2

        Kirigami.Icon {
            id: appIcon
            anchors.fill: parent
            source: itemRoot.iconSource
            roundToIconSize: false
            active: mouseArea.containsMouse
            smooth: true
            opacity: itemRoot.isMinimized ? 0.78 : 1.0
        }

        Rectangle {
            visible: itemRoot.isGroupParent && itemRoot.childCount > 1
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 0
            anchors.rightMargin: 0
            width: Math.max(16, countText.implicitWidth + 6)
            height: 16
            radius: 8
            color: Qt.rgba(0.95, 0.26, 0.21, 0.95)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.35)

            Text {
                id: countText
                anchors.centerIn: parent
                text: String(itemRoot.childCount)
                color: "#ffffff"
                font.pixelSize: 10
                font.bold: true
            }
        }
    }

    Rectangle {
        id: indicatorDot
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: 4
        height: 4
        radius: 2
        visible: itemRoot.isWindow && !itemRoot.isTrash
        color: {
            if (itemRoot.isDemandingAttention) {
                return "#fb923c";
            }
            if (itemRoot.isActive) {
                return "#ffffff";
            }
            return Qt.rgba(0.92, 0.95, 1.0, 0.80);
        }
    }

    PlasmaCore.ToolTipArea {
        id: toolTipArea
        x: 0
        y: Math.min(0, iconBox.y)
        width: itemRoot.width
        height: itemRoot.height - y
        location: PlasmaCore.Types.BottomEdge
        mainText: itemRoot.showTooltip ? itemRoot.titleText : ""
        subText: itemRoot.isGroupParent && itemRoot.childCount > 1
            ? qsTr("%1 open windows").arg(itemRoot.childCount)
            : ""
        active: itemRoot.showTooltip && itemRoot.titleText.length > 0

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                const pt = mouseArea.mapToItem(itemRoot, mouseX, mouseY);
                itemRoot.hoverMoved(pt.x, pt.y);
            }
            onPositionChanged: function(mouse) {
                const pt = mouseArea.mapToItem(itemRoot, mouse.x, mouse.y);
                itemRoot.hoverMoved(pt.x, pt.y);
            }
            onExited: itemRoot.hoverLeft()
            onClicked: function(mouse) {
                itemRoot.activated(mouse.button);
            }
        }
    }
}
