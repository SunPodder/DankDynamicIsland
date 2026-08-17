import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "DankDynamicIsland"

    StyledText {
        width: parent.width
        text: "Dynamic Island Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure colors and visualization bar counts for compact and extended components."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "inheritTheme"
        label: "Inherit Theme Colors"
        description: "Use system theme colors instead of custom background and foreground colors"
        defaultValue: false
    }

    ColorSetting {
        settingKey: "backgroundColor"
        label: "Background Color"
        description: "Custom background color for compact and extended components"
        defaultValue: "#0b0b0b"
    }

    ColorSetting {
        settingKey: "foregroundColor"
        label: "Foreground Color"
        description: "Custom foreground/text color for compact and extended components"
        defaultValue: "#f5f5f5"
    }

    SliderSetting {
        settingKey: "compactBarCount"
        label: "Compact Mode Bars Count"
        description: "Number of audio visualizer bars in compact mode"
        defaultValue: 15
        minimum: 4
        maximum: 32
    }

    SliderSetting {
        settingKey: "extendedBarCount"
        label: "Extended Mode Bars Count"
        description: "Number of audio visualizer bars in extended mode"
        defaultValue: 16
        minimum: 4
        maximum: 32
    }
}