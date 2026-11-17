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
        Assert.equals(6, ui.builder.mainMenuView.rows.length);
        Assert.equals("PLAY SINGLEPLAYER", ui.builder.mainMenuView.rows[0].labelTxt.text);
        Assert.equals("MULTIPLAYER LOBBY", ui.builder.mainMenuView.rows[2].labelTxt.text);
        Assert.equals(MenuAction.OpenMapSelect, MainMenuView.ACTIONS[0]);
        Assert.equals(MenuAction.OpenMultiplayer, MainMenuView.ACTIONS[2]);
    }

    public function testPlaySingleplayerOpensMapSelect() {
        ui.showMainMenu();
        ui.builder.mainMenuView.selectedIndex = 0;
        ui.builder.mainMenuView.confirmSelection();

        Assert.equals(UIState.MapSelect, ui.currentState, "Confirming Play Singleplayer should transition to MapSelect state");
        Assert.isTrue(ui.builder.mapSelectView.visible, "MapSelectView should be visible");
        Assert.isFalse(ui.builder.mainMenuView.visible, "MainMenuView should be hidden");
    }

    public function testMapSelectionOpensCarSelectWithThreeCarsAndPaintPicker() {
        var launchedMode:Null<world.WorldManager.MapMode> = null;
        var launchedCar:String = "";
        var launchedHex:Int = 0;
        ui.onCarLaunch = function(mode, cid, chex) {
            launchedMode = mode;
            launchedCar = cid;
            launchedHex = chex;
        };

        // MapSelect index 0 -> opens CarSelect targeting Circuit
        ui.showMapSelect();
        Assert.equals(0, ui.builder.mapSelectView.selectedIndex);
        ui.builder.mapSelectView.confirmSelection();
        Assert.equals(UIState.CarSelect, ui.currentState);
        Assert.equals(world.WorldManager.MapMode.Circuit, ui.builder.carSelectView.targetMap);

        // Select Sports Hatch (FWD) and Cobalt Blue paint swatch (index 4)
        ui.builder.carSelectView.selectCar(1);
        ui.builder.carSelectView.selectColor(4);
        ui.builder.carSelectView.confirmSelection();
        Assert.equals(world.WorldManager.MapMode.Circuit, launchedMode);
        Assert.equals(physics.CarConfig.ID_HATCH_FWD, launchedCar);
        Assert.equals(physics.CarConfig.PAINT_PALETTE[4].hex, launchedHex);

        // Back from CarSelect returns to MapSelect; index 1 -> CarSelect targeting Sandbox + Low Coupe RWD
        ui.showMapSelect();
        ui.builder.mapSelectView.navigate(1);
        Assert.equals(1, ui.builder.mapSelectView.selectedIndex);
        ui.builder.mapSelectView.confirmSelection();
        Assert.equals(UIState.CarSelect, ui.currentState);
        Assert.equals(world.WorldManager.MapMode.Sandbox, ui.builder.carSelectView.targetMap);

        ui.builder.carSelectView.onBack();
        Assert.equals(UIState.MapSelect, ui.currentState);
        ui.builder.mapSelectView.confirmSelection();
        ui.builder.carSelectView.selectCar(2);
        ui.builder.carSelectView.confirmSelection();
        Assert.equals(world.WorldManager.MapMode.Sandbox, launchedMode);
        Assert.equals(physics.CarConfig.ID_COUPE_RWD, launchedCar);
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

