pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    property bool showOnOverlay: true
    minWidth: 160
    minHeight: 48
    property real defaultWidth: 380
    property real defaultHeight: 180

    readonly property bool inheritTheme: pluginData?.inheritTheme ?? false
    readonly property color islandBackgroundColor: inheritTheme ? Theme.surfaceContainerHigh : (pluginData?.backgroundColor || "#0b0b0b")
    readonly property color islandTextColor: inheritTheme ? Theme.surfaceText : (pluginData?.foregroundColor || "#f5f5f5")
    readonly property int compactBarCount: pluginData?.compactBarCount ?? 8
    readonly property int extendedBarCount: pluginData?.extendedBarCount ?? 16
    readonly property real barThickness: 48

    Component.onCompleted: ensureOverlay()
    onInstanceDataChanged: ensureOverlay()

    function ensureOverlay() {
        if (root.isInstance && root.instanceId && root.instanceData?.config?.showOnOverlay !== true) {
            SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, {
                showOnOverlay: true
            });
        }
    }

    DynamicIslandService {
        id: islandService
    }

    readonly property bool isMediaPlaying: islandService.isConnected ? islandService.isPlaying : (MprisController.activePlayer && MprisController.activePlayer.playbackState === 1)

    Loader {
        id: contentLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        source: root.isMediaPlaying ? Qt.resolvedUrl("DynamicIslandMedia.qml") : Qt.resolvedUrl("DynamicIslandClock.qml")

        onLoaded: {
            if (!item)
                return;
            item.islandBackgroundColor = Qt.binding(() => root.islandBackgroundColor);
            item.islandTextColor = Qt.binding(() => root.islandTextColor);
            item.barThickness = root.barThickness;
            if ("compactBarCount" in item)
                item.compactBarCount = Qt.binding(() => root.compactBarCount);
            if ("extendedBarCount" in item)
                item.extendedBarCount = Qt.binding(() => root.extendedBarCount);
            if ("parentWidgetWidth" in item)
                item.parentWidgetWidth = Qt.binding(() => root.widgetWidth);
            if ("parentWidgetHeight" in item)
                item.parentWidgetHeight = Qt.binding(() => root.widgetHeight);
            if ("islandService" in item)
                item.islandService = islandService;
        }
    }
}
