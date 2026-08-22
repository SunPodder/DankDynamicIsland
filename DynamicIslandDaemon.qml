pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Modules.Plugins

/**
 * Daemon surface: supervises the island helper binary (daemon/).
 *
 * The binary is built on first run (requires the Go toolchain) and restarted
 * when it exits non-zero. Media/lyrics preferences are pushed by the desktop
 * surface over its own connection, so this component stays a pure process
 * supervisor.
 */
PluginComponent {
    id: root

    property var popoutService: null

    readonly property string daemonDir: Qt.resolvedUrl("daemon").toString().replace(/^file:\/\//, "")
    readonly property string daemonBin: daemonDir + "/bin/daemon"

    Process {
        id: daemonProc
        command: [
            "sh",
            "-c",
            "if [ ! -f \"" + root.daemonBin + "\" ]; then (cd \"" + root.daemonDir + "\" && go build -o bin/daemon .); fi && exec \"" + root.daemonBin + "\""
        ]
        running: true

        stdout: SplitParser {
            onRead: line => console.log(line.trim())
        }

        stderr: SplitParser {
            onRead: line => console.warn("[IslandDaemon]", line.trim())
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("[IslandDaemon] Exited with code", exitCode, "- restarting in 3s");
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: {
            if (!daemonProc.running)
                daemonProc.running = true;
        }
    }
}
