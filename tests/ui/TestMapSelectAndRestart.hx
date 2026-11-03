package tests.ui;

import utest.Test;
import utest.Assert;
import ui.FontManager;
import ui.UIManager;
import ui.components.UIEnums.MenuAction;
import ui.components.UIEnums.UIState;
import ui.views.mainmenu.MainMenuView;
import ui.views.mapselect.MapSelectView;
import input.InputController;
import save.SaveSystem;

/**
 * Unit test suite validating MainMenu -> MapSelect navigation flow,
 * singleplayer map selection, and pause menu RestartRace dispatching.
 */
class TestMapSelectAndRestart extends Test {
    var input:InputController;
    var ui:UIManager;
    var lastAction:Null<MenuAction>;

    public function setup() {
        FontManager.init();
        new audio.AudioManager();
        input = new InputController();
        var s = SaveSystem.getDefaultGraphics();
        ui = new UIManager(input, s, false, null);
        lastAction = null;
        ui.onMenuAction = function(act) {
            lastAction = act;
        };
    }

    public function testMainMenuFirstItemIsPlaySingleplayer() {
        ui.showMainMenu();
        Assert.equals(UIState.MainMenu, ui.currentState);
        Assert.equals(5, ui.builder.mainMenuView.rows.length);
        Assert.equals("PLAY SINGLEPLAYER", ui.builder.mainMenuView.rows[0].labelTxt.text);
        Assert.equals(MenuAction.OpenMapSelect, MainMenuView.ACTIONS[0]);
    }

    public function testPlaySingleplayerOpensMapSelect() {
        ui.showMainMenu();
        ui.builder.mainMenuView.selectedIndex = 0;
        ui.builder.mainMenuView.confirmSelection();

        Assert.equals(UIState.MapSelect, ui.currentState, "Confirming Play Singleplayer should transition to MapSelect state");
        Assert.isTrue(ui.builder.mapSelectView.visible, "MapSelectView should be visible");
        Assert.isFalse(ui.builder.mainMenuView.visible, "MainMenuView should be hidden");
    }

    public function testMapSelectionDispatchesCircuitAndSandbox() {
        ui.showMapSelect();
        Assert.equals(0, ui.builder.mapSelectView.selectedIndex);

        // Confirm index 0 -> Highway Circuit (StartGame)
        ui.builder.mapSelectView.confirmSelection();
        Assert.equals(MenuAction.StartGame, lastAction);

        // Navigate to index 1 -> Sandbox Proving Grounds (StartSandbox)
        ui.builder.mapSelectView.navigate(1);
        Assert.equals(1, ui.builder.mapSelectView.selectedIndex);
        ui.builder.mapSelectView.confirmSelection();
        Assert.equals(MenuAction.StartSandbox, lastAction);
    }

    public function testPauseMenuRestartEmitsRestartRace() {
        ui.showPause();
        Assert.equals(UIState.PauseMenu, ui.currentState);

        // Index 1 is "RESTART MAP"
        ui.builder.pauseMenuView.selectedIndex = 1;
        ui.builder.pauseMenuView.confirmSelection();

        Assert.equals(MenuAction.RestartRace, lastAction, "Pause menu restart must emit RestartRace so active map is preserved");
    }
}

