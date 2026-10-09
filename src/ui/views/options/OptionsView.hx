package ui.views.options;

import h2d.Object;
import h2d.Text;
import h2d.Bitmap;
import h2d.Interactive;
import ui.FontManager;
import ui.UIIcons;
import ui.components.UITheme;
import ui.components.UIEnums.OptionsTab;
import save.SaveSystem.GraphicsSettings;
import input.InputController;
import audio.AudioManager;

/**
 * Composite hardware configuration and options modal container view.
 * Integrates tab navigation across Graphics, Audio, Keyboard, and Gamepad subpanels.
 */
class OptionsView extends Object {
    /** Title banner display. */
    public var titleText:Text;

    /** Build version badge display. */
    public var versionText:Text;

    /** Tab buttons labels and icons. */
    public var tabLabels:Array<Text> = [];
    public var tabIcons:Array<Bitmap> = [];
    public var tabInteractives:Array<Interactive> = [];

    /** Currently active configuration tab. */
    public var currentTab:OptionsTab = Graphics;
    public static var TAB_ORDER:Array<OptionsTab> = [Graphics, Audio, Keyboard, Gamepad];

    /** Subpanel views. */
    public var gfxPanel:GraphicsOptionsPanel;
    public var audioPanel:AudioOptionsPanel;
    public var controlsPanel:ControlsOptionsPanel;

    /** On-screen touch/mouse back button display and interaction. */
    public var backBtnText:Text;
    public var backInteractive:Interactive;

    /** Callback invoked when the user selects back / return. */
    public var onBack:Void->Void;

    /** True if opened during an active race. */
    public var isOpenedFromPause:Bool = false;

    /** Tab interactive hitzone width in pixels. */
    public static inline var TAB_BUTTON_WIDTH:Float = 150.0;

    /** Tab interactive hitzone height in pixels. */
    public static inline var TAB_BUTTON_HEIGHT:Float = 42.0;

    /**
     * Instantiates the options modal container view.
     *
     * @param input Input controller reference.
     * @param gfxSettings Graphics settings record.
     * @param parent Optional parent 2D scene object.
     */
    public function new(input:InputController, gfxSettings:GraphicsSettings, ?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.titleFont, this);
        titleText.text = "CONFIGURATION & HARDWARE";
        titleText.textColor = UITheme.COLOR_ACCENT_CYAN;

        versionText = new Text(FontManager.regularFont, this);
        versionText.text = Version.DISPLAY;
        versionText.textColor = UITheme.COLOR_TEXT_MUTED;

        var tabNames = ["GRAPHICS", "AUDIO", "KEYBOARD", "GAMEPAD"];
        var tabIconTypes = [
            UIIcons.IconType.Graphics,
            UIIcons.IconType.Volume,
            UIIcons.IconType.Keyboard,
            UIIcons.IconType.Gamepad
        ];

        for (i in 0...tabNames.length) {
            var tIcon = new Bitmap(UIIcons.get(tabIconTypes[i], UITheme.ICON_SIZE_TAB, UITheme.COLOR_ACCENT_CYAN), this);
            tabIcons.push(tIcon);

            var tTxt = new Text(FontManager.regularFont, this);
            tTxt.text = tabNames[i];
            tabLabels.push(tTxt);

            var tabInter = new Interactive(TAB_BUTTON_WIDTH, TAB_BUTTON_HEIGHT, this);
            tabInter.onClick = function(_) switchTab(TAB_ORDER[i]);
            tabInteractives.push(tabInter);
        }

        // Dedicated touch/mouse back button
        backBtnText = new Text(FontManager.regularFont, this);
        backBtnText.text = "< BACK";
        backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;

        backInteractive = new Interactive(UITheme.BACK_BUTTON_WIDTH, UITheme.BACK_BUTTON_HEIGHT, this);
        backInteractive.onOver = function(_) {
            if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_GOLD;
        };
        backInteractive.onOut = function(_) {
            if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;
        };
        backInteractive.onClick = function(_) {
            if (visible && onBack != null) {
                AudioManager.inst.playMenuBeep(320, 0.06);
                onBack();
            }
        };

        gfxPanel = new GraphicsOptionsPanel(gfxSettings, this);
        audioPanel = new AudioOptionsPanel(this);
        controlsPanel = new ControlsOptionsPanel(input, this);
    }

    /**
     * Activates the options panel.
     *
     * @param fromPause True if opened during a race.
     */
    public function activate(fromPause:Bool) {
        visible = true;
        isOpenedFromPause = fromPause;
        gfxPanel.isOpenedFromPause = fromPause;
        switchTab(Graphics);
    }

    /**
     * Switches currently active subpanel tab.
     *
     * @param newTab Target OptionsTab to display.
     */
    public function switchTab(newTab:OptionsTab) {
        currentTab = newTab;
        AudioManager.inst.playMenuBeep(420, 0.05);

        gfxPanel.visible = (currentTab == Graphics);
        audioPanel.visible = (currentTab == Audio);
        controlsPanel.visible = (currentTab == Keyboard || currentTab == Gamepad);
        controlsPanel.currentTab = currentTab;

        if (currentTab == Keyboard || currentTab == Gamepad) {
            controlsPanel.updateControlViewMode();
        } else if (currentTab == Graphics) {
            gfxPanel.updateStyles();
        } else if (currentTab == Audio) {
            audioPanel.updateStyles();
        }

        updateTabStyles();
    }

    /**
     * Cycles between tabs sequentially.
     *
     * @param dir Direction offset (-1 for previous, +1 for next).
     */
    public function cycleTab(dir:Int) {
        var currentIdx = TAB_ORDER.indexOf(currentTab);
        var nextIdx = (currentIdx + dir + TAB_ORDER.length) % TAB_ORDER.length;
        switchTab(TAB_ORDER[nextIdx]);
    }

    /**
     * Refreshes text colors and highlight borders on tab headers.
     */
    public function updateTabStyles() {
        for (i in 0...TAB_ORDER.length) {
            var lbl = tabLabels[i];
            var ic = tabIcons[i];

            if (TAB_ORDER[i] == currentTab) {
                lbl.textColor = UITheme.COLOR_ACCENT_CYAN;
                ic.color.setColor(UITheme.COLOR_ACCENT_CYAN);
            } else {
                lbl.textColor = 0x7E8E9F;
                ic.color.setColor(0x7E8E9F);
            }
        }
    }

    /**
     * Positions tab buttons and child subpanels.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = sh * 0.10;
        }

        var tabSpacing = UITheme.OPTIONS_TAB_SPACING;
        var tabStartX = (sw - (TAB_ORDER.length * tabSpacing)) * 0.5;
        for (i in 0...TAB_ORDER.length) {
            var ic = tabIcons[i];
            var lbl = tabLabels[i];
            var inter = tabInteractives[i];

            var colX = tabStartX + (i * tabSpacing);
            var colY = sh * 0.18;

            ic.x = colX + 18;
            ic.y = colY + 4;

            lbl.x = colX + 48;
            lbl.y = colY + 3;

            inter.x = colX + 6;
            inter.y = colY - 4;
            inter.width = TAB_BUTTON_WIDTH;
            inter.height = TAB_BUTTON_HEIGHT;
        }

        var cardW = UITheme.OPTIONS_CARD_WIDTH;
        var cardH = UITheme.OPTIONS_CARD_HEIGHT;
        var cardX = (sw - cardW) * 0.5;
        var cardY = sh * 0.16;

        if (backBtnText != null && backInteractive != null) {
            backBtnText.x = cardX + 36;
            backBtnText.y = cardY + 22;
            backInteractive.x = cardX + 24;
            backInteractive.y = cardY + 16;
            backInteractive.width = UITheme.BACK_BUTTON_WIDTH;
            backInteractive.height = UITheme.BACK_BUTTON_HEIGHT;
        }

        if (versionText != null) {
            versionText.x = cardX + cardW - versionText.textWidth - 36;
            versionText.y = cardY + 22;
        }

        if (gfxPanel != null) gfxPanel.layout(sw, sh, cardX, cardY, cardW, cardH);
        if (audioPanel != null) audioPanel.layout(sw, sh, cardX, cardY, cardW, cardH);
        if (controlsPanel != null) controlsPanel.layout(sw, sh, cardX, cardY, cardW, cardH);
    }
}
