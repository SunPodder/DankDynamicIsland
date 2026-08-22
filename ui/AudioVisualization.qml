pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

/**
 * GPU-rendered audio bars driven by CavaService.
 *
 * Playback state is injected via `playing` so the visualization follows the
 * island's normalized media model instead of probing MprisController itself.
 * The Cava process is only kept alive while bars are actually visible.
 */
Item {
    id: root

    property color barColor: Theme.primary
    property int barCount: 15
    property real barGap: 1.5
    property bool playing: false

    readonly property bool live: visible && playing

    implicitWidth: Math.max(64, barCount * 4)
    implicitHeight: Theme.iconSize

    readonly property real maxBarHeight: height
    readonly property real minBarHeight: 3

    onLiveChanged: {
        if (!live) {
            bars.bandsA = Qt.vector4d(0, 0, 0, 0);
            bars.bandsB = Qt.vector2d(0, 0);
        }
    }

    // Ref-counts CavaService so the cava process runs only while visible.
    Loader {
        active: root.live
        sourceComponent: Component {
            Ref {
                service: CavaService
            }
        }
    }

    // Cava missing: synthesize gentle motion so the pill still feels alive.
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
        property vector4d fillColor: Qt.vector4d(root.barColor.r, root.barColor.g, root.barColor.b, root.barColor.a)

        fragmentShader: Qt.resolvedUrl("../Shaders/qsb/dynamic_bars.frag.qsb")
    }
}
