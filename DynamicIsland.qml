import QtQuick
import qs.Services
import qs.Modules.Plugins

pragma ComponentBehavior: Bound

PluginComponent {
    id: root

    readonly property color islandBackgroundColor: "#0b0b0b"
    readonly property color islandTextColor: "#f5f5f5"

    BasePill {
        id: islandPill
        enableCursor: false
        enableBackgroundHover: false
        barConfig: ({ noBackground: true, widgetOutlineEnabled: false })

        content: Component {
            Item {
                id: contentRoot

                implicitWidth: contentLoader.implicitWidth
                implicitHeight: contentLoader.implicitHeight

                Loader {
                    id: contentLoader
                    anchors.centerIn: parent
                    source: MprisController.activePlayer && MprisController.activePlayer.playbackState === 1
                        ? Qt.resolvedUrl("DynamicIslandMedia.qml")
                        : Qt.resolvedUrl("DynamicIslandClock.qml")
                    onLoaded: {
                        if (!item)
                            return;
                        item.islandBackgroundColor = root.islandBackgroundColor;
                        item.islandTextColor = root.islandTextColor;
                        item.barThickness = islandPill.barThickness;
                    }
                }
            }
        }
    }
}
