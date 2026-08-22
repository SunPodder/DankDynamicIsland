.pragma library

/**
 * Central definition of every user-configurable island option and the
 * resolution order used by all surfaces.
 *
 * Resolution (later wins):
 *   1. DEFAULTS        - built-in fallbacks
 *   2. globalSettings  - Settings > Plugins > Dynamic Island (plugin_settings.json)
 *   3. instanceConfig  - per desktop-widget instance overrides
 *
 * Callers must invoke resolve() from inside a QML binding so changes to either
 * source re-evaluate reactively.
 */

var DEFAULTS = {
    enableLyrics: true,
    inheritTheme: false,
    backgroundColor: "#0b0b0b",
    foregroundColor: "#f5f5f5",
    compactBarCount: 15,
    extendedBarCount: 16
};

function resolve(globalSettings, instanceConfig) {
    return Object.assign({}, DEFAULTS, globalSettings || {}, instanceConfig || {});
}
