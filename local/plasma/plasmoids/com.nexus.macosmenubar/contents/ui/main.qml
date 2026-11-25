pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    property string activeAppName: "Finder"
    property bool hasActiveWindow: false

    Layout.preferredWidth: menuRow.implicitWidth + 6
    Layout.minimumWidth: menuRow.implicitWidth + 6
    Layout.maximumWidth: menuRow.implicitWidth + 6
    Layout.fillHeight: true

    function refreshActiveApp() {
        var found = false;
        var name = "Finder";
        for (var i = 0; i < windowModel.count; i++) {
            var idx = windowModel.makeModelIndex(i, -1);
            var isAct = Boolean(windowModel.data(idx, TaskManager.AbstractTasksModel.IsActive));
            var isWin = Boolean(windowModel.data(idx, TaskManager.AbstractTasksModel.IsWindow));
            if (isWin && isAct) {
                var app = windowModel.data(idx, TaskManager.AbstractTasksModel.AppName);
                var disp = windowModel.data(idx, TaskManager.AbstractTasksModel.display);
                var raw = (app && String(app).trim().length > 0) ? String(app).trim() : String(disp || "Finder").trim();
                if (raw.toLowerCase() === "dolphin") {
                    name = "Finder";
                } else {
                    name = raw;
                }
                found = true;
                break;
            }
        }
        root.hasActiveWindow = found;
        root.activeAppName = name;
    }

    function launchApp(idx) {
        if (idx >= 0 && idx < quickLauncherModel.count) {
            quickLauncherModel.requestNewInstance(quickLauncherModel.makeModelIndex(idx, -1));
        }
    }

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManager.TasksModel {
        id: windowModel
        virtualDesktop: virtualDesktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        launcherList: []

        onCountChanged: root.refreshActiveApp()
        onDataChanged: root.refreshActiveApp()
        onRowsInserted: root.refreshActiveApp()
        onRowsRemoved: root.refreshActiveApp()
        onModelReset: root.refreshActiveApp()
    }

    TaskManager.TasksModel {
        id: quickLauncherModel
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        launcherList: [
            "applications:org.kde.dolphin.desktop",
            "applications:org.kde.konsole.desktop",
            "applications:systemsettings.desktop",
            "applications:nexus-plasma-settings.desktop"
        ]
    }

    Component.onCompleted: refreshActiveApp()

    PlasmaComponents3.Menu {
        id: fileMenu
        PlasmaComponents3.MenuItem {
            text: qsTr("New Finder Window")
            icon.name: "folder-open"
            onTriggered: root.launchApp(0)
        }
        PlasmaComponents3.MenuItem {
            text: qsTr("New Terminal")
            icon.name: "utilities-terminal"
            onTriggered: root.launchApp(1)
        }
        PlasmaComponents3.MenuSeparator {}
        PlasmaComponents3.MenuItem {
            text: qsTr("NEXUS-Plasma Settings...")
            icon.name: "preferences-desktop-color"
            onTriggered: root.launchApp(3)
        }
    }

    PlasmaComponents3.Menu {
        id: goMenu
        PlasmaComponents3.MenuItem {
            text: qsTr("Home")
            icon.name: "user-home"
            onTriggered: Qt.openUrlExternally("file://__HOME__")
        }
        PlasmaComponents3.MenuItem {
            text: qsTr("Downloads")
            icon.name: "folder-downloads"
            onTriggered: Qt.openUrlExternally("file://__HOME__/Downloads")
        }
        PlasmaComponents3.MenuItem {
            text: qsTr("Pictures")
            icon.name: "folder-pictures"
            onTriggered: Qt.openUrlExternally("file://__HOME__/Pictures")
        }
        PlasmaComponents3.MenuSeparator {}
        PlasmaComponents3.MenuItem {
            text: qsTr("Trash")
            icon.name: "user-trash"
            onTriggered: Qt.openUrlExternally("trash:/")
        }
    }

    PlasmaComponents3.Menu {
        id: settingsMenu
        PlasmaComponents3.MenuItem {
            text: qsTr("NEXUS-Plasma Control Center")
            icon.name: "preferences-desktop-color"
            onTriggered: root.launchApp(3)
        }
        PlasmaComponents3.MenuItem {
            text: qsTr("System Settings")
            icon.name: "preferences-system"
            onTriggered: root.launchApp(2)
        }
    }

    Row {
        id: menuRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 2
        spacing: 2

        // Bold active application name (Finder when on desktop)
        Rectangle {
            id: appNameBtn
            height: 22
            width: appLabel.implicitWidth + 14
            radius: 4
            color: appMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"

            Text {
                id: appLabel
                anchors.centerIn: parent
                text: root.activeAppName
                color: "#ffffff"
                font.family: "Inter"
                font.pixelSize: 13
                font.bold: true
            }

            MouseArea {
                id: appMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: settingsMenu.popup(appNameBtn, 0, appNameBtn.height + 2)
            }
        }

        // Desktop Finder fallback menus (shown cleanly when no app window owns Global Menu)
        Repeater {
            model: root.hasActiveWindow ? [] : [
                { label: "File", menu: "file" },
                { label: "Edit", menu: "settings" },
                { label: "View", menu: "go" },
                { label: "Go", menu: "go" },
                { label: "Window", menu: "settings" },
                { label: "Help", menu: "settings" }
            ]

            delegate: Rectangle {
                id: itemBtn
                required property var modelData
                height: 22
                width: itemLbl.implicitWidth + 14
                radius: 4
                color: itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                Text {
                    id: itemLbl
                    anchors.centerIn: parent
                    text: itemBtn.modelData.label
                    color: Qt.rgba(1, 1, 1, 0.94)
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (itemBtn.modelData.menu === "file") {
                            fileMenu.popup(itemBtn, 0, itemBtn.height + 2);
                        } else if (itemBtn.modelData.menu === "go") {
                            goMenu.popup(itemBtn, 0, itemBtn.height + 2);
                        } else {
                            settingsMenu.popup(itemBtn, 0, itemBtn.height + 2);
                        }
                    }
                }
            }
        }
    }
}
