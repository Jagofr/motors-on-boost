package ui.views.mainmenu;

import h2d.Object;
import h2d.Text;
import ui.FontManager;
import ui.UIIcons;
import ui.components.MenuItemRow;
import ui.components.UITheme;
import ui.components.UIEnums.MenuAction;
import audio.AudioManager;

/**
 * Main menu panel view providing navigation across play, resume, options, credits, and exit.
 */
class MainMenuView extends Object {
    /** Menu title heading display. */
    public var titleText:Text;

    /** Build version badge display. */
    public var versionText:Text;

    /** Menu item rows collection. */
    public var rows:Array<MenuItemRow> = [];

    /** Dispatched actions corresponding to each menu row. */
    public static var ACTIONS:Array<MenuAction> = [
        StartGame,
        ResumeGame,
        OpenOptions,
        OpenCredits,
        QuitToTitle
    ];

    /** Currently selected/highlighted row index. */
    public var selectedIndex:Int = 0;

    /** True if an active saved race run is available to resume. */
    public var hasActiveSave:Bool = false;

    /** Audio frequency played upon confirming an action in Hz. */
    public static inline var AUDIO_BEEP_CONFIRM_FREQ:Float = 520.0;

    /** Audio frequency played when cycling the navigation cursor in Hz. */
    public static inline var AUDIO_BEEP_NAV_FREQ:Float = 380.0;

    /** Callback invoked when an action is selected. */
    public var onActionSelected:MenuAction->Void;

    /**
     * Instantiates the main menu view and builds menu rows.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.heroFont, this);
        titleText.text = "MAIN MENU";
        titleText.textColor = UITheme.COLOR_ACCENT_CYAN;

        versionText = new Text(FontManager.regularFont, this);
        versionText.text = Version.DISPLAY;
        versionText.textColor = UITheme.COLOR_TEXT_MUTED;

        var labels = ["START NEW RACE", "RESUME SAVED RACE", "OPTIONS", "CREDITS", "EXIT TO SPLASH"];
        var iconTypes = [
            UIIcons.IconType.Play,
            UIIcons.IconType.Resume,
            UIIcons.IconType.Settings,
            UIIcons.IconType.Credits,
            UIIcons.IconType.Exit
        ];

        for (i in 0...labels.length) {
            var row = new MenuItemRow(UIIcons.get(iconTypes[i], UITheme.ICON_SIZE_MENU, UITheme.COLOR_ACCENT_CYAN), labels[i], 440, 44, this);
            rows.push(row);

            row.interactive.onOver = function(_) {
                if (visible) {
                    selectedIndex = i;
                    updateStyles();
                }
            };

            row.interactive.onClick = function(_) {
                if (visible) {
                    if (i == 1 && !hasActiveSave) return;
                    AudioManager.inst.playMenuBeep(AUDIO_BEEP_CONFIRM_FREQ, 0.08);
                    triggerAction(ACTIONS[i]);
                }
            };
        }
    }

    /**
     * Activates the main menu, resetting selection to resume if available.
     *
     * @param hasSave True if a saved run can be resumed.
     */
    public function activate(hasSave:Bool) {
        visible = true;
        hasActiveSave = hasSave;
        selectedIndex = hasActiveSave ? 1 : 0;
        updateStyles();
    }

    /**
     * Sets the saved run state flag and refreshes button styling.
     *
     * @param val True if save data is present.
     */
    public function setHasActiveSave(val:Bool) {
        hasActiveSave = val;
        updateStyles();
    }

    /**
     * Dispatches the specified menu action.
     *
     * @param act Target action to emit.
     */
    public function triggerAction(act:MenuAction) {
        if (onActionSelected != null) {
            onActionSelected(act);
        }
    }

    /**
     * Advances or reverses menu selection cursor with audio feedback.
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
        if (selectedIndex == 1 && !hasActiveSave) return;
        AudioManager.inst.playMenuBeep(AUDIO_BEEP_CONFIRM_FREQ, 0.08);
        triggerAction(ACTIONS[selectedIndex]);
    }

    /**
     * Refreshes text colors and icon tints across all menu item rows.
     */
    public function updateStyles() {
        for (i in 0...rows.length) {
            var row = rows[i];
            var isEnabled = !(i == 1 && !hasActiveSave);
            row.setStyle(
                i == selectedIndex,
                isEnabled,
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
            titleText.y = sh * 0.16;
        }

        for (i in 0...rows.length) {
            var row = rows[i];
            var rowY = sh * 0.32 + (i * UITheme.MAIN_ROW_STRIDE);
            var rowStartX = sw * 0.5 - 190;

            row.iconBmp.x = rowStartX;
            row.iconBmp.y = rowY + 3;

            row.labelTxt.x = rowStartX + 36;
            row.labelTxt.y = rowY;

            row.interactive.x = sw * 0.5 - 220;
            row.interactive.y = rowY - 4;
            row.interactive.width = 440;
            row.interactive.height = 44;
        }

        if (versionText != null) {
            versionText.x = (sw - versionText.textWidth) * 0.5;
            versionText.y = sh * 0.88;
        }
    }
}
