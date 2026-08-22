pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Plugins
import "core"
import "core/IslandConfig.js" as IslandConfig

/**
 * Desktop surface: resolves configuration, owns the shared media pipeline and
 * switches between idle (clock) and media modes.
 *
 * Configuration resolution (core/IslandConfig.js): defaults <- global plugin
 * settings <- per-instance overrides. Desktop widget instances therefore
 * inherit changes made in Settings > Plugins > Dynamic Island, while instance
 * config keys still win.
 *
 * Injection contract for loaded mode components (ui/ClockIsland.qml,
 * ui/MediaIsland.qml):
 *   backgroundColor / foregroundColor / accentColor / onAccentColor
 *   requestResize / clearResize (desktop wrapper bridge)
 *   media (core.MediaState, media mode only)
 *   config (resolved island config, media mode only)
 */
DesktopPluginComponent {
    id: root

    property bool showOnOverlay: true
    minWidth: 160
    minHeight: 48
    property real defaultWidth: 380
    property real defaultHeight: 90

    // ---- configuration ----
    readonly property var islandConfig: IslandConfig.resolve(SettingsData.getPluginSettingsForPlugin(pluginId), instanceConfig)

    readonly property bool inheritTheme: islandConfig.inheritTheme
    readonly property color islandBackground: inheritTheme ? Theme.surfaceContainerHigh : islandConfig.backgroundColor
    readonly property color islandForeground: inheritTheme ? Theme.surfaceText : islandConfig.foregroundColor
    readonly property color islandAccent: inheritTheme ? Theme.primary : islandForeground
    readonly property color onIslandAccent: inheritTheme ? Theme.onPrimary : islandBackground

    // ---- media pipeline ----
    IslandService {
        id: islandService
        lyricsEnabled: root.islandConfig.enableLyrics
    }

    MediaState {
        id: mediaState
        service: islandService
    }

    readonly property bool mediaActive: mediaState.playing

    // ---- overlay visibility ----
    Component.onCompleted: ensureOverlay()
    onInstanceDataChanged: ensureOverlay()

    function ensureOverlay() {
        if (root.isInstance && root.instanceId && root.instanceData?.config?.showOnOverlay !== true) {
            SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, {
                showOnOverlay: true
            });
        }
    }

    // ---- mode switching ----
    Loader {
        id: contentLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        source: root.mediaActive ? "ui/MediaIsland.qml" : "ui/ClockIsland.qml"

        onLoaded: {
            if (!item)
                return;
            // Uniform optional injection: mode components declare only what they use.
            if ("backgroundColor" in item)
                item.backgroundColor = Qt.binding(() => root.islandBackground);
            if ("foregroundColor" in item)
                item.foregroundColor = Qt.binding(() => root.islandForeground);
            if ("accentColor" in item)
                item.accentColor = Qt.binding(() => root.islandAccent);
            if ("onAccentColor" in item)
                item.onAccentColor = Qt.binding(() => root.onIslandAccent);
            if ("availableWidth" in item)
                item.availableWidth = Qt.binding(() => root.widgetWidth);
            if ("availableHeight" in item)
                item.availableHeight = Qt.binding(() => root.widgetHeight);
            if ("requestResize" in item)
                item.requestResize = root.requestResize;
            if ("clearResize" in item)
                item.clearResize = root.clearResize;
            if ("media" in item)
                item.media = mediaState;
            if ("config" in item)
                item.config = Qt.binding(() => root.islandConfig);
        }
    }
}
