package tests.ui;

import utest.Test;
import utest.Assert;
import ui.FontManager;
import ui.components.TouchControlsHUD;
import ui.views.options.ControlsOptionsPanel;
import input.InputController;
import save.SaveSystem;

/**
 * Unit test suite validating touch button coordinates, custom offsets,
 * multi-touch concurrency, and ControlsOptionsPanel touch tab remapping.
 */
class TestTouchControls extends Test {
    var input:InputController;
    var hud:TouchControlsHUD;
    var controlsPanel:ControlsOptionsPanel;

    public function setup() {
        FontManager.init();
        new audio.AudioManager();
        input = new InputController();
        hud = new TouchControlsHUD(input, null);
        controlsPanel = new ControlsOptionsPanel(input, null);
    }

    public function testDefaultLayoutCoordinates() {
        hud.layout(1280, 720);

        Assert.isTrue(hud.stickBaseX > 0 && hud.stickBaseX < 200, "Stick base X in lower-left");
        Assert.isTrue(hud.stickBaseY > 500 && hud.stickBaseY < 720, "Stick base Y in lower-left");

        Assert.isTrue(hud.gasX > 1000 && hud.gasX <= 1280, "Gas pedal in lower-right");
        Assert.isTrue(hud.gasY > 500 && hud.gasY <= 720, "Gas pedal in lower-right");

        Assert.isTrue(hud.brakeX > 900 && hud.brakeX < 1200, "Brake in upper-right");
        Assert.isTrue(hud.brakeY > 50 && hud.brakeY < 200, "Brake in upper-right");

        Assert.isTrue(hud.driftX > 1100 && hud.driftX <= 1280, "Drift in mid-right");
        Assert.isTrue(hud.driftY > 180 && hud.driftY < 350, "Drift in mid-right");

        Assert.isTrue(hud.nitroX > 50 && hud.nitroX < 200, "Nitro in mid-left");
    }

    public function testCustomOffsetsAndScaleApplication() {
        var baseHud = new TouchControlsHUD(input, null);
        baseHud.layout(1280, 720);
        var baseGasX = baseHud.gasX;

        // Apply custom touch settings
        var custom = SaveSystem.getDefaultTouchSettings();
        custom.mode = "Custom";
        custom.scale = 1.2;
        custom.gasOffsetX = 25.0;
        custom.gasOffsetY = -15.0;

        hud.touchSettings = custom;
        hud.layout(1280, 720);

        Assert.floatEquals(baseGasX + 25.0, hud.gasX, 0.01, "Gas X should shift by +25px");
        Assert.floatEquals(48.0 * 1.2, hud.gasRadius, 0.01, "Gas radius should scale by 1.2x");
    }

    public function testMultiTouchConcurrency() {
        hud.layout(1280, 720);

        // Finger 1 presses Gas Pedal
        hud.handlePointerDown(1, hud.gasX, hud.gasY);
        Assert.isTrue(hud.isGasPressed);
        Assert.floatEquals(1.0, input.touchThrottle, 0.001);

        // Finger 2 simultaneously presses Nitro Button
        hud.handlePointerDown(2, hud.nitroX, hud.nitroY);
        Assert.isTrue(hud.isGasPressed, "Gas must remain active when Nitro is pressed");
        Assert.isTrue(hud.isBoostPressed, "Nitro must be active");
        Assert.isTrue(input.touchBoost, "Controller touchBoost must register");

        // Finger 3 simultaneously presses Brake Button (Brake + Nitro chord)
        hud.handlePointerDown(3, hud.brakeX, hud.brakeY);
        Assert.isTrue(hud.isBrakePressed, "Brake must be active");
        Assert.isTrue(hud.isBoostPressed, "Nitro must remain active during multi-touch");

        // Release Gas (Finger 1)
        hud.handlePointerUp(1);
        Assert.isFalse(hud.isGasPressed, "Gas should release");
        Assert.isTrue(hud.isBoostPressed, "Nitro must still remain active after Gas release");
        Assert.isTrue(hud.isBrakePressed, "Brake must still remain active after Gas release");

        // Reset
        hud.resetTouchStates();
        Assert.isFalse(hud.isBoostPressed);
        Assert.isFalse(hud.isBrakePressed);
        Assert.floatEquals(0.0, input.touchThrottle, 0.001);
    }

    public function testControlsPanelTouchCustomAdjustments() {
        controlsPanel.currentTab = Touch;
        controlsPanel.controlViewMode = "Custom";
        controlsPanel.updateControlViewMode();

        Assert.equals(12, controlsPanel.getMaxRemapCount());

        // Adjust index 0 (stickOffsetX)
        controlsPanel.remapIndex = 0;
        controlsPanel.adjustCurrentCustomOption(1); // +5px
        var d = SaveSystem.load();
        Assert.isTrue(d.touchSettings.stickOffsetX != 0.0);

        // Reset defaults (index 11)
        controlsPanel.triggerRemapEntry(11);
        var resetData = SaveSystem.load();
        Assert.floatEquals(0.0, resetData.touchSettings.stickOffsetX, 0.001);
    }

    public function testPersistentSensitivitySliderAcrossTabs() {
        controlsPanel.adjustSensitivity(0.04);
        var sens = input.steerSensitivity;
        Assert.isTrue(sens > 0.0 && sens <= 1.0);

        // Sensitivity should remain active when switching tabs
        controlsPanel.currentTab = Keyboard;
        controlsPanel.updateControlHeaderButtons();
        Assert.floatEquals(sens, input.steerSensitivity, 0.001);

        controlsPanel.currentTab = Gamepad;
        controlsPanel.updateControlHeaderButtons();
        Assert.floatEquals(sens, input.steerSensitivity, 0.001);

        controlsPanel.currentTab = Touch;
        controlsPanel.updateControlHeaderButtons();
        Assert.floatEquals(sens, input.steerSensitivity, 0.001);
    }
}

