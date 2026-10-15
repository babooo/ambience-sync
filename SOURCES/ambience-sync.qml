import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

Page {
    id: page

    readonly property var styleDescriptions: [
        qsTr("Default style that uses a balanced color range"),
        qsTr("More saturated and colorful version of default style"),
        qsTr("No background tint so colors stand out")
    ]

    // Values are stored in dconf; the root service reads them from there.
    ConfigurationValue {
        id: enabledConf
        key: "/desktop/ambience-sync/enabled"
        defaultValue: false
    }

    ConfigurationValue {
        id: monochromeConf
        key: "/desktop/ambience-sync/monochrome"
        defaultValue: false
    }

    // Stored as an index. The order of the MenuItems below must match the
    // index-to-name mapping in apply.sh.
    ConfigurationValue {
        id: styleConf
        key: "/desktop/ambience-sync/style_index"
        defaultValue: 0
    }

    ConfigurationValue {
        id: followConf
        key: "/desktop/ambience-sync/follow_dark_mode"
        defaultValue: false
    }

    // Set to true to ask the root service to remove the package
    ConfigurationValue {
        id: uninstallConf
        key: "/desktop/ambience-sync/uninstall"
        defaultValue: false
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Uninstall")
                onClicked: Remorse.popupAction(
                    page,
                    qsTr("Uninstalling Ambience Sync"),
                    function() {
                        uninstallConf.value = true
                        pageStack.pop()
                    })
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Android theme")
            }

            SectionHeader { text: qsTr("Colors") }

            TextSwitch {
                text: qsTr("Sync ambience color")
                description: qsTr("Use the highlight color of the current ambience as the Android system's primary color. Turn this and Monochrome off to restore the default Android colors.")
                automaticCheck: false
                // faded out and locked while Monochrome is on
                enabled: !monochromeConf.value
                checked: enabledConf.value
                onClicked: enabledConf.value = !enabledConf.value
            }

            ComboBox {
                width: parent.width
                label: qsTr("Theme style")
                description: page.styleDescriptions[Math.max(currentIndex, 0)]
                enabled: enabledConf.value
                // an old stored index (fallback)
                currentIndex: styleConf.value < 3 ? styleConf.value : 0

                menu: ContextMenu {
                    MenuItem { text: qsTr("Tonal Spot") }
                    MenuItem { text: qsTr("Vibrant") }
                    MenuItem { text: qsTr("Rainbow") }
                }

                onCurrentIndexChanged: styleConf.value = currentIndex
            }

            TextSwitch {
                text: qsTr("Monochrome")
                description: qsTr("Give Android a grayscale palette without any color. This can't be combined with Sync ambience color.")
                automaticCheck: false
                // faded out and locked while Sync ambience color is on
                enabled: !enabledConf.value
                checked: monochromeConf.value
                onClicked: monochromeConf.value = !monochromeConf.value
            }

            SectionHeader { text: qsTr("Dark/light theme") }

            TextSwitch {
    text: qsTr("Follow ambience style (Dark/Light)")
    description: qsTr("Switch Android between its dark and light theme to match the Style of the current ambience.")
    automaticCheck: false
    checked: followConf.value
    onClicked: followConf.value = !followConf.value
}
        }

        VerticalScrollDecorator {}
    }
}
