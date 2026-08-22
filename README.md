# Dank Dynamic Island

Apple inspired Dynamic Island for Dank Material Shell.

## Features
- Clock pill on idle, follows the shell's clock format settings
- Compact media pill with live audio visualizer and scrolling track label
- Morphs into an expanded card on hover: player identity, track info, synced lyrics, seekbar, transport controls
- Synced lyrics from LRCLIB via the bundled helper daemon
- Works without the daemon (falls back to MPRIS directly)

## Architecture

```
DankDynamicIsland/
├── plugin.json                  # composite: desktop widget + daemon
├── DynamicIsland.qml            # desktop surface: config resolution, mode switching
├── DynamicIslandDaemon.qml      # daemon surface: helper process supervision
├── DynamicIslandSettings.qml    # global settings UI
├── core/                        # shared, UI-free modules
│   ├── IslandConfig.js          # settings defaults + resolution order
│   ├── IslandLayout.js          # geometry/animation math, signature timing
│   ├── IslandService.qml        # WebSocket client for the helper daemon
│   └── MediaState.qml           # normalized media model (daemon or MPRIS)
├── ui/                          # view modules
│   ├── IslandSurface.qml        # morphing shell: expand/collapse FSM, hover, resize bridge
│   ├── MediaIsland.qml          # media mode composition
│   ├── ClockIsland.qml          # idle clock pill
│   ├── TransportBar.qml         # Material 3 transport controls
│   ├── MarqueeLabel.qml         # eliding/scrolling label
│   ├── SeekBar.qml              # expanded-card seekbar with drag preview
│   └── AudioVisualization.qml   # Cava-driven GPU bars
├── Shaders/                     # dynamic_bars.frag + prebuilt .qsb
└── daemon/                      # Go helper: MPRIS + LRCLIB over WebSocket/UDS
```

### Settings inheritance

Settings resolve as `defaults <- global plugin settings <- per-instance config`
(see `core/IslandConfig.js`). Desktop widget instances therefore inherit
changes made in Settings > Plugins > Dynamic Island; instance config keys
still win. Resolution happens inside a QML binding, so changes apply live.

### Injection contract

`DynamicIsland.qml` injects into loaded mode components: palette colors
(`backgroundColor`, `foregroundColor`, `accentColor`, `onAccentColor`),
`availableWidth`/`availableHeight`, the wrapper resize bridge
(`requestResize`/`clearResize`), plus `media` and `config` for the media mode.
While playing, the surface also keeps the wrapper fitted to the compact pill
(`IslandSurface.fitCompact`), so live lyrics of any length stay fully visible.

### Design system

All colors, spacing, radii and font sizes come from `Theme.*` tokens. When
"Inherit Theme Colors" is off, the custom palette is mapped onto the same
semantic roles (surface/on-surface/accent) so both modes share one code path.

## Development

Rebuild the bar shader after editing `Shaders/dynamic_bars.frag`:

```sh
qsb Shaders/dynamic_bars.frag -o Shaders/qsb/dynamic_bars.frag.qsb
```

The helper daemon builds itself on first run (`go` must be installed).

## Planned
- Download progress indicator
- OBS Studio recording integration
