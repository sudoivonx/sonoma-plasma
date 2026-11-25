import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configRoot

    property alias cfg_iconSize: iconSizeSpin.value
    property alias cfg_magnificationEnabled: magEnabledCheck.checked
    property double cfg_magnificationScale: 1.45
    property alias cfg_magnificationRadius: magRadiusSpin.value
    property alias cfg_iconSpacing: iconSpacingSpin.value
    property alias cfg_showTrash: showTrashCheck.checked
    property alias cfg_showTooltips: showTooltipsCheck.checked
    property alias cfg_showOnlyCurrentDesktop: currentDesktopCheck.checked

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: magEnabledCheck
            Kirigami.FormData.label: qsTr("Hover magnification:")
            text: qsTr("Magnify icons on pointer hover")
        }

        QQC2.SpinBox {
            id: iconSizeSpin
            Kirigami.FormData.label: qsTr("Base icon size (px):")
            from: 24
            to: 48
            stepSize: 2
        }

        QQC2.SpinBox {
            id: magScalePercentSpin
            Kirigami.FormData.label: qsTr("Magnification (%):")
            from: 100
            to: 165
            stepSize: 5
            enabled: magEnabledCheck.checked
            value: Math.round(configRoot.cfg_magnificationScale * 100)
            onValueModified: {
                configRoot.cfg_magnificationScale = value / 100.0;
            }
        }

        QQC2.SpinBox {
            id: magRadiusSpin
            Kirigami.FormData.label: qsTr("Magnification radius (px):")
            from: 60
            to: 260
            stepSize: 5
            enabled: magEnabledCheck.checked
        }

        QQC2.SpinBox {
            id: iconSpacingSpin
            Kirigami.FormData.label: qsTr("Icon spacing (px):")
            from: 2
            to: 20
        }

        QQC2.CheckBox {
            id: showTrashCheck
            Kirigami.FormData.label: qsTr("Dock items:")
            text: qsTr("Show Trash in dock")
        }

        QQC2.CheckBox {
            id: showTooltipsCheck
            text: qsTr("Show hover labels")
        }

        QQC2.CheckBox {
            id: currentDesktopCheck
            text: qsTr("Show only tasks from current virtual desktop")
        }
    }
}
