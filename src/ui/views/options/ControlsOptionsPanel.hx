package ui.views.options;

import h2d.Object;
import h2d.Text;
import h2d.Interactive;
import ui.FontManager;
import ui.ControlDiagrams;
import ui.components.UITheme;
import ui.components.UIEnums.OptionsTab;
import input.InputController;
import input.InputController.InputAction;
import input.InputController.ExclusiveDevice;
import audio.AudioManager;
import save.SaveSystem;
import save.SaveSystem.TouchSettings;

/**
 * Controller, keyboard, and touch screen configuration, schematic diagrams,
 * and custom action / button remapping subpanel.
 * Features an independent persistent steering sensitivity slider active across all control modes.
 */
@:keep
class ControlsOptionsPanel extends Object {
    /** Alias for persistent sensitivity row container. */
    public var sensitivityRow:Object;

    /** Convenience alias returning the touch layout diagram viewer. */
    public var touchDiagram:Object;

    /** Convenience alias returning the custom touch adjustment list container. */
    public var customTouchList:Object;

    /** Container holding persistent sensitivity slider elements. */
    public var sensContainer:Object;

    /** Steering sensitivity text label display. */
    public var sensLabel:Text;

    /** Decrement sensitivity button text label. */
    public var sensDecrBtn:Text;

    /** Interactive hitzone for decrementing sensitivity. */
    public var sensDecrInter:Interactive;

    /** Increment sensitivity button text label. */
    public var sensIncrBtn:Text;

    /** Interactive hitzone for incrementing sensitivity. */
    public var sensIncrInter:Interactive;

    /** Interactive hitzone covering the entire sensitivity row for easy clicking. */
    public var sensRowInter:Interactive;

    // =========================================================================
    // HEADER CONTROLS (EXCLUSIVE HARDWARE & VIEW MODE)
    // =========================================================================

    /** Toggle exclusive hardware device button. */
    public var toggleExclusiveBtn:Text;
    public var toggleExclusiveInter:Interactive;

    /** Toggle schematic diagram vs custom remapping button. */
    public var toggleViewModeBtn:Text;
    public var toggleViewModeInter:Interactive;

    // =========================================================================
    // CONTENT CONTAINERS
    // =========================================================================

    /** Vector schematic diagram canvas. */
    public var diagramViewer:ControlDiagrams;

    /** Container holding interactive remapping list rows. */
    public var remapContainer:Object;

    /** Remapping row items text labels. */
    public var remapItems:Array<Text> = [];

    /** Remapping interactive hitzones. */
    public var remapInteractives:Array<Interactive> = [];

    /** Currently highlighted remapping item index. */
    public var remapIndex:Int = 0;

    /** Status notice text shown when waiting for remapping input. */
    public var remapStatusNotice:Text;

    /** Active view mode ("Diagram" or "Custom"). */
    public var controlViewMode:String = "Diagram";

    /** Reference to active input controller. */
    public var inputRef:InputController;

    /** Currently selected options tab. */
    public var currentTab:OptionsTab = Keyboard;

    /** Callback invoked whenever touch control settings are modified. */
    public var onTouchSettingsChanged:Void->Void;

    /** Interactive remapping row hitzone width in pixels. */
    public static inline var REMAP_ROW_WIDTH:Float = 540.0;

    /** Interactive remapping row hitzone height in pixels. */
    public static inline var REMAP_ROW_HEIGHT:Float = 26.0;

    /** Vertical spacing between successive remapping list rows in pixels. */
    public static inline var REMAP_ROW_STRIDE:Float = 27.0;

    /** Maximum customizable items (supports up to 12 touch configuration rows). */
    public static inline var MAX_REMAP_ITEMS:Int = 12;

    /**
     * Instantiates the controls and hardware options subpanel.
     *
     * @param input Input controller reference.
     * @param parent Optional parent 2D scene object.
     */
    public function new(input:InputController, ?parent:Object) {
        super(parent);
        this.inputRef = input;

        // 1. General Steering Sensitivity Row
        sensContainer = new Object(this);

        sensDecrBtn = new Text(FontManager.regularFont, sensContainer);
        sensDecrBtn.text = "[ < -2% ]";
        sensDecrBtn.textColor = UITheme.COLOR_ACCENT_CYAN;
        sensDecrInter = new Interactive(80, 28, sensContainer);
        sensDecrInter.onClick = function(_) adjustSensitivity(-0.02);

        sensLabel = new Text(FontManager.regularFont, sensContainer);
        sensLabel.textColor = UITheme.COLOR_TEXT_NORMAL;

        sensRowInter = new Interactive(320, 28, sensContainer);
        sensRowInter.onClick = function(_) {
            // Cycle sensitivity by +2% or wrap around
            var next = inputRef.steerSensitivity >= 0.99 ? -1.0 : 0.02;
            adjustSensitivity(next);
        };

        sensIncrBtn = new Text(FontManager.regularFont, sensContainer);
        sensIncrBtn.text = "[ +2% > ]";
        sensIncrBtn.textColor = UITheme.COLOR_ACCENT_CYAN;
        sensIncrInter = new Interactive(80, 28, sensContainer);
        sensIncrInter.onClick = function(_) adjustSensitivity(0.02);

        // 2. Header Status & Mode Buttons
        toggleExclusiveBtn = new Text(FontManager.regularFont, this);
        toggleExclusiveInter = new Interactive(300, 32, this);
        toggleExclusiveInter.onClick = function(_) toggleExclusiveDevice();

        toggleViewModeBtn = new Text(FontManager.regularFont, this);
        toggleViewModeInter = new Interactive(300, 32, this);
        toggleViewModeInter.onClick = function(_) {
            controlViewMode = (controlViewMode == "Diagram") ? "Custom" : "Diagram";
            if (currentTab == Touch) {
                var d = SaveSystem.load();
                if (d.touchSettings == null) d.touchSettings = SaveSystem.getDefaultTouchSettings();
                d.touchSettings.mode = (controlViewMode == "Diagram") ? "Default" : "Custom";
                SaveSystem.save(d);
                if (onTouchSettingsChanged != null) onTouchSettingsChanged();
            }
            updateControlViewMode();
        };

        // 3. Diagram Viewer
        diagramViewer = new ControlDiagrams(this);

        // 4. Remapping List Container
        remapContainer = new Object(this);
        for (i in 0...MAX_REMAP_ITEMS) {
            var txt = new Text(FontManager.regularFont, remapContainer);
            remapItems.push(txt);

            var inter = new Interactive(REMAP_ROW_WIDTH, REMAP_ROW_HEIGHT, remapContainer);
            inter.onOver = function(_) {
                if (visible && controlViewMode == "Custom") {
                    remapIndex = i;
                    updateRemapStyles();
                }
            };
            inter.onClick = function(_) {
                if (visible && controlViewMode == "Custom") triggerRemapEntry(i);
            };
            remapInteractives.push(inter);
        }

        remapStatusNotice = new Text(FontManager.regularFont, this);
        remapStatusNotice.textColor = UITheme.COLOR_ACCENT_GOLD;
        remapStatusNotice.visible = false;

        sensitivityRow = sensContainer;
        touchDiagram = diagramViewer;
        customTouchList = remapContainer;

        updateSensitivityDisplay();
    }

    /**
     * Toggles exclusive hardware device mode for keyboard / gamepad.
     */
    public function toggleExclusiveDevice() {
        if (currentTab == Touch) return;
        AudioManager.inst.playMenuBeep(480, 0.06);
        if (currentTab == Keyboard) {
            inputRef.exclusiveDevice = (inputRef.exclusiveDevice == KeyboardOnly) ? Both : KeyboardOnly;
        } else if (currentTab == Gamepad) {
            inputRef.exclusiveDevice = (inputRef.exclusiveDevice == GamepadOnly) ? Both : GamepadOnly;
        }
        updateControlHeaderButtons();
    }

    /**
     * Increments or decrements steering sensitivity by fractional delta or integer steps (typically 0.02 = 2%).
     *
     * @param stepsOrDelta Change amount (-0.02, +0.02, -1, or +1).
     */
    public function adjustSensitivity(stepsOrDelta:Float) {
        var delta = (Math.abs(stepsOrDelta) >= 1.0) ? (stepsOrDelta * 0.02) : stepsOrDelta;
        var sens = Math.round((inputRef.steerSensitivity + delta) * 50) / 50.0;
        sens = Math.max(0.0, Math.min(1.0, sens));
        inputRef.steerSensitivity = sens;
        AudioManager.inst.playMenuBeep(420 + sens * 240, 0.04);
        updateSensitivityDisplay();

        var d = SaveSystem.load();
        d.steerSensitivity = sens;
        SaveSystem.save(d);
        #if js
        if (untyped js.Browser.window.app != null) untyped js.Browser.window.app.saveData = d;
        #end
    }

    /**
     * Refreshes text display of current steering sensitivity level.
     */
    public function updateSensitivityDisplay() {
        var sensPct = Math.round(inputRef.steerSensitivity * 100);
        var barLen = Math.round(inputRef.steerSensitivity * 20);
        var barStr = "";
        for (i in 0...20) barStr += (i < barLen) ? "■" : "□";

        sensLabel.text = "Steering Sensitivity: [" + barStr + "] " + sensPct + "%";
    }

    /**
     * Updates header status labels for exclusive device and view mode.
     */
    public function updateControlHeaderButtons() {
        if (currentTab == Touch) {
            toggleExclusiveBtn.text = "[INTERFACE: MULTI-TOUCH ACTIVE]";
            toggleExclusiveBtn.textColor = UITheme.COLOR_GREEN_SUCCESS;
            toggleExclusiveInter.visible = false;
            toggleViewModeBtn.text = "[MODE: " + (controlViewMode == "Diagram" ? "DEFAULT LAYOUT" : "CUSTOM LAYOUT") + "]";
            toggleViewModeBtn.textColor = UITheme.COLOR_ACCENT_CYAN;
            return;
        }

        toggleExclusiveInter.visible = true;
        var isKbd = (currentTab == Keyboard);
        var active = inputRef.exclusiveDevice;
        var status = "BOTH ACTIVE";
        if (active == KeyboardOnly) status = isKbd ? "EXCLUSIVE (ACTIVE)" : "MUTED";
        else if (active == GamepadOnly) status = !isKbd ? "EXCLUSIVE (ACTIVE)" : "MUTED";

        toggleExclusiveBtn.text = "[DEVICE: " + status + "]";
        toggleExclusiveBtn.textColor = (status.indexOf("MUTED") >= 0) ? UITheme.COLOR_RED_ALERT : UITheme.COLOR_GREEN_SUCCESS;
        toggleViewModeBtn.text = "[MODE: " + (controlViewMode == "Diagram" ? "DEFAULT DIAGRAM" : "CUSTOM REMAPPING") + "]";
        toggleViewModeBtn.textColor = UITheme.COLOR_ACCENT_CYAN;
    }

    /**
     * Switches between vector schematic diagram and custom key remapping views.
     */
    public function updateControlViewMode() {
        diagramViewer.visible = (controlViewMode == "Diagram");
        remapContainer.visible = (controlViewMode == "Custom");

        if (controlViewMode == "Diagram") {
            if (currentTab == Keyboard) diagramViewer.drawKeyboardLayout();
            else if (currentTab == Gamepad) diagramViewer.drawGamepadLayout();
            else if (currentTab == Touch) diagramViewer.drawTouchLayout();
        } else {
            updateRemapStyles();
        }

        updateControlHeaderButtons();
        updateSensitivityDisplay();
    }

    /**
     * Gets the number of valid items in the current custom mode list.
     *
     * @return 12 for touch tab, 7 for keyboard/gamepad tabs.
     */
    public function getMaxRemapCount():Int {
        return (currentTab == Touch) ? 12 : 7;
    }

    /**
     * Initiates remapping capture or activates an option entry.
     *
     * @param idx Action row index.
     */
    public function triggerRemapEntry(idx:Int) {
        if (currentTab == Touch) {
            var d = SaveSystem.load();
            var ts = d.touchSettings != null ? d.touchSettings : SaveSystem.getDefaultTouchSettings();
            if (idx == 11) {
                // Reset to default touch layout
                AudioManager.inst.playMenuBeep(320, 0.08);
                d.touchSettings = SaveSystem.getDefaultTouchSettings();
                d.touchSettings.mode = "Custom";
                SaveSystem.save(d);
                #if js
                if (untyped js.Browser.window.app != null) untyped js.Browser.window.app.saveData = d;
                #end
                if (onTouchSettingsChanged != null) onTouchSettingsChanged();
                updateRemapStyles();
                return;
            }

            // Click cycles value forward
            adjustCurrentCustomOption(1);
            return;
        }

        if (idx == 6) {
            AudioManager.inst.playMenuBeep(320, 0.08);
            if (currentTab == Keyboard) inputRef.bindings.resetKeyboardDefaults();
            else inputRef.bindings.resetGamepadDefaults();
            updateRemapStyles();
            return;
        }

        var isGamepad = (currentTab == Gamepad);
        var actList = [InputAction.Throttle, InputAction.Brake, InputAction.SteerLeft, InputAction.SteerRight, InputAction.Handbrake, InputAction.Boost];
        AudioManager.inst.playMenuBeep(640, 0.1);
        remapStatusNotice.text = "PRESS ANY " + (isGamepad ? "BUTTON" : "KEY") + "...";
        remapStatusNotice.visible = true;
        inputRef.startListening(actList[idx], isGamepad);
    }

    /**
     * Adjusts the currently selected custom setting left (-1) or right (+1).
     *
     * @param dir Navigation direction multiplier (-1 or +1).
     */
    public function adjustCurrentCustomOption(dir:Int) {
        if (currentTab != Touch) return;

        var d = SaveSystem.load();
        var ts = d.touchSettings != null ? d.touchSettings : SaveSystem.getDefaultTouchSettings();
        ts.mode = "Custom";
        var delta = dir * 10.0;

        switch (remapIndex) {
            case 0: ts.stickOffsetX = Math.max(-100.0, Math.min(100.0, ts.stickOffsetX + delta));
            case 1: ts.stickOffsetY = Math.max(-100.0, Math.min(100.0, ts.stickOffsetY + delta));
            case 2: ts.nitroOffsetX = Math.max(-100.0, Math.min(100.0, ts.nitroOffsetX + delta));
            case 3: ts.nitroOffsetY = Math.max(-100.0, Math.min(100.0, ts.nitroOffsetY + delta));
            case 4: ts.gasOffsetX = Math.max(-100.0, Math.min(100.0, ts.gasOffsetX + delta));
            case 5: ts.gasOffsetY = Math.max(-100.0, Math.min(100.0, ts.gasOffsetY + delta));
            case 6: ts.brakeOffsetX = Math.max(-100.0, Math.min(100.0, ts.brakeOffsetX + delta));
            case 7: ts.brakeOffsetY = Math.max(-100.0, Math.min(100.0, ts.brakeOffsetY + delta));
            case 8: ts.driftOffsetX = Math.max(-100.0, Math.min(100.0, ts.driftOffsetX + delta));
            case 9: ts.driftOffsetY = Math.max(-100.0, Math.min(100.0, ts.driftOffsetY + delta));
            case 10:
                var s = Math.round((ts.scale + dir * 0.05) * 100) / 100.0;
                ts.scale = Math.max(0.5, Math.min(1.5, s));
            case 11:
                // No adjustment for reset row
                return;
        }

        d.touchSettings = ts;
        SaveSystem.save(d);
        #if js
        if (untyped js.Browser.window.app != null) untyped js.Browser.window.app.saveData = d;
        #end
        AudioManager.inst.playMenuBeep(450 + remapIndex * 20, 0.04);
        if (onTouchSettingsChanged != null) onTouchSettingsChanged();
        updateRemapStyles();
    }


    /**
     * Toggles between Default layout diagram and Custom layout adjustment list.
     */
    public function toggleCustomMode() {
        controlViewMode = (controlViewMode == "Diagram") ? "Custom" : "Diagram";
        var d = SaveSystem.load();
        d.touchSettings.mode = (controlViewMode == "Diagram") ? "Default" : "Custom";
        SaveSystem.save(d);
        #if js
        if (untyped js.Browser.window.app != null) untyped js.Browser.window.app.saveData = d;
        #end
        updateControlViewMode();
        if (onTouchSettingsChanged != null) onTouchSettingsChanged();
    }

    /**
     * Adjusts a specific touch custom option row by index and direction.
     *
     * @param row Option row index (0-11).
     * @param dir Increment or decrement direction (-1 or +1).
     */
    public function cycleCustomTouchRow(row:Int, dir:Int) {
        remapIndex = row;
        adjustCurrentCustomOption(dir);
    }

    /**
     * Resets touch controls configuration to baseline defaults.
     */
    public function resetTouchDefaults() {
        triggerRemapEntry(11);
    }

    /**
     * Navigates cursor up or down when in custom remapping mode.
     *
     * @param dir Navigation offset (-1 or +1).
     */
    public function navigate(dir:Int) {
        var count = getMaxRemapCount();
        remapIndex = (remapIndex + dir + count) % count;
        AudioManager.inst.playMenuBeep(380, 0.04);
        updateRemapStyles();
    }

    /**
     * Refreshes text and highlights in remapping / custom list.
     */
    public function updateRemapStyles() {
        var count = getMaxRemapCount();

        if (currentTab == Touch) {
            var d = SaveSystem.load();
            var ts = d.touchSettings != null ? d.touchSettings : SaveSystem.getDefaultTouchSettings();
            var labels = [
                "Analog Joystick Offset X:  " + Math.round(ts.stickOffsetX) + " px  [ < / > ]",
                "Analog Joystick Offset Y:  " + Math.round(ts.stickOffsetY) + " px  [ < / > ]",
                "Nitro Button Offset X:     " + Math.round(ts.nitroOffsetX) + " px  [ < / > ]",
                "Nitro Button Offset Y:     " + Math.round(ts.nitroOffsetY) + " px  [ < / > ]",
                "Gas Pedal Offset X:        " + Math.round(ts.gasOffsetX) + " px  [ < / > ]",
                "Gas Pedal Offset Y:        " + Math.round(ts.gasOffsetY) + " px  [ < / > ]",
                "Brake Disc Offset X:       " + Math.round(ts.brakeOffsetX) + " px  [ < / > ]",
                "Brake Disc Offset Y:       " + Math.round(ts.brakeOffsetY) + " px  [ < / > ]",
                "Handbrake Offset X:        " + Math.round(ts.driftOffsetX) + " px  [ < / > ]",
                "Handbrake Offset Y:        " + Math.round(ts.driftOffsetY) + " px  [ < / > ]",
                "Touch Controls Scale:      " + Math.round(ts.scale * 100) + "%  [ < / > ]",
                "[RESET TOUCH LAYOUT TO DEFAULTS]"
            ];

            for (i in 0...MAX_REMAP_ITEMS) {
                var item = remapItems[i];
                var inter = remapInteractives[i];
                if (i < count) {
                    item.visible = true;
                    inter.visible = true;
                    if (i == remapIndex) {
                        item.textColor = UITheme.COLOR_ACCENT_CYAN;
                        item.text = "> " + labels[i] + " <";
                    } else {
                        item.textColor = (i == 11) ? 0xE5C07B : UITheme.COLOR_TEXT_NORMAL;
                        item.text = "  " + labels[i] + "  ";
                    }
                } else {
                    item.visible = false;
                    inter.visible = false;
                }
            }
            return;
        }

        var isGamepad = (currentTab == Gamepad);
        var b = inputRef.bindings;
        var labels = [
            "Throttle (Gas):       " + (isGamepad ? InputController.getGamepadBtnName(b.padGas) : InputController.getKeyName(b.keyGas)),
            "Brake / Reverse:      " + (isGamepad ? InputController.getGamepadBtnName(b.padBrake) : InputController.getKeyName(b.keyBrake)),
            "Steer Left:           " + (isGamepad ? "Left Analog / D-Pad" : InputController.getKeyName(b.keyLeft)),
            "Steer Right:          " + (isGamepad ? "Left Analog / D-Pad" : InputController.getKeyName(b.keyRight)),
            "Handbrake (Drift):    " + (isGamepad ? InputController.getGamepadBtnName(b.padHandbrake) : InputController.getKeyName(b.keyHandbrake)),
            "Nitro Boost:          " + (isGamepad ? InputController.getGamepadBtnName(b.padBoost) : InputController.getKeyName(b.keyBoost)),
            "[RESET TO DEFAULTS]"
        ];

        for (i in 0...MAX_REMAP_ITEMS) {
            var item = remapItems[i];
            var inter = remapInteractives[i];
            if (i < count) {
                item.visible = true;
                inter.visible = true;
                if (i == remapIndex) {
                    item.textColor = UITheme.COLOR_ACCENT_CYAN;
                    item.text = "> " + labels[i] + " <";
                } else {
                    item.textColor = (i == 6) ? 0xE5C07B : UITheme.COLOR_TEXT_NORMAL;
                    item.text = "  " + labels[i] + "  ";
                }
            } else {
                item.visible = false;
                inter.visible = false;
            }
        }
    }

    /**
     * Positions diagram viewer, sensitivity controls, header buttons, and remapping items.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param cardX Modal card left coordinate.
     * @param cardY Modal card top coordinate.
     * @param cardW Modal card width.
     * @param cardH Modal card height.
     */
    public function layout(sw:Float, sh:Float, cardX:Float = 0, cardY:Float = 0, cardW:Float = 0, cardH:Float = 0) {
        var effectiveCardX = (cardW > 0) ? cardX : (sw - UITheme.OPTIONS_CARD_WIDTH) * 0.5;
        var effectiveCardY = (cardH > 0) ? cardY : sh * 0.16;
        var effectiveCardW = (cardW > 0) ? cardW : UITheme.OPTIONS_CARD_WIDTH;
        var effectiveCardH = (cardH > 0) ? cardH : UITheme.OPTIONS_CARD_HEIGHT;

        // 1. Steering Sensitivity Slider at top
        var sensY = effectiveCardY + 54.0;
        if (sensLabel != null) {
            sensLabel.x = (sw - sensLabel.textWidth) * 0.5;
            sensLabel.y = sensY;
            sensRowInter.x = sensLabel.x;
            sensRowInter.y = sensY;
            sensRowInter.width = sensLabel.textWidth;
            sensRowInter.height = 24.0;

            sensDecrBtn.x = sensLabel.x - sensDecrBtn.textWidth - 14.0;
            sensDecrBtn.y = sensY;
            sensDecrInter.x = sensDecrBtn.x;
            sensDecrInter.y = sensY;
            sensDecrInter.width = sensDecrBtn.textWidth;
            sensDecrInter.height = 24.0;

            sensIncrBtn.x = sensLabel.x + sensLabel.textWidth + 14.0;
            sensIncrBtn.y = sensY;
            sensIncrInter.x = sensIncrBtn.x;
            sensIncrInter.y = sensY;
            sensIncrInter.width = sensIncrBtn.textWidth;
            sensIncrInter.height = 24.0;
        }

        // 2. Mode and Device Header Buttons
        var headerY = sensY + 34.0;
        if (toggleExclusiveBtn != null) {
            toggleExclusiveBtn.x = effectiveCardX + 50.0;
            toggleExclusiveBtn.y = headerY;
            toggleExclusiveInter.x = toggleExclusiveBtn.x;
            toggleExclusiveInter.y = toggleExclusiveBtn.y;
        }
        if (toggleViewModeBtn != null) {
            toggleViewModeBtn.x = effectiveCardX + effectiveCardW - 350.0;
            toggleViewModeBtn.y = headerY;
            toggleViewModeInter.x = toggleViewModeBtn.x;
            toggleViewModeInter.y = toggleViewModeBtn.y;
        }

        // 3. Diagram Viewer
        if (diagramViewer != null) {
            diagramViewer.x = effectiveCardX + (effectiveCardW * 0.5);
            diagramViewer.y = effectiveCardY + 320.0;
            diagramViewer.setScale(0.92);
        }

        // 4. Remapping List
        var remapStartY = headerY + 42.0;
        if (remapStatusNotice != null) {
            remapStatusNotice.x = (sw - remapStatusNotice.textWidth) * 0.5;
            remapStatusNotice.y = remapStartY;
        }

        var itemsStartY = remapStartY + 24.0;
        for (i in 0...MAX_REMAP_ITEMS) {
            var item = remapItems[i];
            var inter = remapInteractives[i];
            item.x = (sw - item.textWidth) * 0.5;
            item.y = itemsStartY + (i * REMAP_ROW_STRIDE);
            inter.x = effectiveCardX + (effectiveCardW - REMAP_ROW_WIDTH) * 0.5;
            inter.y = item.y;
            inter.width = REMAP_ROW_WIDTH;
            inter.height = REMAP_ROW_HEIGHT;
        }
    }
}
