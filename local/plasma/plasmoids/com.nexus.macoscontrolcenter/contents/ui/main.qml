pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    Layout.preferredWidth: 26
    Layout.minimumWidth: 26
    Layout.maximumWidth: 26
    Layout.fillHeight: true

    TaskManager.TasksModel {
        id: ccLauncher
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        launcherList: ["applications:nexus-plasma-settings.desktop"]
    }

    Rectangle {
        id: pillBg
        anchors.centerIn: parent
        width: 24
        height: 20
        radius: 4
        color: ccMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"

        // Iconic macOS two-toggle Control Center glyph
        Column {
            anchors.centerIn: parent
            spacing: 2.5

            Rectangle {
                width: 14
                height: 6
                radius: 3
                color: "transparent"
                border.width: 1.2
                border.color: "#ffffff"

                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 1.2
                    color: "#ffffff"
                }
            }

            Rectangle {
                width: 14
                height: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.88)

                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 1.2
                    color: "#1c1c1e"
                }
            }
        }
    }

    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: qsTr("Control Center")
        subText: qsTr("Open NEXUS-Plasma Settings (Meta+I)")

        MouseArea {
            id: ccMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (ccLauncher.count > 0) {
                    ccLauncher.requestActivate(ccLauncher.makeModelIndex(0, -1));
                }
            }
        }
    }
}
