package ui.views.pause;

import h2d.Object;
import h2d.Text;
import ui.FontManager;
import ui.UIIcons;
import ui.components.MenuItemRow;
import ui.components.UITheme;
import audio.AudioManager;

/**
 * Mid-race pause menu modal overlay view.
 */
class PauseMenuView extends Object {
    /** Pause heading banner text. */
    public var titleText:Text;

    /** Menu item rows collection. */
    public var rows:Array<MenuItemRow> = [];

    /** Currently selected row index. */
    public var selectedIndex:Int = 0;

    /** Audio frequency played upon confirming an action in Hz. */
    public static inline var AUDIO_BEEP_CONFIRM_FREQ:Float = 520.0;

    /** Audio frequency played when cycling the navigation cursor in Hz. */
    public static inline var AUDIO_BEEP_NAV_FREQ:Float = 380.0;

    /** Callbacks triggered on menu selections. */
    public var onResume:Void->Void;
    public var onRestart:Void->Void;
    public var onOptions:Void->Void;
    public var onQuitToTitle:Void->Void;

    /**
     * Instantiates the pause menu view and builds pause action options.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.heroFont, this);
        titleText.text = "PAUSED";
        titleText.textColor = UITheme.COLOR_ACCENT_GOLD;

        var labels = ["RESUME RACE", "RESTART RACE", "OPTIONS", "MAIN MENU"];
        var pauseIconTypes = [
            UIIcons.IconType.Resume,
            UIIcons.IconType.Restart,
            UIIcons.IconType.Settings,
            UIIcons.IconType.Exit
        ];

        for (i in 0...labels.length) {
            var row = new MenuItemRow(UIIcons.get(pauseIconTypes[i], UITheme.ICON_SIZE_MENU, UITheme.COLOR_ACCENT_GOLD), labels[i], 380, 44, this);
            rows.push(row);

            row.interactive.onOver = function(_) {
                if (visible) {
                    selectedIndex = i;
                    updateStyles();
                }
            };

            row.interactive.onClick = function(_) {
                if (visible) {
                    AudioManager.inst.playMenuBeep(AUDIO_BEEP_CONFIRM_FREQ, 0.08);
                    triggerActionByIndex(i);
                }
            };
        }
    }

    /**
     * Activates the pause menu and resets cursor to resume.
     */
    public function activate() {
        visible = true;
        selectedIndex = 0;
        updateStyles();
    }

    /**
     * Navigates cursor up or down with audio feedback.
     *
     * @param dir Navigation offset (-1 for up, +1 for down).
     */
    public function navigate(dir:Int) {
        selectedIndex = (selectedIndex + dir + rows.length) % rows.length;
        AudioManager.inst.playMenuBeep(AUDIO_BEEP_NAV_FREQ, 0.04);
        updateStyles();
    }

    /**
     * Confirms the currently focused selection.
     */
    public function confirmSelection() {
        AudioManager.inst.playMenuBeep(AUDIO_BEEP_CONFIRM_FREQ, 0.08);
        triggerActionByIndex(selectedIndex);
    }

    /**
     * Dispatches action corresponding to index.
     *
     * @param idx Option index.
     */
    function triggerActionByIndex(idx:Int) {
        switch (idx) {
            case 0: if (onResume != null) onResume();
            case 1: if (onRestart != null) onRestart();
            case 2: if (onOptions != null) onOptions();
            case 3: if (onQuitToTitle != null) onQuitToTitle();
        }
    }

    /**
     * Refreshes text colors and icon tints across pause item rows.
     */
    public function updateStyles() {
        for (i in 0...rows.length) {
            rows[i].setStyle(
                i == selectedIndex,
                true,
                UITheme.COLOR_ACCENT_CYAN,
                UITheme.COLOR_TEXT_NORMAL,
                UITheme.COLOR_TEXT_DISABLED
            );
        }
    }

    /**
     * Positions title heading and option rows relative to screen bounds.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = sh * 0.20;
        }

        for (i in 0...rows.length) {
            var row = rows[i];
            var rowY = sh * 0.38 + (i * UITheme.PAUSE_ROW_STRIDE);
            var rowStartX = sw * 0.5 - 160;

            row.iconBmp.x = rowStartX;
            row.iconBmp.y = rowY + 3;

            row.labelTxt.x = rowStartX + 36;
            row.labelTxt.y = rowY;

            row.interactive.x = sw * 0.5 - 190;
            row.interactive.y = rowY - 4;
            row.interactive.width = 380;
            row.interactive.height = 44;
        }
    }
}
