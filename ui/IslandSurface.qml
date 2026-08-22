pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../core/IslandLayout.js" as Layout

/**
 * Morphing shell shared by every island mode.
 *
 * Owns the expand/collapse state machine, hover tracking and geometry
 * animation. Content is provided as two slots (compactContent,
 * expandedContent) faded by expansion progress, so mode components stay purely
 * declarative.
 *
 * A single ancestor HoverHandler tracks the pointer across the whole card -
 * including over child controls - which replaces per-control MouseArea
 * enter/exit coordination and its collapse races.
 *
 * The desktop wrapper's resize protocol is bridged: expanding grows the
 * wrapper container via requestResize(), a finished collapse releases it via
 * clearResize().
 */
Item {
    id: surface

    // ---- geometry contract (driven by the mode component) ----
    property real compactWidth: Layout.COMPACT_MIN_WIDTH
    property real compactHeight: Layout.ISLAND_HEIGHT
    property real expandedWidth: Layout.EXPANDED_DEFAULT_WIDTH
    property real expandedHeight: Layout.EXPANDED_DEFAULT_HEIGHT
    property real expandedRadius: Layout.EXPANDED_RADIUS

    // ---- appearance ----
    property color backgroundColor: Theme.surfaceContainerHigh
    /// Animated in with expansion progress; bind to a transparent color to disable.
    property color outlineColor: "transparent"

    // ---- behaviour ----
    /// Expansion gate (e.g. only while media is playing).
    property bool expandable: true
    /// Master switch for hover interaction (off during desktop edit mode).
    property bool interactive: true

    // ---- desktop wrapper resize bridge ----
    property var requestResize: null
    property var clearResize: null
    /// Extra room the wrapper container needs beyond the card itself.
    property real surfacePaddingH: 0
    property real surfacePaddingV: 0
    // ---- compact fit ----
    /// While enabled and collapsed, keeps the wrapper container fitted to the
    /// compact pill (compactFitWidth) instead of the saved widget size, so
    /// unclamped content such as live lyrics is never cut off.
    property bool fitCompact: false
    /// Natural (unclamped) compact width used when fitting; defaults to compactWidth.
    property real compactFitWidth: compactWidth

    onFitCompactChanged: _updateCompactFit()
    onCompactFitWidthChanged: _updateCompactFit()

    // ---- content slots ----
    property Component compactContent
    property Component expandedContent

    readonly property bool expanded: isExpanded
    readonly property real progress: expandProgress
    readonly property alias expandedContentItem: expandedLoader.item

    property bool isExpanded: false
    property real expandProgress: 0

    implicitWidth: Math.round(currentWidth)
    implicitHeight: Math.round(currentHeight)

    property real animatedCompactWidth: compactWidth

    Behavior on animatedCompactWidth {
        NumberAnimation {
            duration: Layout.WIDTH_EASE_DURATION
            easing.type: Easing.OutCubic
        }
    }

    readonly property real currentWidth: Layout.lerp(surface.animatedCompactWidth, surface.expandedWidth, surface.expandProgress)
    readonly property real currentHeight: Layout.lerp(surface.compactHeight, surface.expandedHeight, surface.expandProgress)
    readonly property real currentRadius: Layout.interpolateRadius(surface.compactHeight / 2, surface.expandedRadius, surface.expandProgress)

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(surface.currentWidth)
        height: Math.round(surface.currentHeight)
        radius: surface.currentRadius
        color: surface.backgroundColor
        border.color: surface.outlineColor
        border.width: surface.expandProgress > 0.05 ? 1 : 0
        clip: true

        HoverHandler {
            id: hover
            enabled: surface.interactive

            onHoveredChanged: {
                if (hovered) {
                    graceTimer.stop();
                    if (surface.expandable)
                        surface.expand();
                } else {
                    graceTimer.restart();
                }
            }
        }

        Item {
            width: surface.animatedCompactWidth
            height: surface.compactHeight
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            clip: true
            opacity: Layout.calcCompactOpacity(surface.expandProgress)
            visible: opacity > 0

            Loader {
                id: compactLoader
                anchors.centerIn: parent
                sourceComponent: surface.compactContent
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            opacity: Layout.calcExpandedOpacity(surface.expandProgress)
            visible: opacity > 0

            Loader {
                id: expandedLoader
                anchors.fill: parent
                sourceComponent: surface.expandedContent
            }
        }
    }

    Timer {
        id: graceTimer
        interval: Layout.HOVER_GRACE_MS
        onTriggered: surface.collapse()
    }

    NumberAnimation {
        id: expandAnim
        target: surface
        property: "expandProgress"
        to: 1.0
        duration: Layout.EXPAND_DURATION
        easing.type: Easing.OutBack
        easing.overshoot: 1.15
    }

    NumberAnimation {
        id: collapseAnim
        target: surface
        property: "expandProgress"
        to: 0.0
        duration: Layout.COLLAPSE_DURATION
        easing.type: Easing.OutCubic
        onFinished: {
            if (!surface.isExpanded) {
                if (surface.fitCompact)
                    surface._updateCompactFit();
                else
                    surface._releaseResize();
            }
        }
    }

    Component.onDestruction: _releaseResize()

    function expand() {
        if (!expandable || isExpanded)
            return;
        isExpanded = true;
        collapseAnim.stop();
        _growContainer();
        expandAnim.restart();
    }

    function collapse() {
        if (!isExpanded && expandProgress === 0)
            return;
        isExpanded = false;
        expandAnim.stop();
        collapseAnim.restart();
    }

    /// Collapse immediately, bypassing the hover grace period.
    function forceCollapse() {
        graceTimer.stop();
        collapse();
    }

    function _growContainer() {
        if (typeof requestResize === "function")
            requestResize(Math.ceil(expandedWidth) + surfacePaddingH, Math.ceil(expandedHeight) + surfacePaddingV);
    }

    function _releaseResize() {
        if (typeof clearResize === "function")
            clearResize();
    }

    /// Refits the wrapper around the compact pill. No-op while expanded or
    /// mid-animation; releases the override when fitting is disabled.
    function _updateCompactFit() {
        if (isExpanded || expandProgress > 0)
            return;
        if (!fitCompact) {
            _releaseResize();
            return;
        }
        if (typeof requestResize !== "function")
            return;
        requestResize(Math.ceil(compactFitWidth) + surfacePaddingH, Math.ceil(compactHeight) + surfacePaddingV);
    }
}
