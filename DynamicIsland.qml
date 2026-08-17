import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

pragma ComponentBehavior: Bound

PluginComponent {
    id: root

    readonly property bool inheritTheme: pluginData?.inheritTheme ?? false
    readonly property color islandBackgroundColor: inheritTheme
        ? Theme.surfaceContainerHigh
        : (pluginData?.backgroundColor || "#0b0b0b")
    readonly property color islandTextColor: inheritTheme
        ? Theme.surfaceText
        : (pluginData?.foregroundColor || "#f5f5f5")
    readonly property int compactBarCount: pluginData?.compactBarCount ?? 15
    readonly property int extendedBarCount: pluginData?.extendedBarCount ?? 16

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
                        item.islandBackgroundColor = Qt.binding(() => root.islandBackgroundColor);
                        item.islandTextColor = Qt.binding(() => root.islandTextColor);
                        item.barThickness = islandPill.barThickness;
                        if ("compactBarCount" in item)
                            item.compactBarCount = Qt.binding(() => root.compactBarCount);
                        if ("extendedBarCount" in item)
                            item.extendedBarCount = Qt.binding(() => root.extendedBarCount);
                    }
                }
            }
        }
    }
}

