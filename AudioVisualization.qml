import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services

Item {
    id: root

    property color color: Theme.primary
    property int barCount: 15
    property real barGap: 1.5
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer !== null && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool live: visible && isPlaying

    width: Math.max(64, barCount * 3.5)
    height: Theme.iconSize

    readonly property real maxBarHeight: Theme.iconSize
    readonly property real minBarHeight: 3

    onLiveChanged: {
        if (!live) {
            bars.bandsA = Qt.vector4d(0, 0, 0, 0);
            bars.bandsB = Qt.vector2d(0, 0);
        }
    }

    Loader {
        active: root.live
        sourceComponent: Component {
            Ref {
                service: CavaService
            }
        }
    }

    Timer {
        running: !CavaService.cavaAvailable && root.live
        interval: 500
        repeat: true
        onTriggered: {
            CavaService.values = [Math.random() * 20 + 5, Math.random() * 25 + 8, Math.random() * 22 + 6, Math.random() * 20 + 5, Math.random() * 22 + 6, Math.random() * 25 + 8];
        }
    }

    Connections {
        target: CavaService
        enabled: root.live
        function onValuesChanged() {
            const v = CavaService.values;
            if (v.length < 6)
                return;
            const n = i => {
                const x = v[i];
                const level = x <= 0 ? 0 : x >= 100 ? 1 : Math.sqrt(x * 0.01);
                return Math.round(level * 32) / 32;
            };
            const a = Qt.vector4d(n(0), n(1), n(2), n(3));
            const b = Qt.vector2d(n(4), n(5));
            if (a == bars.bandsA && b == bars.bandsB)
                return;
            bars.bandsA = a;
            bars.bandsB = b;
        }
    }

    ShaderEffect {
        id: bars
        anchors.fill: parent

        property real widthPx: width
        property real heightPx: height
        property real minH: root.minBarHeight
        property real maxH: root.maxBarHeight
        property real barCount: root.barCount
        property real barGap: root.barGap
        property vector4d bandsA: Qt.vector4d(0, 0, 0, 0)
        property vector2d bandsB: Qt.vector2d(0, 0)
        property vector4d fillColor: Qt.vector4d(root.color.r, root.color.g, root.color.b, root.color.a)

        fragmentShader: Qt.resolvedUrl("Shaders/qsb/dynamic_bars.frag.qsb")
    }
}