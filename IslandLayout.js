.pragma library

/**
 * Layout and animation geometry helpers for Dynamic Island widgets.
 */

function clamp(value, min, max) {
    return Math.max(min, Math.min(value, max));
}

function lerp(start, end, progress) {
    return start + (end - start) * progress;
}

/**
 * Calculate compact island width based on content width and padding
 */
function calculateCompactWidth(contentWidth, padding, minWidth, maxWidth) {
    const raw = contentWidth + (padding || 24);
    const minW = minWidth || 120;
    const maxW = maxWidth || 320;
    return clamp(raw, minW, maxW);
}

/**
 * Calculate expanded island card dimensions
 */
function calculateExpandedDimensions(parentWidth, parentHeight, defaultExpandedW, defaultExpandedH) {
    const targetW = defaultExpandedW || 360;
    const targetH = defaultExpandedH || 170;
    const maxW = (parentWidth && parentWidth > 0) ? Math.min(targetW, parentWidth) : targetW;
    const maxH = (parentHeight && parentHeight > 0) ? Math.min(targetH, parentHeight) : targetH;
    return {
        width: Math.max(280, maxW),
        height: Math.max(140, maxH)
    };
}

/**
 * Smoothly morph corner radius between pill (height/2) and rounded rectangle
 */
function interpolateRadius(compactRadius, expandedRadius, progress) {
    return lerp(compactRadius, expandedRadius, progress);
}

/**
 * Fade out opacity curve for compact content during expansion
 */
function calcCompactOpacity(progress) {
    return clamp(1.0 - progress * 2.2, 0.0, 1.0);
}

/**
 * Fade in opacity curve for expanded content during expansion
 */
function calcExpandedOpacity(progress) {
    if (progress <= 0.2) return 0.0;
    return clamp((progress - 0.2) / 0.8, 0.0, 1.0);
}
