package ui;

import h2d.Object;
import h2d.Text;
import h2d.Graphics;
import h2d.Bitmap;
import h2d.Tile;
import input.InputController;
import save.SaveSystem.GraphicsSettings;
import ui.FontManager;
import ui.components.UITheme;
import ui.components.UIEnums.MenuAction;
import ui.components.UIEnums.UIState;
import ui.components.UIEnums.OptionsTab;
import ui.components.CardBackplate;
import ui.views.splash.SplashView;
import ui.views.mainmenu.MainMenuView;
import ui.views.pause.PauseMenuView;
import ui.views.options.OptionsView;
import ui.views.credits.CreditsView;
import ui.components.TouchControlsHUD;

/**
 * Composite UI Builder orchestrating modal backplates and views.
 * Assembles and lays out the title splash, main menu, pause menu, options, and credits views.
 */
class UIBuilder extends Object {
    /** Semi-transparent full-viewport dimming curtain. */
    public var modalDimmer:Bitmap;

    /** Vector graphics context for drawing card backplates and active highlights. */
    public var cardBg:Graphics;

    /** Contextual navigation footer helper text label. */
    public var helpText:Text;

    /** Modular view panels. */
    public var splashView:SplashView;
    public var mainMenuView:MainMenuView;
    public var pauseMenuView:PauseMenuView;
    public var optionsView:OptionsView;
    public var creditsView:CreditsView;

    /** In-game virtual touch driving controls HUD overlay. */
    public var touchControlsHUD:TouchControlsHUD;

    /**
     * Instantiates the composite UI builder and creates all modular UI view layers.
     *
     * @param input Active input controller instance.
     * @param gfxSettings Current graphics configuration profile.
     * @param hasSave True if an active race save exists.
     * @param parent Optional parent 2D scene object.
     */
    public function new(input:InputController, gfxSettings:GraphicsSettings, hasSave:Bool, ?parent:Object) {
        super(parent);

        // 1. Fullscreen dimming modal curtain
        modalDimmer = new Bitmap(Tile.fromColor(0x000000, 1, 1, UITheme.ALPHA_MODAL_DIMMER), this);

        // 2. Vector graphics canvas for cyber frames and cards
        cardBg = new Graphics(this);

        // 3. Modular screen views
        splashView = new SplashView(this);
        mainMenuView = new MainMenuView(this);
        pauseMenuView = new PauseMenuView(this);
        optionsView = new OptionsView(input, gfxSettings, this);
        creditsView = new CreditsView(this);

        // 4. Mobile touch driving controls HUD
        touchControlsHUD = new TouchControlsHUD(input, this);
        touchControlsHUD.visible = false;

        // 5. Footer navigation hint text
        helpText = new Text(FontManager.regularFont, this);
        helpText.textColor = UITheme.COLOR_TEXT_MUTED;
    }

    /**
     * Renders card backplates and highlights for the current UI state.
     *
     * @param state Currently active UI state.
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function drawBackplates(state:UIState, sw:Float, sh:Float) {
        cardBg.clear();
        if (!cardBg.visible) return;

        cardBg.beginFill(UITheme.COLOR_CARD_BG, UITheme.ALPHA_CARD_SURFACE);
        cardBg.lineStyle(2.0, UITheme.COLOR_ACCENT_CYAN, UITheme.ALPHA_CARD_BORDER);

        switch (state) {
            case MainMenu:
                CardBackplate.drawMainMenu(cardBg, sw, sh, mainMenuView.selectedIndex);
            case PauseMenu:
                CardBackplate.drawPauseMenu(cardBg, sw, sh, pauseMenuView.selectedIndex);
            case OptionsMenu:
                var activeIdx = OptionsView.TAB_ORDER.indexOf(optionsView.currentTab);
                CardBackplate.drawOptionsMenu(cardBg, sw, sh, activeIdx, OptionsView.TAB_ORDER.length);
            case CreditsScreen:
                CardBackplate.drawCreditsScreen(cardBg, sw, sh);
            default:
        }
        cardBg.endFill();
    }

    /**
     * Recalculates positions and bounding boxes for all active views.
     *
     * @param state Active UI state.
     */
    public function layout(state:UIState) {
        var s2d = getScene();
        var sw:Float = s2d != null ? s2d.width : hxd.Window.getInstance().width;
        var sh:Float = s2d != null ? s2d.height : hxd.Window.getInstance().height;

        if (modalDimmer != null) {
            modalDimmer.scaleX = sw;
            modalDimmer.scaleY = sh;
        }

        drawBackplates(state, sw, sh);

        if (splashView != null && splashView.visible) splashView.layout(sw, sh);
        if (mainMenuView != null && mainMenuView.visible) mainMenuView.layout(sw, sh);
        if (pauseMenuView != null && pauseMenuView.visible) pauseMenuView.layout(sw, sh);
        if (optionsView != null && optionsView.visible) optionsView.layout(sw, sh);
        if (creditsView != null && creditsView.visible) creditsView.layout(sw, sh);
        if (touchControlsHUD != null && touchControlsHUD.visible) touchControlsHUD.layout(sw, sh);

        if (helpText != null) {
            helpText.x = (sw - helpText.textWidth) * 0.5;
            helpText.y = sh * 0.94;
        }
    }
}
