package ui;

import h2d.Object;
import input.InputController;
import save.SaveSystem.GraphicsSettings;
import ui.components.UIEnums.MenuAction;
import ui.components.UIEnums.UIState;
import ui.components.UIEnums.OptionsTab;
import ui.UIBuilder;

/**
 * User interface manager, menu hierarchy, and modal coordinator.
 * Manages UI state machine, dispatches controller/touch navigation inputs to modular views,
 * and delegates visual element assembly and layout to `UIBuilder`.
 */
class UIManager extends Object {
    /** Currently active UI state machine mode. */
    public var currentState:UIState = Splash;

    /** True if options modal was opened while in-game from pause menu. */
    public var isOpenedFromPause:Bool = false;

    /** Composite UI builder assembling modular view packages and backplates. */
    public var builder:UIBuilder;

    /** Callback invoked upon selecting a menu action. */
    public var onMenuAction:MenuAction->Void;

    /** Reference to active input controller. */
    var inputRef:InputController;

    /** Active graphics hardware configuration profile. */
    public var gfxSettings:GraphicsSettings;

    /** True if an active race save exists. */
    public var hasActiveSave:Bool = false;

    /**
     * Constructs the user interface manager and initializes the underlying UI builder.
     *
     * @param input Reference to the active input controller.
     * @param initialGfx Current graphics settings profile.
     * @param hasSave True if an in-progress race run is available to resume.
     * @param parent Optional parent 2D scene graph node.
     */
    public function new(input:InputController, initialGfx:GraphicsSettings, hasSave:Bool, ?parent:Object) {
        super(parent);
        this.visible = false; // Stay hidden until finishIntroSequence() triggers
        this.inputRef = input;
        this.gfxSettings = initialGfx;
        this.hasActiveSave = hasSave;

        // Instantiate modular UI Builder
        builder = new UIBuilder(input, initialGfx, hasSave, this);

        // Wire subview callbacks
        builder.splashView.onEnter = function() showMainMenu();
        builder.mainMenuView.onActionSelected = function(act) triggerMainAction(act);
        builder.pauseMenuView.onResume = function() if (onMenuAction != null) onMenuAction(ResumeGame);
        builder.pauseMenuView.onRestart = function() if (onMenuAction != null) onMenuAction(StartGame);
        builder.pauseMenuView.onOptions = function() openOptions(true);
        builder.pauseMenuView.onQuitToTitle = function() if (onMenuAction != null) onMenuAction(QuitToTitle);
        builder.optionsView.onBack = function() {
            if (isOpenedFromPause) showPause();
            else showMainMenu();
        };
        builder.optionsView.gfxPanel.onUIResolutionChanged = function() {
            layout();
        };
        builder.creditsView.onBack = function() showMainMenu();
        builder.touchControlsHUD.onPauseTriggered = function() {
            if (currentState == InGameHUD) {
                showPause();
            }
        };
    }

    /**
     * Updates the active save run availability flag and re-styles the main menu items.
     *
     * @param val True if a saved run is present.
     */
    public function setHasActiveSave(val:Bool) {
        hasActiveSave = val;
        builder.mainMenuView.setHasActiveSave(val);
    }

    /**
     * Reveals and transitions to the title splash screen.
     */
    public function showSplash() {
        this.visible = true; // Reveal UI container
        inputRef.flushInputs();
        currentState = Splash;

        builder.modalDimmer.visible = false;
        builder.cardBg.visible = false;
        builder.splashView.activate();
        builder.mainMenuView.visible = false;
        builder.pauseMenuView.visible = false;
        builder.optionsView.visible = false;
        builder.creditsView.visible = false;
        builder.touchControlsHUD.visible = false;
        builder.helpText.visible = false;

        layout();
    }

    /**
     * Activates the primary main menu screen with option cards and icons.
     */
    public function showMainMenu() {
        inputRef.flushInputs();
        currentState = MainMenu;

        builder.modalDimmer.visible = true;
        builder.cardBg.visible = true;
        builder.splashView.visible = false;
        builder.mainMenuView.activate(hasActiveSave);
        builder.pauseMenuView.visible = false;
        builder.optionsView.visible = false;
        builder.creditsView.visible = false;
        builder.touchControlsHUD.visible = false;

        builder.helpText.text = "[Up / Down / D-Pad] Select    [A / Enter] Confirm";
        builder.helpText.visible = true;

        layout();
    }

    /**
     * Hides modal overlays and transitions to the transparent in-game HUD.
     */
    public function showInGame() {
        inputRef.flushInputs();
        currentState = InGameHUD;

        builder.modalDimmer.visible = false;
        builder.cardBg.visible = false;
        builder.splashView.visible = false;
        builder.mainMenuView.visible = false;
        builder.pauseMenuView.visible = false;
        builder.optionsView.visible = false;
        builder.creditsView.visible = false;
        builder.helpText.visible = false;

        // Auto-show touch controls if device has touch capability or touch was registered
        builder.touchControlsHUD.visible = inputRef.isTouchActive;
        builder.touchControlsHUD.resetTouchStates();
        layout();
    }

    /**
     * Activates the in-run pause menu modal overlay.
     */
    public function showPause() {
        inputRef.flushInputs();
        currentState = PauseMenu;

        builder.modalDimmer.visible = true;
        builder.cardBg.visible = true;
        builder.splashView.visible = false;
        builder.mainMenuView.visible = false;
        builder.pauseMenuView.activate();
        builder.optionsView.visible = false;
        builder.creditsView.visible = false;
        builder.touchControlsHUD.visible = false;
        builder.touchControlsHUD.resetTouchStates();

        builder.helpText.text = "[Up / Down] Select    [A / Enter] Confirm    [B / Esc] Resume";
        builder.helpText.visible = true;

        layout();
    }

    /**
     * Opens the options configuration modal.
     *
     * @param fromPause True if opened during a race; disables in-run restricted options.
     */
    public function openOptions(fromPause:Bool) {
        inputRef.flushInputs();
        currentState = OptionsMenu;
        isOpenedFromPause = fromPause;

        builder.modalDimmer.visible = true;
        builder.cardBg.visible = true;
        builder.splashView.visible = false;
        builder.mainMenuView.visible = false;
        builder.pauseMenuView.visible = false;
        builder.optionsView.activate(fromPause);
        builder.creditsView.visible = false;
        builder.touchControlsHUD.visible = false;
        builder.touchControlsHUD.resetTouchStates();

        builder.helpText.text = "[LB / RB / Q / E] Switch Tabs    [Left / Right] Value    [B / Esc] Back";
        builder.helpText.visible = true;

        layout();
    }

    /**
     * Opens the credits and technical disclosures overlay.
     */
    public function showCredits() {
        inputRef.flushInputs();
        currentState = CreditsScreen;

        builder.modalDimmer.visible = true;
        builder.cardBg.visible = true;
        builder.splashView.visible = false;
        builder.mainMenuView.visible = false;
        builder.pauseMenuView.visible = false;
        builder.optionsView.visible = false;
        builder.creditsView.activate();
        builder.touchControlsHUD.visible = false;
        builder.touchControlsHUD.resetTouchStates();

        builder.helpText.text = "[B / Esc / Enter] Return to Main Menu";
        builder.helpText.visible = true;

        layout();
    }

    /**
     * Dispatches selected menu action.
     *
     * @param act Target action to execute.
     */
    function triggerMainAction(act:MenuAction) {
        switch (act) {
            case StartGame: if (onMenuAction != null) onMenuAction(StartGame);
            case ResumeGame: if (hasActiveSave && onMenuAction != null) onMenuAction(ResumeGame);
            case OpenOptions: openOptions(false);
            case OpenCredits: showCredits();
            case QuitToTitle: showSplash();
        }
    }

    /**
     * Updates UI input processing, prompt animations, and menu navigation.
     *
     * @param dt Delta time in seconds.
     * @param uiUp Up directional navigation impulse.
     * @param uiDown Down directional navigation impulse.
     * @param uiLeft Left value decrement impulse.
     * @param uiRight Right value increment impulse.
     * @param uiConfirm Confirmation select impulse.
     * @param uiCancel Cancel or back return impulse.
     */
    public function update(dt:Float, uiUp:Bool, uiDown:Bool, uiLeft:Bool, uiRight:Bool, uiConfirm:Bool, uiCancel:Bool) {
        if (currentState == Splash) {
            builder.splashView.update(dt, inputRef.anyKeyPressed);
            return;
        }

        if (currentState == MainMenu) {
            if (uiUp) builder.mainMenuView.navigate(-1);
            else if (uiDown) builder.mainMenuView.navigate(1);
            if (uiConfirm) builder.mainMenuView.confirmSelection();
        } else if (currentState == PauseMenu) {
            if (uiUp) builder.pauseMenuView.navigate(-1);
            else if (uiDown) builder.pauseMenuView.navigate(1);
            if (uiConfirm) builder.pauseMenuView.confirmSelection();
            else if (uiCancel) {
                if (onMenuAction != null) onMenuAction(ResumeGame);
            }
        } else if (currentState == OptionsMenu) {
            if (inputRef.tabPrevPressed) {
                builder.optionsView.cycleTab(-1);
            } else if (inputRef.tabNextPressed) {
                builder.optionsView.cycleTab(1);
            }

            var opt = builder.optionsView;
            if (opt.currentTab == Graphics) {
                if (uiUp) opt.gfxPanel.navigate(-1);
                else if (uiDown) opt.gfxPanel.navigate(1);
                if (uiLeft) opt.gfxPanel.cycleOption(opt.gfxPanel.selectedIndex, -1);
                if (uiRight || uiConfirm) opt.gfxPanel.cycleOption(opt.gfxPanel.selectedIndex, 1);
            } else if (opt.currentTab == Audio) {
                if (uiUp) opt.audioPanel.navigate(-1);
                else if (uiDown) opt.audioPanel.navigate(1);
                if (uiLeft) opt.audioPanel.adjustVolume(opt.audioPanel.selectedIndex, -0.1);
                if (uiRight) opt.audioPanel.adjustVolume(opt.audioPanel.selectedIndex, 0.1);
            } else {
                if (opt.controlsPanel.controlViewMode == "Custom") {
                    if (uiUp) opt.controlsPanel.navigate(-1);
                    else if (uiDown) opt.controlsPanel.navigate(1);
                    if (uiConfirm) opt.controlsPanel.triggerRemapEntry(opt.controlsPanel.remapIndex);
                }
            }

            if (uiCancel) {
                if (isOpenedFromPause) showPause();
                else showMainMenu();
            }
        } else if (currentState == CreditsScreen) {
            if (uiCancel || uiConfirm) showMainMenu();
        } else if (currentState == InGameHUD) {
            if (inputRef.isTouchActive && !builder.touchControlsHUD.visible) {
                builder.touchControlsHUD.visible = true;
                layout();
            }
        }
    }

    /**
     * Recalculates responsive viewport coordinates, modal dimensions, and element alignments.
     */
    public function layout() {
        builder.layout(currentState);
    }
}