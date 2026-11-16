package ui;

import h2d.Object;
import input.InputController;
import net.MultiplayerManager;
import save.SaveSystem.GraphicsSettings;
import ui.components.UIEnums.MenuAction;
import ui.components.UIEnums.UIState;
import ui.components.UIEnums.OptionsTab;
import ui.UIBuilder;

/**
 * User interface manager, menu hierarchy, and modal coordinator.
 * Manages UI state machine, dispatches controller/touch navigation inputs to modular views,
 * and delegates visual element assembly and layout to `UIBuilder`.
 *
 * @class UIManager
 * @extends h2d.Object
 */
@:keep
class UIManager extends Object {
    /** Currently active UI state machine mode. */
    public var currentState:UIState = Splash;

    /** True if options modal was opened while in-game from pause menu. */
    public var isOpenedFromPause:Bool = false;

    /** Composite UI builder assembling modular view packages and backplates. */
    public var builder:UIBuilder;

    /** In-game cyber telemetry HUD overlay reference. */
    public var inGameHUD(get, never):ui.views.hud.InGameHUDView;
    inline function get_inGameHUD():ui.views.hud.InGameHUDView return builder.inGameHUDView;

    /** Callback invoked upon selecting a menu action. */
    public var onMenuAction:Null<MenuAction -> Void>;

    /** Optional callback invoked when pause is requested via touch HUD or pause shortcut. */
    public var onPauseRequested:Null<Void -> Void>;

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
     * @param mp Optional peer-to-peer multiplayer coordinator.
     */
    public function new(input:InputController, initialGfx:GraphicsSettings, hasSave:Bool, ?parent:Object, ?mp:MultiplayerManager) {
        super(parent);
        this.visible = false; // Stay hidden until finishIntroSequence() triggers
        this.inputRef = input;
        this.gfxSettings = initialGfx;
        this.hasActiveSave = hasSave;

        // Instantiate modular UI Builder
        builder = new UIBuilder(input, initialGfx, hasSave, this, mp);

        // Wire subview callbacks
        builder.splashView.onEnter = function() showMainMenu();
        builder.mainMenuView.onActionSelected = function(act) triggerMainAction(act);
        builder.mainMenuView.onSelectionChanged = function() layout();
        builder.mapSelectView.onMapSelected = function(act) {
            if (onMenuAction != null) onMenuAction(act);
        };
        builder.mapSelectView.onBack = function() showMainMenu();
        builder.mapSelectView.onSelectionChanged = function() layout();
        builder.multiplayerMenuView.onHostSelected = function() {
            if (mp != null) mp.hostRoom(null, "HOST");
            showMultiplayerLobby();
        };
        builder.multiplayerMenuView.onJoinSelected = function(code:String) {
            if (mp != null) mp.joinRoom(code, "GUEST");
            showMultiplayerLobby();
        };
        builder.multiplayerMenuView.onBack = function() showMainMenu();
        builder.multiplayerMenuView.onSelectionChanged = function() layout();
        builder.multiplayerLobbyView.onBack = function() {
            if (mp != null) mp.leaveRoom();
            showMultiplayerMenu();
        };
        builder.multiplayerLobbyView.onVisualRefresh = function() layout();
        builder.pauseMenuView.onResume = function() if (onMenuAction != null) onMenuAction(ResumeGame);
        builder.pauseMenuView.onRestart = function() if (onMenuAction != null) onMenuAction(RestartRace);
        builder.pauseMenuView.onOptions = function() openOptions(true);
        builder.pauseMenuView.onQuitToTitle = function() if (onMenuAction != null) onMenuAction(QuitToTitle);
        builder.pauseMenuView.onSelectionChanged = function() layout();
        builder.optionsView.onBack = function() {
            if (isOpenedFromPause) showPause();
            else showMainMenu();
        };
        builder.optionsView.onTabChanged = function() {
            if (currentState == OptionsMenu) layout();
        };
        builder.optionsView.gfxPanel.onUIResolutionChanged = function() {
            layout();
        };
        builder.creditsView.onBack = function() showMainMenu();
        builder.optionsView.controlsPanel.onTouchSettingsChanged = function() {
            builder.touchControlsHUD.refreshSettings();
        };
        builder.touchControlsHUD.onPauseTriggered = function() {
            if (currentState == InGameHUD) {
                if (onPauseRequested != null) onPauseRequested();
                else showPause();
            }
        };
    }

    function prepareTransition(state:UIState, showModalCard:Bool, ?helpMsg:String, resetTouch:Bool = true) {
        inputRef.flushInputs();
        currentState = state;

        builder.modalDimmer.visible = showModalCard;
        builder.cardBg.visible = showModalCard;
        builder.splashView.visible = false;
        builder.mainMenuView.visible = false;
        builder.mapSelectView.visible = false;
        builder.multiplayerMenuView.visible = false;
        builder.multiplayerLobbyView.visible = false;
        builder.pauseMenuView.visible = false;
        builder.optionsView.visible = false;
        builder.creditsView.visible = false;
        builder.inGameHUDView.visible = false;
        builder.touchControlsHUD.visible = false;

        if (resetTouch) {
            builder.touchControlsHUD.resetTouchStates();
        }

        if (helpMsg != null) {
            builder.helpText.text = helpMsg;
            builder.helpText.visible = true;
        } else {
            builder.helpText.visible = false;
        }
    }

    /**
     * Updates the active save run availability flag and re-styles the main menu items.
     *
     * @param {Bool} val True if a saved run is present.
     */
    public function setHasActiveSave(val:Bool) {
        hasActiveSave = val;
        builder.mainMenuView.setHasActiveSave(val);
    }

    /**
     * Reveals and transitions to the title splash screen.
     */
    public function showSplash() {
        this.visible = true;
        prepareTransition(Splash, false, null, false);
        builder.splashView.activate();
        layout();
    }

    /**
     * Activates the primary main menu screen with option cards and icons.
     */
    public function showMainMenu() {
        prepareTransition(MainMenu, true, "[Up / Down / D-Pad] Select    [A / Enter] Confirm", false);
        builder.mainMenuView.activate(hasActiveSave);
        layout();
    }

    /**
     * Activates the singleplayer map selection screen before starting a game session.
     */
    public function showMapSelect() {
        prepareTransition(MapSelect, true, "[Left / Right / Up / Down] Select Map    [A / Enter] Launch    [B / Esc] Back", false);
        builder.mapSelectView.activate();
        layout();
    }

    /**
     * Activates the peer-to-peer multiplayer Host-or-Join entry menu.
     */
    public function showMultiplayerMenu() {
        prepareTransition(MultiplayerMenu, true, "[Left / Right] Host or Join    [Type A-Z / 0-9] Invite Code    [A / Enter] Confirm    [B / Esc] Back", false);
        builder.multiplayerMenuView.activate();
        layout();
    }

    /**
     * Activates the peer-to-peer multiplayer staging lobby screen.
     */
    public function showMultiplayerLobby() {
        prepareTransition(MultiplayerLobby, true, "[Up / Down] Select Map    [A / Enter] Start Match (Host)    [B / Esc] Back", false);
        builder.multiplayerLobbyView.activate();
        layout();
    }

    /**
     * Hides modal overlays and transitions to the transparent in-game HUD.
     */
    public function showInGame() {
        prepareTransition(InGameHUD, false, null, true);
        builder.inGameHUDView.visible = true;
        builder.touchControlsHUD.visible = inputRef.isTouchActive;
        layout();
    }

    /**
     * Activates the in-run pause menu modal overlay.
     */
    public function showPause() {
        prepareTransition(PauseMenu, true, "[Up / Down] Select    [A / Enter] Confirm    [B / Esc] Resume", true);
        builder.pauseMenuView.activate();
        layout();
    }

    /**
     * Opens the options configuration modal.
     *
     * @param {Bool} fromPause True if opened during a race; disables in-run restricted options.
     */
    public function openOptions(fromPause:Bool) {
        isOpenedFromPause = fromPause;
        prepareTransition(OptionsMenu, true, "[LB / RB / Q / E] Switch Tabs    [Left / Right] Value    [B / Esc] Back", true);
        builder.optionsView.activate(fromPause);
        layout();
    }

    /**
     * Opens the credits and technical disclosures overlay.
     */
    public function showCredits() {
        prepareTransition(CreditsScreen, true, "[B / Esc / Enter] Return to Main Menu", true);
        builder.creditsView.activate();
        layout();
    }

    /**
     * Dispatches selected menu action.
     *
     * @param act Target action to execute.
     */
    function triggerMainAction(act:MenuAction) {
        switch (act) {
            case OpenMapSelect: showMapSelect();
            case OpenMultiplayer: if (onMenuAction != null) onMenuAction(OpenMultiplayer); else showMultiplayerMenu();
            case StartGame: if (onMenuAction != null) onMenuAction(StartGame);
            case StartSandbox: if (onMenuAction != null) onMenuAction(StartSandbox);
            case RestartRace: if (onMenuAction != null) onMenuAction(RestartRace);
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
        } else if (currentState == MapSelect) {
            if (uiLeft || uiUp) builder.mapSelectView.navigate(-1);
            else if (uiRight || uiDown) builder.mapSelectView.navigate(1);
            if (uiConfirm) builder.mapSelectView.confirmSelection();
            else if (uiCancel) showMainMenu();
        } else if (currentState == MultiplayerMenu) {
            var mpMenu = builder.multiplayerMenuView;
            var navLeft = uiLeft || uiUp;
            var navRight = uiRight || uiDown;
            if (mpMenu.shouldCaptureWasdAsText()) {
                var allowArrowOrPadLeft = hxd.Key.isDown(hxd.Key.LEFT) || hxd.Key.isDown(hxd.Key.UP) || !(hxd.Key.isDown(hxd.Key.A) || hxd.Key.isDown(hxd.Key.W));
                var allowArrowOrPadRight = hxd.Key.isDown(hxd.Key.RIGHT) || hxd.Key.isDown(hxd.Key.DOWN) || !(hxd.Key.isDown(hxd.Key.D) || hxd.Key.isDown(hxd.Key.S));
                navLeft = navLeft && allowArrowOrPadLeft;
                navRight = navRight && allowArrowOrPadRight;
            }
            if (navLeft) mpMenu.navigate(-1);
            else if (navRight) mpMenu.navigate(1);
            if (uiConfirm) mpMenu.confirmSelection();
            else if (uiCancel && !mpMenu.consumeBackspaceCancel()) showMainMenu();
        } else if (currentState == MultiplayerLobby) {
            builder.multiplayerLobbyView.updateTimer(dt);
            if (uiLeft || uiUp) builder.multiplayerLobbyView.navigate(-1);
            else if (uiRight || uiDown) builder.multiplayerLobbyView.navigate(1);
            if (uiConfirm) builder.multiplayerLobbyView.confirmFocused();
            else if (uiCancel) {
                if (builder.multiplayerLobbyView.onBack != null) builder.multiplayerLobbyView.onBack();
                else showMainMenu();
            }
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
                if (uiRight || uiConfirm) opt.audioPanel.adjustVolume(opt.audioPanel.selectedIndex, 0.1);
            } else {
                if (opt.controlsPanel.controlViewMode == "Custom") {
                    if (uiUp) opt.controlsPanel.navigate(-1);
                    else if (uiDown) opt.controlsPanel.navigate(1);
                    if (uiLeft) opt.controlsPanel.adjustCurrentCustomOption(-1);
                    if (uiRight) opt.controlsPanel.adjustCurrentCustomOption(1);
                    if (uiConfirm) opt.controlsPanel.triggerRemapEntry(opt.controlsPanel.remapIndex);
                } else {
                    if (uiLeft) opt.controlsPanel.adjustSensitivity(-0.02);
                    if (uiRight) opt.controlsPanel.adjustSensitivity(0.02);
                    if (uiConfirm) opt.controlsPanel.toggleCustomMode();
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