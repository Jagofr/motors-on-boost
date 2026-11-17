package ui.views.options;

import ui.nodes.UINodes.UIObject as Object;
import ui.nodes.UINodes.UIText as Text;
import ui.nodes.UINodes.UIGraphics as Graphics;
import ui.nodes.UINodes.UIInteractive as Interactive;
import ui.FontManager;
import ui.ControlDiagrams;
import ui.components.CardBackplate;
import ui.components.UITheme;
import ui.components.UIEnums.OptionsTab;
import input.InputController;
import input.InputController.InputAction;
import input.InputController.ExclusiveDevice;
import audio.AudioManager;
import save.SaveSystem;
import save.SaveSystem.GameSaveData;
import save.SaveSystem.TouchSettings;

/**
 * Controller, keyboard, and touch screen configuration, schematic diagrams,
 * and custom action / button remapping subpanel.
 * Features an independent persistent steering sensitivity slider active across all control modes.
 *
 * @class ControlsOptionsPanel
 * @extends ui.nodes.UINodes.UIObject
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

    /** Procedural background graphics for header buttons and touch custom grid cards. */
    public var headerBg:Graphics;
    public var remapBg:Graphics;

    /** Vector schematic diagram canvas. */
    public var diagramViewer:ControlDiagrams;

    /** Container holding interactive remapping list rows. */
    public var remapContainer:Object;

    /** Remapping row items text labels. */
    public var remapItems:Array<Text> = [];

    /** Remapping interactive hitzones. */
    public var remapInteractives:Array<Interactive> = [];

    /** Dedicated decrement `[ - ]` button labels and touch hitzones for custom touch rows. */
    public var remapDecrBtns:Array<Text> = [];
    public var remapDecrInteractives:Array<Interactive> = [];

    /** Dedicated increment `[ + ]` button labels and touch hitzones for custom touch rows. */
    public var remapIncrBtns:Array<Text> = [];
    public var remapIncrInteractives:Array<Interactive> = [];

    /** Currently highlighted remapping item index. */
    public var remapIndex:Int = 0;

    /** Status notice text shown when waiting for remapping input. */
    public var remapStatusNotice:Text;

    private var lastSw:Float = 0.0;
    private var lastSh:Float = 0.0;
    private var lastCardX:Float = 0.0;
    private var lastCardY:Float = 0.0;
    private var lastCardW:Float = 0.0;
    private var lastCardH:Float = 0.0;

    /** Active view mode ("Diagram" or "Custom"). */
    public var controlViewMode:String = "Diagram";

    /** Reference to active input controller. */
    public var inputRef:InputController;

    /** Currently selected options tab. */
    public var currentTab:OptionsTab = Keyboard;

    /** Callback invoked whenever touch control settings are modified. */
    public var onTouchSettingsChanged:Null<Void -> Void>;

    /** Optional provider returning the active persistent save structure. */
    public var getSaveData:Null<Void -> GameSaveData>;

    /** Optional callback notified whenever save settings are mutated and persisted. */
    public var onSaveDataUpdated:Null<GameSaveData -> Void>;

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

        headerBg = new Graphics(this);

        // 1. General Steering Sensitivity Row
        sensContainer = new Object(this);

        sensDecrBtn = new Text(FontManager.regularFont, sensContainer);
        sensDecrBtn.text = "[ < -2% ]";
        sensDecrBtn.textColor = UITheme.COLOR_ACCENT_CYAN;
        sensDecrInter = new Interactive(80, 30, sensContainer);
        sensDecrInter.onClick = function(_) adjustSensitivity(-0.02);

        sensLabel = new Text(FontManager.regularFont, sensContainer);
        sensLabel.textColor = UITheme.COLOR_TEXT_NORMAL;

        sensRowInter = new Interactive(320, 30, sensContainer);
        sensRowInter.onClick = function(_) {
            // Cycle sensitivity by +2% or wrap around
            var next = inputRef.steerSensitivity >= 0.99 ? -1.0 : 0.02;
            adjustSensitivity(next);
        };

        sensIncrBtn = new Text(FontManager.regularFont, sensContainer);
        sensIncrBtn.text = "[ +2% > ]";
        sensIncrBtn.textColor = UITheme.COLOR_ACCENT_CYAN;
        sensIncrInter = new Interactive(80, 30, sensContainer);
        sensIncrInter.onClick = function(_) adjustSensitivity(0.02);

        // 2. Header Status & Mode Buttons
        toggleExclusiveBtn = new Text(FontManager.regularFont, this);
        toggleExclusiveInter = new Interactive(300, 32, this);
        toggleExclusiveInter.onClick = function(_) toggleExclusiveDevice();

        toggleViewModeBtn = new Text(FontManager.regularFont, this);
        toggleViewModeInter = new Interactive(360, 32, this);
        toggleViewModeInter.onClick = function(_) toggleCustomMode();

        // 3. Diagram Viewer
        diagramViewer = new ControlDiagrams(this);

        // 4. Remapping List Container
        remapContainer = new Object(this);
        remapBg = new Graphics(remapContainer);
        for (i in 0...MAX_REMAP_ITEMS) {
            var idx = i;

            var decrTxt = new Text(FontManager.regularFont, remapContainer);
            decrTxt.text = "- 10";
            decrTxt.textColor = UITheme.COLOR_ACCENT_CYAN;
            decrTxt.visible = false;
            remapDecrBtns.push(decrTxt);

            var decrInter = new Interactive(68, 34, remapContainer);
            decrInter.visible = false;
            decrInter.onOver = function(_) {
                if (visible && controlViewMode == "Custom" && currentTab == Touch) {
                    remapIndex = idx;
                    updateRemapStyles();
                }
            };
            decrInter.onClick = function(_) {
                if (visible && controlViewMode == "Custom" && currentTab == Touch) {
                    cycleCustomTouchRow(idx, -1);
                }
            };
            remapDecrInteractives.push(decrInter);

            var txt = new Text(FontManager.regularFont, remapContainer);
            remapItems.push(txt);

            var inter = new Interactive(REMAP_ROW_WIDTH, REMAP_ROW_HEIGHT, remapContainer);
            inter.onOver = function(_) {
                if (visible && controlViewMode == "Custom") {
                    remapIndex = idx;
                    updateRemapStyles();
                }
            };
            inter.onClick = function(_) {
                if (visible && controlViewMode == "Custom") {
                    remapIndex = idx;
                    triggerRemapEntry(idx);
                }
            };
            remapInteractives.push(inter);

            var incrTxt = new Text(FontManager.regularFont, remapContainer);
            incrTxt.text = "+ 10";
            incrTxt.textColor = UITheme.COLOR_ACCENT_CYAN;
            incrTxt.visible = false;
            remapIncrBtns.push(incrTxt);

            var incrInter = new Interactive(68, 34, remapContainer);
            incrInter.visible = false;
            incrInter.onOver = function(_) {
                if (visible && controlViewMode == "Custom" && currentTab == Touch) {
                    remapIndex = idx;
                    updateRemapStyles();
                }
            };
            incrInter.onClick = function(_) {
                if (visible && controlViewMode == "Custom" && currentTab == Touch) {
                    cycleCustomTouchRow(idx, 1);
                }
            };
            remapIncrInteractives.push(incrInter);
        }

        remapStatusNotice = new Text(FontManager.regularFont, this);
        remapStatusNotice.textColor = UITheme.COLOR_ACCENT_GOLD;
        remapStatusNotice.visible = false;

        sensitivityRow = sensContainer;
        touchDiagram = diagramViewer;
        customTouchList = remapContainer;

        inputRef.onRemapComplete = function(bound:Bool) {
            remapStatusNotice.visible = false;
            if (bound) persistInputBindings();
            updateRemapStyles();
        };

        updateSensitivityDisplay();
    }

    function loadActiveSave():GameSaveData {
        var d = (getSaveData != null) ? getSaveData() : SaveSystem.load();
        if (d == null) d = SaveSystem.load();
        if (d.touchSettings == null) d.touchSettings = SaveSystem.getDefaultTouchSettings();
        return d;
    }

    function persistActiveSave(d:GameSaveData) {
        SaveSystem.save(d);
        if (onSaveDataUpdated != null) onSaveDataUpdated(d);
    }

    /**
     * Synchronizes current key/gamepad bindings and exclusive hardware selection to save storage.
     */
    public function persistInputBindings() {
        var d = loadActiveSave();
        inputRef.exportToSave(d);
        persistActiveSave(d);
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
        persistInputBindings();
        updateControlHeaderButtons();
    }

    /**
     * Increments or decrements steering sensitivity by fractional delta or integer steps (typically 0.02 = 2%).
     *
     * @param {Float} stepsOrDelta Change amount (-0.02, +0.02, -1, or +1).
     */
    public function adjustSensitivity(stepsOrDelta:Float) {
        var delta = (Math.abs(stepsOrDelta) >= 1.0) ? (stepsOrDelta * 0.02) : stepsOrDelta;
        var sens = Math.round((inputRef.steerSensitivity + delta) * 50) / 50.0;
        sens = Math.max(0.0, Math.min(1.0, sens));
        inputRef.steerSensitivity = sens;
        AudioManager.inst.playMenuBeep(420 + sens * 240, 0.04);
        updateSensitivityDisplay();

        var d = loadActiveSave();
        d.steerSensitivity = sens;
        persistActiveSave(d);
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
            toggleViewModeBtn.text = (controlViewMode == "Diagram")
                ? "[MODE: DEFAULT LAYOUT  |  TAP TO CUSTOMIZE]"
                : "[MODE: CUSTOM OFFSETS  |  TAP FOR PREVIEW]";
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

        updateControlHeaderButtons();
        updateSensitivityDisplay();

        if (controlViewMode == "Diagram") {
            if (currentTab == Keyboard) diagramViewer.drawKeyboardLayout();
            else if (currentTab == Gamepad) diagramViewer.drawGamepadLayout();
            else if (currentTab == Touch) diagramViewer.drawTouchLayout(loadActiveSave().touchSettings);
        } else {
            updateRemapStyles();
        }

        applySubpanelLayout();
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
     * @param {Int} idx Action row index.
     */
    public function triggerRemapEntry(idx:Int) {
        if (currentTab == Touch) {
            remapIndex = idx;
            if (idx == 11) {
                AudioManager.inst.playMenuBeep(320, 0.08);
                var d = loadActiveSave();
                d.touchSettings = SaveSystem.getDefaultTouchSettings();
                d.touchSettings.mode = "Custom";
                persistActiveSave(d);
                if (onTouchSettingsChanged != null) onTouchSettingsChanged();
                updateRemapStyles();
                return;
            }

            adjustCurrentCustomOption(1);
            return;
        }

        if (idx == 6) {
            AudioManager.inst.playMenuBeep(320, 0.08);
            if (currentTab == Keyboard) inputRef.bindings.resetKeyboardDefaults();
            else inputRef.bindings.resetGamepadDefaults();
            persistInputBindings();
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
     * @param {Int} dir Navigation direction multiplier (-1 or +1).
     */
    public function adjustCurrentCustomOption(dir:Int) {
        if (currentTab != Touch) return;

        var d = loadActiveSave();
        var ts = d.touchSettings;
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
                return;
        }

        d.touchSettings = ts;
        persistActiveSave(d);
        AudioManager.inst.playMenuBeep(450 + remapIndex * 20, 0.04);
        if (onTouchSettingsChanged != null) onTouchSettingsChanged();
        updateRemapStyles();
    }

    /**
     * Directly updates an X/Y offset pair for a virtual touch element (from drag/touch preview).
     */
    public function setTouchControlOffset(part:String, ox:Float, oy:Float):Void {
        var d = loadActiveSave();
        var ts = d.touchSettings;
        ts.mode = "Custom";
        controlViewMode = "Custom";
        var cx = Math.max(-100.0, Math.min(100.0, Math.round(ox)));
        var cy = Math.max(-100.0, Math.min(100.0, Math.round(oy)));
        switch (part) {
            case "stick": ts.stickOffsetX = cx; ts.stickOffsetY = cy; remapIndex = 0;
            case "nitro": ts.nitroOffsetX = cx; ts.nitroOffsetY = cy; remapIndex = 2;
            case "gas":   ts.gasOffsetX = cx;   ts.gasOffsetY = cy;   remapIndex = 4;
            case "brake": ts.brakeOffsetX = cx; ts.brakeOffsetY = cy; remapIndex = 6;
            case "drift": ts.driftOffsetX = cx; ts.driftOffsetY = cy; remapIndex = 8;
            default:
        }
        d.touchSettings = ts;
        persistActiveSave(d);
        if (onTouchSettingsChanged != null) onTouchSettingsChanged();
        updateControlViewMode();
    }

    /**
     * Toggles between Default layout diagram and Custom layout adjustment list.
     */
    public function toggleCustomMode() {
        controlViewMode = (controlViewMode == "Diagram") ? "Custom" : "Diagram";
        if (currentTab == Touch) {
            var d = loadActiveSave();
            d.touchSettings.mode = (controlViewMode == "Diagram") ? "Default" : "Custom";
            persistActiveSave(d);
            if (onTouchSettingsChanged != null) onTouchSettingsChanged();
        }
        updateControlViewMode();
    }

    /**
     * Adjusts a specific touch custom option row by index and direction.
     *
     * @param {Int} row Option row index (0-11).
     * @param {Int} dir Increment or decrement direction (-1 or +1).
     */
    public function cycleCustomTouchRow(row:Int, dir:Int) {
        remapIndex = row;
        controlViewMode = "Custom";
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
     * @param {Int} dir Navigation offset (-1 or +1).
     */
    public function navigate(dir:Int) {
        var count = getMaxRemapCount();
        remapIndex = (remapIndex + dir + count) % count;
        AudioManager.inst.playMenuBeep(380, 0.04);
        updateRemapStyles();
    }

    function fmtSignedPx(val:Float):String {
        var n = Math.round(val);
        return (n > 0 ? "+" : "") + n + " px";
    }

    function hideTouchStepButtons() {
        for (i in 0...MAX_REMAP_ITEMS) {
            remapDecrBtns[i].visible = false;
            remapDecrInteractives[i].visible = false;
            remapIncrBtns[i].visible = false;
            remapIncrInteractives[i].visible = false;
        }
    }

    function applyRemapRowLabels(labels:Array<String>, resetIdx:Int) {
        hideTouchStepButtons();
        var count = labels.length;
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
                    item.textColor = (i == resetIdx) ? 0xE5C07B : UITheme.COLOR_TEXT_NORMAL;
                    item.text = "  " + labels[i] + "  ";
                }
            } else {
                item.visible = false;
                inter.visible = false;
            }
        }
    }

    /**
     * Refreshes text and highlights in remapping / custom list.
     */
    public function updateRemapStyles() {
        if (currentTab == Touch) {
            var ts = loadActiveSave().touchSettings;
            var labels = [
                "Joystick X:   " + fmtSignedPx(ts.stickOffsetX),
                "Joystick Y:   " + fmtSignedPx(ts.stickOffsetY),
                "Nitro Btn X:  " + fmtSignedPx(ts.nitroOffsetX),
                "Nitro Btn Y:  " + fmtSignedPx(ts.nitroOffsetY),
                "Gas Pedal X:  " + fmtSignedPx(ts.gasOffsetX),
                "Gas Pedal Y:  " + fmtSignedPx(ts.gasOffsetY),
                "Brake Disc X: " + fmtSignedPx(ts.brakeOffsetX),
                "Brake Disc Y: " + fmtSignedPx(ts.brakeOffsetY),
                "Handbrake X:  " + fmtSignedPx(ts.driftOffsetX),
                "Handbrake Y:  " + fmtSignedPx(ts.driftOffsetY),
                "HUD Scale:    " + Math.round(ts.scale * 100) + "%",
                "RESET DEFAULT LAYOUT"
            ];

            for (i in 0...MAX_REMAP_ITEMS) {
                var isSel = (i == remapIndex);
                remapItems[i].visible = true;
                remapInteractives[i].visible = true;
                remapItems[i].text = labels[i];

                if (i < 11) {
                    remapItems[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_TEXT_NORMAL;

                    var decrBtn = remapDecrBtns[i];
                    var incrBtn = remapIncrBtns[i];
                    decrBtn.text = (i == 10) ? "- 5%" : "- 10";
                    incrBtn.text = (i == 10) ? "+ 5%" : "+ 10";
                    decrBtn.textColor = isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_ACCENT_CYAN;
                    incrBtn.textColor = isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_ACCENT_CYAN;

                    decrBtn.visible = true;
                    remapDecrInteractives[i].visible = true;
                    incrBtn.visible = true;
                    remapIncrInteractives[i].visible = true;
                } else {
                    remapItems[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_ACCENT_GOLD;
                    remapDecrBtns[i].visible = false;
                    remapDecrInteractives[i].visible = false;
                    remapIncrBtns[i].visible = false;
                    remapIncrInteractives[i].visible = false;
                }
            }

            applySubpanelLayout();
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
        applyRemapRowLabels(labels, 6);
        applySubpanelLayout();
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
        lastSw = sw;
        lastSh = sh;
        lastCardX = cardX;
        lastCardY = cardY;
        lastCardW = cardW;
        lastCardH = cardH;
        applySubpanelLayout();
    }

    function applySubpanelLayout() {
        var sw = (lastSw > 0) ? lastSw : 1280.0;
        var sh = (lastSh > 0) ? lastSh : 720.0;
        var effectiveCardW = (lastCardW > 0) ? lastCardW : UITheme.OPTIONS_CARD_WIDTH;
        var effectiveCardH = (lastCardH > 0) ? lastCardH : UITheme.OPTIONS_CARD_HEIGHT;
        var effectiveCardX = (lastCardW > 0) ? lastCardX : (sw - effectiveCardW) * 0.5;
        var effectiveCardY = (lastCardH > 0) ? lastCardY : Math.max(12.0, (sh - effectiveCardH) * 0.5);

        if (headerBg != null) headerBg.clear();
        if (remapBg != null) remapBg.clear();

        // 1. Steering Sensitivity Slider cleanly below tab bar divider (cardY + 60)
        var sensY = effectiveCardY + 66.0;
        if (sensLabel != null) {
            sensLabel.x = (sw - sensLabel.textWidth) * 0.5;
            sensLabel.y = sensY;
            sensRowInter.x = sensLabel.x;
            sensRowInter.y = sensY + 5.0;
            sensRowInter.width = sensLabel.textWidth;
            sensRowInter.height = 30.0;

            sensDecrBtn.x = sensLabel.x - sensDecrBtn.textWidth - 16.0;
            sensDecrBtn.y = sensY;
            sensDecrInter.x = sensDecrBtn.x - 6.0;
            sensDecrInter.y = sensY + 5.0;
            sensDecrInter.width = sensDecrBtn.textWidth + 12.0;
            sensDecrInter.height = 30.0;

            sensIncrBtn.x = sensLabel.x + sensLabel.textWidth + 16.0;
            sensIncrBtn.y = sensY;
            sensIncrInter.x = sensIncrBtn.x - 6.0;
            sensIncrInter.y = sensY + 5.0;
            sensIncrInter.width = sensIncrBtn.textWidth + 12.0;
            sensIncrInter.height = 30.0;

            if (headerBg != null) {
                CardBackplate.drawChamferedBox(headerBg, sensDecrInter.x, sensDecrInter.y, sensDecrInter.width, sensDecrInter.height, 4.0, 0x101C2C, 0.72, UITheme.COLOR_ACCENT_CYAN, 0.55, 1.0);
                CardBackplate.drawChamferedBox(headerBg, sensIncrInter.x, sensIncrInter.y, sensIncrInter.width, sensIncrInter.height, 4.0, 0x101C2C, 0.72, UITheme.COLOR_ACCENT_CYAN, 0.55, 1.0);
            }
        }

        // 2. Mode and Device Header Buttons
        var headerY = sensY + 36.0;
        if (toggleExclusiveBtn != null) {
            toggleExclusiveBtn.x = effectiveCardX + 40.0;
            toggleExclusiveBtn.y = headerY;
            toggleExclusiveInter.x = toggleExclusiveBtn.x - 8.0;
            toggleExclusiveInter.y = headerY + 4.0;
            toggleExclusiveInter.width = Math.max(220.0, toggleExclusiveBtn.textWidth + 16.0);
            toggleExclusiveInter.height = 32.0;
        }
        if (toggleViewModeBtn != null) {
            var modeW = Math.max(260.0, toggleViewModeBtn.textWidth + 24.0);
            var modeX = effectiveCardX + effectiveCardW - modeW - 36.0;
            toggleViewModeBtn.x = modeX + 12.0;
            toggleViewModeBtn.y = headerY;
            toggleViewModeInter.x = modeX;
            toggleViewModeInter.y = headerY + 4.0;
            toggleViewModeInter.width = modeW;
            toggleViewModeInter.height = 32.0;

            if (headerBg != null) {
                CardBackplate.drawChamferedBox(
                    headerBg, modeX, headerY + 4.0, modeW, 32.0, 5.0,
                    0x102438, 0.80, UITheme.COLOR_ACCENT_CYAN, 0.85, 1.3
                );
            }
        }

        // 3. Diagram Viewer
        if (diagramViewer != null) {
            diagramViewer.x = effectiveCardX + (effectiveCardW * 0.5);
            diagramViewer.y = effectiveCardY + Math.min(340.0, effectiveCardH * 0.57);
            diagramViewer.setScale(0.92);
        }

        // 4. Remapping List / Touch Custom Stepper Grid
        if (remapStatusNotice != null) {
            remapStatusNotice.x = (sw - remapStatusNotice.textWidth) * 0.5;
            remapStatusNotice.y = headerY + 36.0;
        }

        if (currentTab == Touch) {
            layoutTouchCustomGrid(effectiveCardX, effectiveCardY, effectiveCardW, effectiveCardH, headerY + 44.0);
            return;
        }

        var itemsStartY = headerY + 62.0;
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

    function layoutTouchCustomGrid(cardX:Float, cardY:Float, cardW:Float, cardH:Float, gridTop:Float) {
        var padX = 32.0;
        var colGap = 20.0;
        var cellW = (cardW - (padX * 2.0) - colGap) * 0.5;
        var availH = Math.max(180.0, cardH - (gridTop - cardY) - 14.0);
        var rowStride = Math.min(56.0, availH / 6.0);
        var cellH = Math.min(44.0, Math.max(26.0, rowStride - 8.0));
        var btnW = Math.min(68.0, Math.max(48.0, cellW * 0.165));
        var btnH = Math.min(34.0, cellH - 6.0);

        for (i in 0...MAX_REMAP_ITEMS) {
            var col = i % 2;
            var row = Std.int(i / 2);
            var cellX = cardX + padX + col * (cellW + colGap);
            var cellY = gridTop + row * rowStride;
            var centerY = cellY + cellH * 0.5;
            var textTopY = centerY - 20.0;
            var isSel = (i == remapIndex);

            var item = remapItems[i];
            var inter = remapInteractives[i];

            if (i < 11) {
                var btnY = cellY + (cellH - btnH) * 0.5;
                var decrX = cellX + 6.0;
                var incrX = cellX + cellW - btnW - 6.0;
                var midX = decrX + btnW + 4.0;
                var midW = Math.max(40.0, (incrX - 4.0) - midX);

                var decrBtn = remapDecrBtns[i];
                var decrInter = remapDecrInteractives[i];
                decrBtn.x = decrX + (btnW - decrBtn.textWidth) * 0.5;
                decrBtn.y = textTopY;
                decrInter.x = decrX;
                decrInter.y = btnY;
                decrInter.width = btnW;
                decrInter.height = btnH;

                var incrBtn = remapIncrBtns[i];
                var incrInter = remapIncrInteractives[i];
                incrBtn.x = incrX + (btnW - incrBtn.textWidth) * 0.5;
                incrBtn.y = textTopY;
                incrInter.x = incrX;
                incrInter.y = btnY;
                incrInter.width = btnW;
                incrInter.height = btnH;

                item.x = midX + (midW - item.textWidth) * 0.5;
                item.y = textTopY;
                inter.x = midX;
                inter.y = btnY;
                inter.width = midW;
                inter.height = btnH;

                if (remapBg != null && controlViewMode == "Custom") {
                    CardBackplate.drawChamferedBox(
                        remapBg, cellX, cellY, cellW, cellH, 6.0,
                        isSel ? 0x132235 : 0x0F1622, isSel ? 0.90 : 0.72,
                        isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_DIVIDER, isSel ? 0.90 : 0.55,
                        isSel ? 1.6 : 1.0
                    );
                    CardBackplate.drawChamferedBox(
                        remapBg, decrX, btnY, btnW, btnH, 4.0,
                        0x15273D, 0.92,
                        isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_ACCENT_CYAN, 0.82, 1.2
                    );
                    CardBackplate.drawChamferedBox(
                        remapBg, incrX, btnY, btnW, btnH, 4.0,
                        0x15273D, 0.92,
                        isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_ACCENT_CYAN, 0.82, 1.2
                    );
                }
            } else {
                item.x = cellX + (cellW - item.textWidth) * 0.5;
                item.y = textTopY;
                inter.x = cellX;
                inter.y = cellY;
                inter.width = cellW;
                inter.height = cellH;

                if (remapBg != null && controlViewMode == "Custom") {
                    CardBackplate.drawChamferedBox(
                        remapBg, cellX, cellY, cellW, cellH, 6.0,
                        isSel ? 0x241B12 : 0x1A1510, 0.85,
                        isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_ACCENT_ORANGE, 0.85,
                        isSel ? 1.6 : 1.2
                    );
                }
            }
        }
    }
}
