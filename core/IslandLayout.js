.pragma library

/**
 * Geometry and animation math for the dynamic island morph.
 *
 * The pill-to-card morph is this component's signature motion, so it keeps its
 * own timing constants instead of following the shell-wide animation-speed
 * setting (which can be zero = instant).
 */

// Signature motion timing (ms)
var EXPAND_DURATION = 320;
var COLLAPSE_DURATION = 250;
var WIDTH_EASE_DURATION = 220;
var HOVER_GRACE_MS = 180;

// Sizing
var ISLAND_HEIGHT = 48;        // compact pill height
var COMPACT_MIN_WIDTH = 160;
var EXPANDED_DEFAULT_WIDTH = 360;
var EXPANDED_DEFAULT_HEIGHT = 176;
var EXPANDED_MIN_WIDTH = 280;
var EXPANDED_MIN_HEIGHT = 140;
var EXPANDED_RADIUS = 24;

function clamp(value, min, max) {
    return Math.max(min, Math.min(value, max));
}

function lerp(start, end, progress) {
    return start + (end - start) * progress;
}

/** Smoothly morph corner radius between pill (height/2) and expanded card. */
function interpolateRadius(compactRadius, expandedRadius, progress) {
    return lerp(compactRadius, expandedRadius, progress);
}

/**
 * Expanded card dimensions: target size clamped to the desktop widget bounds.
 */
function expandedDimensions(parentWidth, parentHeight) {
    const maxW = (parentWidth && parentWidth > 0) ? Math.min(EXPANDED_DEFAULT_WIDTH, parentWidth) : EXPANDED_DEFAULT_WIDTH;
    const maxH = (parentHeight && parentHeight > 0) ? Math.min(EXPANDED_DEFAULT_HEIGHT, parentHeight) : EXPANDED_DEFAULT_HEIGHT;
    return {
        width: Math.max(EXPANDED_MIN_WIDTH, maxW),
        height: Math.max(EXPANDED_MIN_HEIGHT, maxH)
    };
}

/** Fade out curve for compact content during expansion. */
function calcCompactOpacity(progress) {
    return clamp(1.0 - progress * 2.2, 0.0, 1.0);
}

/** Fade in curve for expanded content during expansion. */
function calcExpandedOpacity(progress) {
    if (progress <= 0.2)
        return 0.0;
    return clamp((progress - 0.2) / 0.8, 0.0, 1.0);
}
