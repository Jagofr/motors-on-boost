package ui.views.options;

import h2d.Object;
import h2d.Text;
import h2d.Bitmap;
import h2d.Interactive;
import ui.FontManager;
import ui.UIIcons;
import ui.components.UITheme;
import audio.AudioManager;

/**
 * Audio channels volume sliders configuration subpanel view.
 */
class AudioOptionsPanel extends Object {
    /** Text items displaying channel labels and slider bars. */
    public var items:Array<Text> = [];

    /** Channel iconography icons. */
    public var icons:Array<Bitmap> = [];

    /** Interactive hitzones for volume slider adjustments. */
    public var interactives:Array<Interactive> = [];

    /** Currently highlighted channel index. */
    public var selectedIndex:Int = 0;

    /** Interactive row hitzone width in pixels. */
    public static inline var ROW_WIDTH:Float = 560.0;

    /** Interactive row hitzone height in pixels. */
    public static inline var ROW_HEIGHT:Float = 48.0;

    /** Vertical spacing between successive audio slider rows in pixels. */
    public static inline var ROW_STRIDE:Float = 64.0;

    /** Total number of discrete bars in the volume slider display. */
    public static inline var TOTAL_SLIDER_BARS:Int = 12;

    /**
     * Instantiates the audio volume configuration subpanel.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        var optLabels = ["Master Volume", "Music Track", "Sound Effects (SFX)"];
        var audioIconTypes = [
            UIIcons.IconType.Volume,
            UIIcons.IconType.Music,
            UIIcons.IconType.Sfx
        ];

        for (i in 0...optLabels.length) {
            var row = new Object(this);

            var iconBmp = new Bitmap(UIIcons.get(audioIconTypes[i], UITheme.ICON_SIZE_AUDIO, UITheme.COLOR_ACCENT_CYAN), row);
            icons.push(iconBmp);

            var txt = new Text(FontManager.regularFont, row);
            items.push(txt);

            var inter = new Interactive(ROW_WIDTH, ROW_HEIGHT, this);
            inter.onOver = function(_) {
                if (visible) {
                    selectedIndex = i;
                    updateStyles();
                }
            };
            inter.onClick = function(_) {
                if (visible) adjustVolume(i, 0.1);
            };
            interactives.push(inter);
        }
    }

    /**
     * Formats a floating-point volume value into discrete geometric bar blocks and percentage.
     *
     * @param val Volume scalar [0.0 - 1.0].
     * @return Formatted bar string representation.
     */
    public static function formatSlider(val:Float):String {
        var pct = Math.round(val * 100);
        var activeBars = Math.round(val * TOTAL_SLIDER_BARS);

        var barStr = "";
        for (i in 0...TOTAL_SLIDER_BARS) {
            barStr += (i < activeBars ? FontManager.BLOCK_FILLED : FontManager.BLOCK_EMPTY);
        }

        return "[" + barStr + "]  " + (pct < 100 ? (pct < 10 ? "  " : " ") : "") + pct + "%";
    }

    /**
     * Adjusts the volume on the specified channel by delta amount.
     *
     * @param channel Channel index (0: Master, 1: Music, 2: SFX).
     * @param delta Adjustment delta.
     */
    public function adjustVolume(channel:Int, delta:Float) {
        var am = AudioManager.inst;
        switch (channel) {
            case 0: am.masterVolume = Math.max(0.0, Math.min(1.0, am.masterVolume + delta));
            case 1: am.musicVolume = Math.max(0.0, Math.min(1.0, am.musicVolume + delta));
            case 2: am.sfxVolume = Math.max(0.0, Math.min(1.0, am.sfxVolume + delta));
        }
        am.playMenuBeep(480 + (channel * 60), 0.05);
        updateStyles();
    }

    /**
     * Navigates cursor up or down.
     *
     * @param dir Navigation offset (-1 or +1).
     */
    public function navigate(dir:Int) {
        selectedIndex = (selectedIndex + dir + items.length) % items.length;
        AudioManager.inst.playMenuBeep(380, 0.04);
        updateStyles();
    }

    /**
     * Refreshes text displays, slider representations, and icon tints.
     */
    public function updateStyles() {
        var am = AudioManager.inst;
        var labels = [
            "Master Volume:     " + formatSlider(am.masterVolume),
            "Music Track:       " + formatSlider(am.musicVolume),
            "Sound FX & Tires:  " + formatSlider(am.sfxVolume)
        ];

        for (i in 0...items.length) {
            var item = items[i];
            var ic = icons[i];
            if (i == selectedIndex) {
                item.textColor = UITheme.COLOR_ACCENT_CYAN;
                ic.color.setColor(UITheme.COLOR_ACCENT_CYAN);
                item.text = "> " + labels[i] + " <";
            } else {
                item.textColor = UITheme.COLOR_TEXT_NORMAL;
                ic.color.setColor(UITheme.COLOR_TEXT_MUTED);
                item.text = "  " + labels[i] + "  ";
            }
        }
    }

    /**
     * Positions slider rows and interactive hitboxes relative to modal card bounds.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param cardX Modal card left coordinate.
     * @param cardY Modal card top coordinate.
     * @param cardW Modal card width.
     * @param cardH Modal card height.
     */
    public function layout(sw:Float, sh:Float, cardX:Float = 0, cardY:Float = 0, cardW:Float = 0, cardH:Float = 0) {
        var effectiveCardX = (cardW > 0) ? cardX : (sw - UITheme.OPTIONS_CARD_WIDTH) * 0.5;
        var effectiveCardY = (cardH > 0) ? cardY : sh * 0.16;
        var effectiveCardW = (cardW > 0) ? cardW : UITheme.OPTIONS_CARD_WIDTH;
        var effectiveCardH = (cardH > 0) ? cardH : UITheme.OPTIONS_CARD_HEIGHT;

        var totalHeight = items.length * ROW_STRIDE;
        var startY = effectiveCardY + (effectiveCardH - totalHeight) * 0.5 + 24.0;
        var rowX = effectiveCardX + (effectiveCardW - ROW_WIDTH) * 0.5;

        for (i in 0...items.length) {
            var item = items[i];
            var ic = icons[i];
            var inter = interactives[i];

            var rowY = startY + (i * ROW_STRIDE);

            ic.x = rowX;
            ic.y = rowY - 3;

            item.x = rowX + 44;
            item.y = rowY;

            inter.x = rowX;
            inter.y = rowY - 4;
            inter.width = ROW_WIDTH;
            inter.height = ROW_HEIGHT;
        }
    }
}
