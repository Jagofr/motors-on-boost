package tests.ui;

import utest.Test;
import utest.Assert;
import audio.AudioManager;
import input.InputController;
import input.InputController.ExclusiveDevice;
import save.SaveSystem;
import ui.FontManager;
import ui.UIManager;
import ui.components.UIEnums.MenuAction;
import ui.components.UIEnums.OptionsTab;
import ui.components.UIEnums.UIState;

/**
 * Unit test suite exercising all Main Menu entries, all Options tabs & subcontrols,
 * Pause Menu transitions, and touch pause callback routing.
 */
class TestFullMenuAndOptionsFlow extends Test {
    var input:InputController;
    var ui:UIManager;
    var emittedActions:Array<MenuAction>;
    var pauseRequests:Int;

    public function setup() {
        FontManager.init();
        new AudioManager();
        input = new InputController();
        ui = new UIManager(input, SaveSystem.getDefaultGraphics(), false, null);
        emittedActions = [];
        pauseRequests = 0;
        ui.onMenuAction = function(act) emittedActions.push(act);
        ui.onPauseRequested = function() {
            pauseRequests++;
            ui.showPause();
        };
    }

    public function testAllMainMenuButtons() {
        // 0: PLAY SINGLEPLAYER -> MapSelect
        ui.showMainMenu();
        ui.builder.mainMenuView.selectedIndex = 0;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(UIState.MapSelect, ui.currentState);

        // 1: RESUME SAVED RACE (blocked without active save, active with save)
        ui.showMainMenu();
        ui.builder.mainMenuView.selectedIndex = 1;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(0, emittedActions.length, "Resume must not trigger when hasActiveSave is false");

        ui.setHasActiveSave(true);
        ui.builder.mainMenuView.selectedIndex = 1;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(MenuAction.ResumeGame, emittedActions[0]);

        // 2: MULTIPLAYER LOBBY -> OpenMultiplayer
        ui.showMainMenu();
        ui.builder.mainMenuView.selectedIndex = 2;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(MenuAction.OpenMultiplayer, emittedActions[1]);

        // 3: OPTIONS -> OptionsMenu
        ui.showMainMenu();
        ui.builder.mainMenuView.selectedIndex = 3;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(UIState.OptionsMenu, ui.currentState);
        Assert.isFalse(ui.isOpenedFromPause);

        // Back -> MainMenu
        ui.builder.optionsView.onBack();
        Assert.equals(UIState.MainMenu, ui.currentState);

        // 4: CREDITS -> CreditsScreen -> Back -> MainMenu
        ui.builder.mainMenuView.selectedIndex = 4;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(UIState.CreditsScreen, ui.currentState);
        ui.builder.creditsView.onBack();
        Assert.equals(UIState.MainMenu, ui.currentState);

        // 5: EXIT TO SPLASH -> Splash
        ui.builder.mainMenuView.selectedIndex = 5;
        ui.builder.mainMenuView.confirmSelection();
        Assert.equals(UIState.Splash, ui.currentState);
    }

    public function testAllOptionsTabsAndControls() {
        ui.openOptions(false);
        var opt = ui.builder.optionsView;
        Assert.equals(OptionsTab.Graphics, opt.currentTab);

        // Cycle every tab via switchTab & verify active panel visibility
        opt.switchTab(OptionsTab.Audio);
        Assert.isTrue(opt.audioPanel.visible);
        Assert.isFalse(opt.gfxPanel.visible);
        Assert.isFalse(opt.controlsPanel.visible);

        opt.audioPanel.adjustVolume(0, -0.1);
        Assert.isTrue(AudioManager.inst.masterVolume < 0.8);

        for (tab in [OptionsTab.Keyboard, OptionsTab.Gamepad, OptionsTab.Touch]) {
            opt.switchTab(tab);
            Assert.isTrue(opt.controlsPanel.visible, "Controls panel must be visible on " + tab);
            Assert.equals(tab, opt.controlsPanel.currentTab);

            opt.controlsPanel.toggleCustomMode();
            Assert.equals("Custom", opt.controlsPanel.controlViewMode);
            opt.controlsPanel.toggleCustomMode();
            Assert.equals("Diagram", opt.controlsPanel.controlViewMode);
        }

        // Verify exclusive device toggle works on Keyboard/Gamepad
        opt.switchTab(OptionsTab.Keyboard);
        opt.controlsPanel.toggleExclusiveDevice();
        Assert.equals(ExclusiveDevice.KeyboardOnly, input.exclusiveDevice);
        opt.controlsPanel.toggleExclusiveDevice();
        Assert.equals(ExclusiveDevice.Both, input.exclusiveDevice);
    }

    public function testTouchPauseCallbackAndAllPauseMenuButtons() {
        ui.showInGame();
        ui.builder.touchControlsHUD.onPauseTriggered();
        Assert.equals(1, pauseRequests);
        Assert.equals(UIState.PauseMenu, ui.currentState);

        // 0: RESUME SESSION
        ui.builder.pauseMenuView.selectedIndex = 0;
        ui.builder.pauseMenuView.confirmSelection();
        Assert.equals(MenuAction.ResumeGame, emittedActions[0]);

        // 1: RESTART MAP
        ui.builder.pauseMenuView.selectedIndex = 1;
        ui.builder.pauseMenuView.confirmSelection();
        Assert.equals(MenuAction.RestartRace, emittedActions[1]);

        // 2: OPTIONS (fromPause = true)
        ui.builder.pauseMenuView.selectedIndex = 2;
        ui.builder.pauseMenuView.confirmSelection();
        Assert.equals(UIState.OptionsMenu, ui.currentState);
        Assert.isTrue(ui.isOpenedFromPause);

        // Back from Pause Options -> PauseMenu
        ui.builder.optionsView.onBack();
        Assert.equals(UIState.PauseMenu, ui.currentState);

        // 3: MAIN MENU
        ui.builder.pauseMenuView.selectedIndex = 3;
        ui.builder.pauseMenuView.confirmSelection();
        Assert.equals(MenuAction.QuitToTitle, emittedActions[2]);
    }
}
