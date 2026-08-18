pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    readonly property string daemonDir: Qt.resolvedUrl("daemon").toString().replace(/^file:\/\//, "")
    readonly property string daemonBin: daemonDir + "/bin/daemon"
    readonly property bool enableLyricsSetting: pluginData?.enableLyrics ?? true

    Process {
        id: daemonProc
        command: [
            "sh",
            "-c",
            "if [ ! -f \"" + root.daemonBin + "\" ]; then (cd \"" + root.daemonDir + "\" && go build -o bin/daemon .); fi && exec \"" + root.daemonBin + "\""
        ]
        running: true

        stdout: SplitParser {
            onRead: line => {
                if (line.includes("[Daemon]") || line.includes("[Server]") || line.includes("[MPRIS]")) {
                    console.log(line.trim());
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                console.warn("[DynamicIslandDaemon stderr]", line.trim());
            }
        }

        onExited: exitCode => {
            console.log("[DynamicIslandDaemon] Process exited with code:", exitCode);
            if (exitCode !== 0) {
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!daemonProc.running) {
                console.log("[DynamicIslandDaemon] Restarting daemon process...");
                daemonProc.running = true;
            }
        }
    }

    DynamicIslandService {
        id: islandService
    }

    onEnableLyricsSettingChanged: {
        islandService.setLyricsEnabled(root.enableLyricsSetting);
    }

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId === pluginId) {
                const lyricsVal = pluginService.loadPluginData(pluginId, "enableLyrics", true);
                islandService.setLyricsEnabled(lyricsVal);
            }
        }
    }

    Component.onCompleted: {
        console.log("[DynamicIslandDaemon] Daemon component loaded. Binary path:", root.daemonBin);
    }
}
