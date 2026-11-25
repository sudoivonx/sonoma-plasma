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

    readonly property int baseIconSize: Plasmoid.configuration.iconSize
    readonly property int iconSpacing: Plasmoid.configuration.iconSpacing
    readonly property bool magEnabled: Plasmoid.configuration.magnificationEnabled
    readonly property real magScale: Plasmoid.configuration.magnificationScale
    readonly property int magRadius: Plasmoid.configuration.magnificationRadius
    readonly property bool showTrash: Plasmoid.configuration.showTrash
    readonly property bool showTooltips: Plasmoid.configuration.showTooltips

    readonly property real rawMaxSize: Math.max(baseIconSize, Math.round(baseIconSize * magScale))
    readonly property int panelHeadroomCap: root.height > 0
        ? Math.max(64, Math.floor(root.height + 22))
        : rawMaxSize
    readonly property real effectiveBaseSize: Math.min(baseIconSize, panelHeadroomCap)
    readonly property real effectiveMaxSize: Math.min(
        Math.max(effectiveBaseSize, Math.round(effectiveBaseSize * magScale)),
        panelHeadroomCap
    )

    readonly property real restSlotWidth: effectiveBaseSize + 4
    readonly property int visibleSlotCount: tasksModel.count + (showTrash ? 2 : 0)
    readonly property real restTotalWidth: tasksModel.count * restSlotWidth
        + (showTrash ? dividerSlot.width + restSlotWidth : 0)
        + Math.max(0, visibleSlotCount - 1) * iconSpacing

    property bool dockIsHovered: false
    property real hoverCenterOffset: -10000

    Layout.preferredWidth: dockRow.implicitWidth + 8
    Layout.minimumWidth: Layout.preferredWidth
    Layout.maximumWidth: Layout.preferredWidth
    Layout.minimumHeight: 40
    Layout.fillHeight: true

    function computeTargetSize(restCenterX, cursorCenterOffset, hovered) {
        if (!magEnabled || !hovered || magRadius <= 0) {
            return effectiveBaseSize;
        }
        const restCenterOffset = restCenterX - restTotalWidth * 0.5;
        const dist = Math.abs(cursorCenterOffset - restCenterOffset);
        if (dist >= magRadius) {
            return effectiveBaseSize;
        }
        const t = dist / magRadius;
        const factor = 0.5 * (1.0 + Math.cos(Math.PI * t));
        return effectiveBaseSize + (effectiveMaxSize - effectiveBaseSize) * factor;
    }

    function updateHoverFromItem(item, localX, localY) {
        if (!item) {
            return;
        }
        const pt = item.mapToItem(dockRow, localX, localY);
        root.hoverCenterOffset = pt.x - dockRow.width * 0.5;
        root.dockIsHovered = true;
        hoverLeaveTimer.stop();
    }

    function syncItemGeometry(rowIdx, item) {
        if (!item || !item.visible || rowIdx < 0) {
            return;
        }
        const topLeft = item.mapToGlobal(0, 0);
        tasksModel.requestPublishDelegateGeometry(
            tasksModel.makeModelIndex(rowIdx, -1),
            Qt.rect(Math.round(topLeft.x), Math.round(topLeft.y), Math.round(item.width), Math.round(item.height)),
            item
        );
    }

    Timer {
        id: hoverLeaveTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (!dockHover.hovered) {
                root.dockIsHovered = false;
            }
        }
    }

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManager.TasksModel {
        id: tasksModel

        virtualDesktop: virtualDesktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByCurrentVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: false
        filterByActivity: true
        sortMode: TaskManager.TasksModel.SortManual
        groupMode: Plasmoid.configuration.groupingStrategy === 0
            ? TaskManager.TasksModel.GroupDisabled
            : TaskManager.TasksModel.GroupApplications
        separateLaunchers: false
        launchInPlace: true
        hideActivatedLaunchers: true
        launcherList: Plasmoid.configuration.launchers

        onLauncherListChanged: {
            if (JSON.stringify(Plasmoid.configuration.launchers) !== JSON.stringify(launcherList)) {
                Plasmoid.configuration.launchers = launcherList;
            }
        }
    }

    property int contextRow: -1
    property bool contextIsWindow: false
    property bool contextIsMinimized: false
    property bool contextHasLauncher: false
    property string contextLauncherUrl: ""
    property string contextAppName: ""

    PlasmaComponents3.Menu {
        id: contextMenu

        PlasmaComponents3.MenuItem {
            text: root.contextAppName
            enabled: false
        }

        PlasmaComponents3.MenuSeparator {}

        PlasmaComponents3.MenuItem {
            text: qsTr("New Window")
            icon.name: "window-new"
            onTriggered: {
                if (root.contextRow >= 0) {
                    tasksModel.requestNewInstance(tasksModel.makeModelIndex(root.contextRow, -1));
                }
            }
        }

        PlasmaComponents3.MenuItem {
            visible: root.contextIsWindow
            text: root.contextIsMinimized ? qsTr("Restore") : qsTr("Minimize")
            icon.name: root.contextIsMinimized ? "window-restore" : "window-minimize"
            onTriggered: {
                if (root.contextRow >= 0) {
                    tasksModel.requestToggleMinimized(tasksModel.makeModelIndex(root.contextRow, -1));
                }
            }
        }

        PlasmaComponents3.MenuItem {
            visible: root.contextLauncherUrl.length > 0
            text: root.contextHasLauncher ? qsTr("Remove from Dock") : qsTr("Keep in Dock")
            icon.name: root.contextHasLauncher ? "pin" : "window-pin"
            onTriggered: {
                if (root.contextHasLauncher) {
                    tasksModel.requestRemoveLauncher(root.contextLauncherUrl);
                } else {
                    tasksModel.requestAddLauncher(root.contextLauncherUrl);
                }
            }
        }

        PlasmaComponents3.MenuSeparator {
            visible: root.contextIsWindow
        }

        PlasmaComponents3.MenuItem {
            visible: root.contextIsWindow
            text: qsTr("Close")
            icon.name: "window-close"
            onTriggered: {
                if (root.contextRow >= 0) {
                    tasksModel.requestClose(tasksModel.makeModelIndex(root.contextRow, -1));
                }
            }
        }
    }

    Item {
        id: dockHoverArea
        anchors.left: dockRow.left
        anchors.right: dockRow.right
        anchors.bottom: dockRow.bottom
        height: Math.max(
            dockRow.height,
            (root.dockIsHovered ? root.effectiveMaxSize : root.effectiveBaseSize) + 10
        )
        z: -1

        HoverHandler {
            id: dockHover
            onHoveredChanged: {
                if (hovered) {
                    hoverLeaveTimer.stop();
                    root.hoverCenterOffset = point.position.x - dockHoverArea.width * 0.5;
                    root.dockIsHovered = true;
                } else {
                    hoverLeaveTimer.restart();
                }
            }
            onPointChanged: {
                if (hovered) {
                    root.hoverCenterOffset = point.position.x - dockHoverArea.width * 0.5;
                    root.dockIsHovered = true;
                }
            }
        }
    }

    Row {
        id: dockRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -5
        height: parent.height
        spacing: root.iconSpacing

        Repeater {
            id: taskRepeater
            model: tasksModel

            delegate: DockItem {
                id: taskDelegate
                required property int index
                required property var model

                readonly property real restCenterX: index * (root.restSlotWidth + root.iconSpacing) + root.restSlotWidth * 0.5

                itemIndex: index
                baseSize: root.effectiveBaseSize
                targetSize: root.computeTargetSize(restCenterX, root.hoverCenterOffset, root.dockIsHovered)
                titleText: model.AppName || model.display || ""
                iconSource: model.decoration
                isWindow: Boolean(model.IsWindow)
                isLauncher: Boolean(model.IsLauncher)
                hasLauncher: Boolean(model.HasLauncher)
                isActive: Boolean(model.IsActive)
                isMinimized: Boolean(model.IsMinimized)
                isGroupParent: Boolean(model.IsGroupParent)
                childCount: model.ChildCount ? Number(model.ChildCount) : 0
                isDemandingAttention: Boolean(model.IsDemandingAttention)
                isTrash: false
                showTooltip: root.showTooltips

                onGeometrySyncRequested: root.syncItemGeometry(index, taskDelegate)
                onHoverMoved: function(lx, ly) {
                    root.updateHoverFromItem(taskDelegate, lx, ly);
                }
                onHoverLeft: hoverLeaveTimer.restart()

                onActivated: function(button) {
                    const idx = tasksModel.makeModelIndex(index, -1);
                    if (button === Qt.LeftButton) {
                        if (isLauncher) {
                            tasksModel.requestActivate(idx);
                        } else if (isActive && !isMinimized && !(isGroupParent && childCount > 1)) {
                            tasksModel.requestToggleMinimized(idx);
                        } else {
                            tasksModel.requestActivate(idx);
                        }
                    } else if (button === Qt.MiddleButton) {
                        tasksModel.requestNewInstance(idx);
                    } else if (button === Qt.RightButton) {
                        root.contextRow = index;
                        root.contextIsWindow = isWindow;
                        root.contextIsMinimized = isMinimized;
                        root.contextHasLauncher = hasLauncher;
                        root.contextLauncherUrl = model.LauncherUrlWithoutIcon ? String(model.LauncherUrlWithoutIcon) : "";
                        root.contextAppName = titleText;
                        contextMenu.popup(taskDelegate, taskDelegate.width * 0.5, 0);
                    }
                }
            }
        }

        Item {
            id: dividerSlot
            visible: root.showTrash
            width: 10
            height: parent.height

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                width: 1
                height: Math.round(root.effectiveBaseSize * 0.76)
                color: Qt.rgba(1, 1, 1, 0.30)
            }
        }

        DockItem {
            id: trashDelegate
            visible: root.showTrash

            readonly property real restCenterX: tasksModel.count * (root.restSlotWidth + root.iconSpacing)
                + (dividerSlot.width + root.iconSpacing)
                + root.restSlotWidth * 0.5

            itemIndex: tasksModel.count
            baseSize: root.effectiveBaseSize
            targetSize: root.computeTargetSize(restCenterX, root.hoverCenterOffset, root.dockIsHovered)
            titleText: qsTr("Trash")
            iconSource: "__HOME__/.local/share/icons/WhiteSur/places/scalable/user-trash-full.svg"
            isWindow: false
            isLauncher: true
            isTrash: true
            showTooltip: root.showTooltips

            onHoverMoved: function(lx, ly) {
                root.updateHoverFromItem(trashDelegate, lx, ly);
            }
            onHoverLeft: hoverLeaveTimer.restart()

            onActivated: function(button) {
                if (button === Qt.LeftButton || button === Qt.MiddleButton) {
                    Qt.openUrlExternally("trash:/");
                }
            }
        }
    }
}
