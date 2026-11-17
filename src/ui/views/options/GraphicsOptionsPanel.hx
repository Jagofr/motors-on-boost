package ui.views.options;

import ui.nodes.UINodes.UIObject as Object;
import ui.nodes.UINodes.UIText as Text;
import ui.nodes.UINodes.UIInteractive as Interactive;
import ui.FontManager;
import ui.components.UITheme;
import save.SaveSystem.GraphicsSettings;
import graphics.GraphicsManager;
import audio.AudioManager;

/**
 * Declarative descriptor for a single configurable graphics option row.
 *
 * @typedef {Object} GraphicsOptionDef
 * @property {String} name Short identifier name.
 * @property {String} label UI display label prefix.
 * @property {Bool} [menuOnly=false] Locks editing while inside an active run.
 * @property {Bool} [triggersLayout=false] Triggers UI re-layout when changed.
 * @property {GraphicsSettings->Bool} [disabledWhen] Predicate disabling the row.
 * @property {GraphicsSettings->String} formatValue Formats the current setting value.
 * @property {GraphicsSettings->Int->Void} cycle Advances or rewinds the option value.
 */
typedef GraphicsOptionDef = {
    var name:String;
    var label:String;
    @:optional var menuOnly:Bool;
    @:optional var triggersLayout:Bool;
    @:optional var disabledWhen:GraphicsSettings->Bool;
    var formatValue:GraphicsSettings->String;
    var cycle:GraphicsSettings->Int->Void;
}

/**
 * Graphics hardware and rendering quality settings subpanel view.
 *
 * @class GraphicsOptionsPanel
 * @extends ui.nodes.UINodes.UIObject
 */
class GraphicsOptionsPanel extends Object {
    /** Graphics option label text objects. */
    public var items:Array<Text> = [];

    /** Interactive hitzones for cycling options. */
    public var interactives:Array<Interactive> = [];

    /** Currently highlighted item index. */
    public var selectedIndex:Int = 0;

    /** Reference to active graphics settings. */
    public var settings:GraphicsSettings;

    /** True if opened during an active race. */
    public var isOpenedFromPause:Bool = false;

    /** Interactive row hitzone width in pixels. */
    public static inline var ROW_WIDTH:Float = 560.0;

    /** Interactive row hitzone height in pixels. */
    public static inline var ROW_HEIGHT:Float = 28.0;

    /** Audio frequency played when cycling graphics parameters in Hz. */
    public static inline var AUDIO_CYCLE_FREQ:Float = 480.0;

    static var OPTION_DEFS:Array<GraphicsOptionDef> = [
        {
            name: "Textures", label: "Texture Fidelity:    ", menuOnly: true,
            formatValue: s -> s.textures,
            cycle: (s, d) -> {
                s.textures = cycleArray(["Off", "Very Low", "Low", "Medium", "High", "Ultra", "Unreal"], s.textures, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyTexturesAndFiltering();
            }
        },
        {
            name: "Shadow Level", label: "Shadow Quality:      ",
            formatValue: s -> s.shadowLevel,
            cycle: (s, d) -> {
                s.shadowLevel = cycleArray(["Off", "Normal", "High", "Ultra", "Dynamic"], s.shadowLevel, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyShadows();
            }
        },
        {
            name: "Shadow Res", label: "Shadow Buffer:       ",
            disabledWhen: s -> s.shadowLevel == "Off",
            formatValue: s -> s.shadowRes + "p",
            cycle: (s, d) -> {
                s.shadowRes = cycleArray([512, 1024, 2048, 4096], s.shadowRes, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyShadows();
            }
        },
        {
            name: "Lighting", label: "Lighting Pipeline:   ", menuOnly: true,
            formatValue: s -> s.lightingLevel,
            cycle: (s, d) -> {
                s.lightingLevel = cycleArray(["Low", "Medium", "High", "Ultra (RTX/Path)"], s.lightingLevel, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyLighting();
            }
        },
        {
            name: "Lighting Res", label: "Light Buffer:        ",
            formatValue: s -> s.lightingRes + "p",
            cycle: (s, d) -> {
                s.lightingRes = cycleArray([512, 1024, 2048], s.lightingRes, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyLighting();
            }
        },
        {
            name: "Mipmapping", label: "Mipmapping Filters:  ", menuOnly: true,
            formatValue: s -> s.mipmapping ? "Enabled" : "Disabled",
            cycle: (s, _) -> {
                s.mipmapping = !s.mipmapping;
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyTexturesAndFiltering();
            }
        },
        {
            name: "Anisotropy", label: "Anisotropy Sampling: ", menuOnly: true,
            disabledWhen: s -> !s.mipmapping,
            formatValue: s -> s.anisotropic + "x",
            cycle: (s, d) -> {
                s.anisotropic = cycleArray([1, 2, 4, 8, 16], s.anisotropic, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyTexturesAndFiltering();
            }
        },
        {
            name: "Anti-Aliasing", label: "Anti-Aliasing Pass:  ",
            formatValue: s -> s.aaType,
            cycle: (s, d) -> {
                s.aaType = cycleArray(["None", "FXAA", "TSAA", "SMAA", "MSAA"], s.aaType, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyAntiAliasing();
            }
        },
        {
            name: "AA Level", label: "AA Quality:          ",
            disabledWhen: s -> s.aaType == "None" || s.aaType == "MSAA",
            formatValue: s -> formatAAQuality(s.aaType, s.aaLevel),
            cycle: (s, d) -> {
                s.aaLevel = cycleArray([2, 4, 8], s.aaLevel, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyAntiAliasing();
            }
        },
        {
            name: "Model Geometry", label: "Model Geometry LOD:  ", menuOnly: true,
            formatValue: s -> s.modelGeometry,
            cycle: (s, d) -> {
                s.modelGeometry = cycleArray(["Very Low", "Low", "Medium", "High", "Ultra"], s.modelGeometry, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyModelGeometry();
            }
        },
        {
            name: "Reflections", label: "Screen Reflections:  ",
            formatValue: s -> s.modelReflections ? "Active" : "Disabled",
            cycle: (s, _) -> {
                s.modelReflections = !s.modelReflections;
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyReflections();
            }
        },
        {
            name: "Reflection Level", label: "Reflection Updates:  ",
            disabledWhen: s -> !s.modelReflections,
            formatValue: s -> s.reflectionLevel,
            cycle: (s, d) -> {
                s.reflectionLevel = cycleArray(["Low", "Medium", "High", "Ultra"], s.reflectionLevel, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyReflections();
            }
        },
        {
            name: "Render Scale", label: "3D Render Resolution:",
            formatValue: s -> s.renderScale + "x (" + Math.round(s.renderScale * 100) + "%)",
            cycle: (s, d) -> {
                s.renderScale = cycleArray([0.25, 0.334, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0], s.renderScale, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyRenderScale();
            }
        },
        {
            name: "UI Resolution", label: "UI Interface Target: ", triggersLayout: true,
            formatValue: s -> s.uiResolution,
            cycle: (s, d) -> {
                s.uiResolution = cycleArray(["720p (HD)", "1080p (FHD)", "1440p (2K)", "2160p (4K)", "Native / Match Window"], s.uiResolution, d);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyUIResolution();
            }
        }
    ];

    /** Ordered display names corresponding to each option index. */
    public static var NAMES:Array<String> = [for (def in OPTION_DEFS) def.name];

    /** Callback notified whenever a graphics option value is modified so saves persist. */
    public var onSettingsChanged:Null<Void -> Void> = null;

    /** Callback invoked when UI resolution changes so the parent options view and UI can immediately re-layout. */
    public var onUIResolutionChanged:Void->Void;

    /** Current vertical scroll offset for compact displays. */
    public var scrollOffset:Int = 0;

    /** Maximum visible option rows fitting in the modal card. */
    public var maxVisibleRows:Int = 14;

    /** Visual scroll upward indicator hint. */
    var scrollUpHint:Text;

    /** Visual scroll downward indicator hint. */
    var scrollDownHint:Text;

    var cachedSw:Float = 1280.0;
    var cachedSh:Float = 720.0;
    var cachedCardX:Float = 0.0;
    var cachedCardY:Float = 0.0;
    var cachedCardW:Float = 920.0;
    var cachedCardH:Float = 580.0;

    /**
     * Instantiates the graphics options configuration subpanel.
     *
     * @param gfxSettings Target graphics settings record.
     * @param parent Optional parent 2D scene object.
     */
    public function new(gfxSettings:GraphicsSettings, ?parent:Object) {
        super(parent);
        this.settings = gfxSettings;

        scrollUpHint = new Text(FontManager.regularFont, this);
        scrollUpHint.text = "^  MORE OPTIONS ABOVE  ^";
        scrollUpHint.textColor = UITheme.COLOR_ACCENT_GOLD;
        scrollUpHint.visible = false;

        scrollDownHint = new Text(FontManager.regularFont, this);
        scrollDownHint.text = "v  MORE OPTIONS BELOW  v";
        scrollDownHint.textColor = UITheme.COLOR_ACCENT_GOLD;
        scrollDownHint.visible = false;

        for (i in 0...NAMES.length) {
            var txt = new Text(FontManager.regularFont, this);
            items.push(txt);

            var inter = new Interactive(ROW_WIDTH, ROW_HEIGHT, this);
            inter.onOver = function(_) {
                if (visible) {
                    selectedIndex = i;
                    updateStyles();
                }
            };
            inter.onClick = function(_) {
                if (visible) cycleOption(i, 1);
            };
            inter.onWheel = function(e:ui.nodes.UINodes.UIEvent) {
                if (visible) {
                    if (e.wheelDelta > 0) scroll(-1);
                    else if (e.wheelDelta < 0) scroll(1);
                }
            };
            interactives.push(inter);
        }
    }

    /**
     * Checks if a graphics setting is currently disabled due to its parent option setting.
     *
     * @param {Int} idx Option index.
     * @returns {Bool} True if the option should be grayed out and non-interactive.
     */
    public function isOptionDisabled(idx:Int):Bool {
        if (idx < 0 || idx >= OPTION_DEFS.length) return false;
        var pred = OPTION_DEFS[idx].disabledWhen;
        return (pred != null) ? pred(settings) : false;
    }

    /**
     * Checks if an option requires returning to main menu to modify during an active run.
     */
    public function isOptionMenuOnly(idx:Int):Bool {
        if (idx < 0 || idx >= OPTION_DEFS.length) return false;
        return OPTION_DEFS[idx].menuOnly == true;
    }

    /**
     * Cycles an option setting in forward (+1) or backward (-1) direction.
     *
     * @param {Int} idx Option index.
     * @param {Int} dir Direction multiplier.
     */
    public function cycleOption(idx:Int, dir:Int) {
        if (idx < 0 || idx >= OPTION_DEFS.length) return;
        if (isOptionDisabled(idx)) {
            AudioManager.inst.playMenuBeep(220.0, 0.05);
            return;
        }

        AudioManager.inst.playMenuBeep(AUDIO_CYCLE_FREQ, 0.05);
        var def = OPTION_DEFS[idx];
        if (isOpenedFromPause && def.menuOnly == true) return;

        def.cycle(settings, dir);
        if (def.triggersLayout == true && onUIResolutionChanged != null) {
            onUIResolutionChanged();
        }
        updateStyles();
        if (onSettingsChanged != null) onSettingsChanged();
    }

    static function cycleArray<T>(arr:Array<T>, curr:T, dir:Int):T {
        var idx = arr.indexOf(curr);
        if (idx == -1) idx = 0;
        var next = (idx + dir + arr.length) % arr.length;
        return arr[next];
    }

    /**
     * Navigates cursor up or down with automated viewport scrolling.
     *
     * @param {Int} dir Navigation offset (-1 or +1).
     */
    public function navigate(dir:Int) {
        selectedIndex = (selectedIndex + dir + items.length) % items.length;
        AudioManager.inst.playMenuBeep(380, 0.04);
        adjustScrollForSelected();
        layoutCached();
        updateStyles();
    }

    /**
     * Scrolls the visible option rows up or down.
     *
     * @param {Int} dir Scroll direction delta (-1 or +1).
     */
    public function scroll(dir:Int) {
        var maxScroll = Math.max(0, items.length - maxVisibleRows);
        scrollOffset = Math.round(Math.max(0, Math.min(maxScroll, scrollOffset + dir)));
        layoutCached();
        updateStyles();
    }

    /**
     * Adjusts scroll offset so the currently selected row stays visible in the viewport.
     */
    function adjustScrollForSelected() {
        if (selectedIndex < scrollOffset) {
            scrollOffset = selectedIndex;
        } else if (selectedIndex >= scrollOffset + maxVisibleRows) {
            scrollOffset = selectedIndex - maxVisibleRows + 1;
        }
    }

    function layoutCached() {
        layout(cachedSw, cachedSh, cachedCardX, cachedCardY, cachedCardW, cachedCardH);
    }

    /**
     * Refreshes text displays and highlights.
     */
    public function updateStyles() {
        var inGameLocked = isOpenedFromPause;

        for (i in 0...items.length) {
            var def = OPTION_DEFS[i];
            var item = items[i];
            var isDisabled = isOptionDisabled(i);
            var isMenuOnly = (def.menuOnly == true);
            var isLocked = inGameLocked && isMenuOnly;

            var valueStr = isDisabled ? "[DISABLED]" : def.formatValue(settings);
            if (!isDisabled && isLocked) valueStr += " [LOCKED IN-RUN]";

            if (isDisabled) {
                item.textColor = UITheme.COLOR_TEXT_DISABLED;
            } else if (isLocked) {
                item.textColor = UITheme.COLOR_TEXT_MUTED;
            } else if (i == selectedIndex) {
                item.textColor = UITheme.COLOR_ACCENT_CYAN;
            } else {
                item.textColor = UITheme.COLOR_TEXT_NORMAL;
            }

            var prefix = (i == selectedIndex) ? "> " : "  ";
            var suffix = (i == selectedIndex) ? " <" : "  ";
            item.text = prefix + def.label + valueStr + suffix;
        }
    }

    /**
     * Positions text rows and interactive hitboxes relative to modal card bounds.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     * @param cardX Modal card left coordinate.
     * @param cardY Modal card top coordinate.
     * @param cardW Modal card width.
     * @param cardH Modal card height.
     */
    public function layout(sw:Float, sh:Float, cardX:Float = 0, cardY:Float = 0, cardW:Float = 0, cardH:Float = 0) {
        cachedSw = sw;
        cachedSh = sh;
        cachedCardX = (cardW > 0) ? cardX : (sw - UITheme.OPTIONS_CARD_WIDTH) * 0.5;
        cachedCardY = (cardH > 0) ? cardY : sh * 0.16;
        cachedCardW = (cardW > 0) ? cardW : UITheme.OPTIONS_CARD_WIDTH;
        cachedCardH = (cardH > 0) ? cardH : UITheme.OPTIONS_CARD_HEIGHT;

        var availableH = cachedCardH - 110.0;
        maxVisibleRows = Math.floor(availableH / ROW_HEIGHT);
        if (maxVisibleRows < 4) maxVisibleRows = 4;
        if (maxVisibleRows > items.length) maxVisibleRows = items.length;

        adjustScrollForSelected();

        var startY = cachedCardY + 68.0;

        for (i in 0...items.length) {
            var item = items[i];
            var inter = interactives[i];
            var isVisible = (i >= scrollOffset && i < scrollOffset + maxVisibleRows);
            item.visible = isVisible;
            inter.visible = isVisible;

            if (isVisible) {
                var rowY = startY + ((i - scrollOffset) * ROW_HEIGHT);
                item.x = (sw - item.textWidth) * 0.5;
                item.y = rowY;
                inter.x = cachedCardX + (cachedCardW - ROW_WIDTH) * 0.5;
                inter.y = rowY;
                inter.width = Math.min(ROW_WIDTH, cachedCardW - 40.0);
                inter.height = ROW_HEIGHT;
            }
        }

        if (scrollUpHint != null) {
            scrollUpHint.visible = (scrollOffset > 0);
            if (scrollUpHint.visible) {
                scrollUpHint.x = (sw - scrollUpHint.textWidth) * 0.5;
                scrollUpHint.y = startY - 20.0;
            }
        }

        if (scrollDownHint != null) {
            scrollDownHint.visible = (scrollOffset + maxVisibleRows < items.length);
            if (scrollDownHint.visible) {
                scrollDownHint.x = (sw - scrollDownHint.textWidth) * 0.5;
                scrollDownHint.y = startY + (maxVisibleRows * ROW_HEIGHT) + 2.0;
            }
        }
    }

    /** Formats the AA Quality / Scale readout appropriately per anti-aliasing algorithm. */
    public static function formatAAQuality(aaType:String, aaLevel:Int):String {
        return switch (aaType) {
            case "FXAA" | "SMAA": switch (aaLevel) {
                case 2: "Low";
                case 4: "Medium";
                case 8: "High";
                default: "Medium";
            };
            case "TSAA": switch (aaLevel) {
                case 2: "8x";
                case 4: "16x";
                case 8: "32x";
                default: "16x";
            };
            case "MSAA": "4x (Fixed)";
            default: aaLevel + "x";
        };
    }
}
