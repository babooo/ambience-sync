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

    ConfigurationValue {
        id: textConf
        key: "/desktop/ambience-sync/follow_text_size"
        defaultValue: false
    }

    // Set to true to ask the root service to remove the package
    ConfigurationValue {
        id: uninstallConf
        key: "/desktop/ambience-sync/uninstall"
        defaultValue: false
    }

    // The About page lives in this file so the package needs no extra files
    Component {
        id: aboutComponent

        Page {
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: aboutColumn.height + Theme.paddingLarge

                Column {
                    id: aboutColumn
                    width: parent.width
                    spacing: Theme.paddingLarge

                    PageHeader {
                        title: qsTr("About")
                    }

                    Repeater {
                        model: [
                            qsTr("ambience-sync is a simple add-on that keeps Android apps in step with your Sailfish ambience. It syncs Android's colors and dark/light mode with the current ambience, and can match Android's text size to Sailfish's."),
                            qsTr("A background service running as root waits for changes to the ambience or to the settings on this page and applies them to Android (AppSupport). A second small service starts together with AppSupport and applies your settings again, so nothing is missed while Android was off."),
                            qsTr("Turning an option off, or uninstalling, restores Android to how it was before. For the cleanest result, uninstall while AppSupport is running.")
                        ]

                        delegate: Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            wrapMode: Text.Wrap
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.highlightColor
                            text: modelData
                        }
                    }

                    DetailItem {
                        width: parent.width
                        label: qsTr("Version")
                        value: "1.0.0"
                    }

                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Open project page")
                        onClicked: Qt.openUrlExternally("https://github.com/babooo/ambience-sync")
                    }
                }

                VerticalScrollDecorator {}
            }
        }
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

            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(aboutComponent)
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

            SectionHeader { text: qsTr("Text size") }

            TextSwitch {
                text: qsTr("Match text size")
                description: qsTr("Set Android's font size to approximately-match the text size chosen in Sailfish's Display settings.")
                automaticCheck: false
                checked: textConf.value
                onClicked: textConf.value = !textConf.value
            }
        }

        VerticalScrollDecorator {}
    }
}
