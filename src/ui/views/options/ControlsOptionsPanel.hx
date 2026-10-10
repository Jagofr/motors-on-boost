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

/**
 * Controller and keyboard configuration, schematic diagrams, and custom action remapping subpanel.
 */
class ControlsOptionsPanel extends Object {
    /** Toggle exclusive hardware device button. */
    public var toggleExclusiveBtn:Text;
    public var toggleExclusiveInter:Interactive;

    /** Toggle schematic diagram vs custom remapping button. */
    public var toggleViewModeBtn:Text;
    public var toggleViewModeInter:Interactive;

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

    /** Interactive remapping row hitzone width in pixels. */
    public static inline var REMAP_ROW_WIDTH:Float = 500.0;

    /** Interactive remapping row hitzone height in pixels. */
    public static inline var REMAP_ROW_HEIGHT:Float = 36.0;

    /** Vertical spacing between successive remapping list rows in pixels. */
    public static inline var REMAP_ROW_STRIDE:Float = 38.0;

    /**
     * Instantiates the controls and hardware options subpanel.
     *
     * @param input Input controller reference.
     * @param parent Optional parent 2D scene object.
     */
    public function new(input:InputController, ?parent:Object) {
        super(parent);
        this.inputRef = input;

        toggleExclusiveBtn = new Text(FontManager.regularFont, this);
        toggleExclusiveInter = new Interactive(300, 34, this);
        toggleExclusiveInter.onClick = function(_) toggleExclusiveDevice();

        toggleViewModeBtn = new Text(FontManager.regularFont, this);
        toggleViewModeInter = new Interactive(300, 34, this);
        toggleViewModeInter.onClick = function(_) {
            controlViewMode = (controlViewMode == "Diagram") ? "Custom" : "Diagram";
            updateControlViewMode();
        };

        diagramViewer = new ControlDiagrams(this);

        remapContainer = new Object(this);
        var actions = ["Steering Sensitivity", "Throttle (Gas)", "Brake / Reverse", "Steer Left", "Steer Right", "Handbrake", "Nitro Boost", "Reset All to Defaults"];
        for (i in 0...actions.length) {
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
    }

    /**
     * Toggles exclusive hardware device mode.
     */
    public function toggleExclusiveDevice() {
        AudioManager.inst.playMenuBeep(480, 0.06);
        if (currentTab == Keyboard) {
            inputRef.exclusiveDevice = (inputRef.exclusiveDevice == KeyboardOnly) ? Both : KeyboardOnly;
        } else if (currentTab == Gamepad) {
            inputRef.exclusiveDevice = (inputRef.exclusiveDevice == GamepadOnly) ? Both : GamepadOnly;
        }
        updateControlHeaderButtons();
    }

    /**
     * Updates header status labels for exclusive device and view mode.
     */
    public function updateControlHeaderButtons() {
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
            else diagramViewer.drawGamepadLayout();
        } else {
            updateRemapStyles();
        }
        updateControlHeaderButtons();
    }

    /**
     * Initiates remapping capture for an action.
     *
     * @param idx Action row index.
     */
    public function triggerRemapEntry(idx:Int) {
        if (idx == 0) {
            // Cycle sensitivity by +2% or wrap around
            var next = inputRef.steerSensitivity >= 0.99 ? -1.0 : 0.02;
            adjustSensitivity(next);
            return;
        }

        if (idx == 7) {
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
        inputRef.startListening(actList[idx - 1], isGamepad);
    }

    /**
     * Increments or decrements steering sensitivity by fractional delta (typically 0.02 = 2%).
     *
     * @param delta Change amount (-0.02 or +0.02).
     */
    public function adjustSensitivity(delta:Float) {
        var sens = Math.round((inputRef.steerSensitivity + delta) * 50) / 50.0;
        sens = Math.max(0.0, Math.min(1.0, sens));
        inputRef.steerSensitivity = sens;
        AudioManager.inst.playMenuBeep(420 + sens * 240, 0.04);
        updateRemapStyles();

        var d = SaveSystem.load();
        d.steerSensitivity = sens;
        SaveSystem.save(d);
    }

    /**
     * Navigates cursor up or down when in custom remapping mode.
     *
     * @param dir Navigation offset (-1 or +1).
     */
    public function navigate(dir:Int) {
        remapIndex = (remapIndex + dir + remapItems.length) % remapItems.length;
        AudioManager.inst.playMenuBeep(380, 0.04);
        updateRemapStyles();
    }

    /**
     * Refreshes keycap and gamepad button name representations in remapping list.
     */
    public function updateRemapStyles() {
        var isGamepad = (currentTab == Gamepad);
        var b = inputRef.bindings;
        var sensPct = Math.round(inputRef.steerSensitivity * 100);
        var labels = [
            "Steering Sensitivity: " + sensPct + "%  [ < / > ]",
            "Throttle (Gas):       " + (isGamepad ? InputController.getGamepadBtnName(b.padGas) : InputController.getKeyName(b.keyGas)),
            "Brake / Reverse:      " + (isGamepad ? InputController.getGamepadBtnName(b.padBrake) : InputController.getKeyName(b.keyBrake)),
            "Steer Left:           " + (isGamepad ? "Left Analog / D-Pad" : InputController.getKeyName(b.keyLeft)),
            "Steer Right:          " + (isGamepad ? "Left Analog / D-Pad" : InputController.getKeyName(b.keyRight)),
            "Handbrake (Drift):    " + (isGamepad ? InputController.getGamepadBtnName(b.padHandbrake) : InputController.getKeyName(b.keyHandbrake)),
            "Nitro Boost:          " + (isGamepad ? InputController.getGamepadBtnName(b.padBoost) : InputController.getKeyName(b.keyBoost)),
            "[RESET TO DEFAULTS]"
        ];

        for (i in 0...remapItems.length) {
            var item = remapItems[i];
            if (i == remapIndex) {
                item.textColor = UITheme.COLOR_ACCENT_CYAN;
                item.text = "> " + labels[i] + " <";
            } else {
                item.textColor = (i == 7) ? 0xE5C07B : UITheme.COLOR_TEXT_NORMAL;
                item.text = "  " + labels[i] + "  ";
            }
        }
    }

    /**
     * Positions diagram viewer, header toggle buttons, and remapping items relative to modal card bounds.
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

        var headerY = effectiveCardY + 70.0;
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

        if (diagramViewer != null) {
            diagramViewer.x = effectiveCardX + (effectiveCardW * 0.5);
            diagramViewer.y = effectiveCardY + 310.0;
            diagramViewer.setScale(0.92);
        }

        var remapStartY = headerY + 48.0;
        if (remapStatusNotice != null) {
            remapStatusNotice.x = (sw - remapStatusNotice.textWidth) * 0.5;
            remapStatusNotice.y = remapStartY;
        }

        var itemsStartY = remapStartY + 26.0;
        for (i in 0...remapItems.length) {
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
