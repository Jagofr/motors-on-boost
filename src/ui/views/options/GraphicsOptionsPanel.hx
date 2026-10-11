package ui.views.options;

import h2d.Object;
import h2d.Text;
import h2d.Interactive;
import ui.FontManager;
import ui.components.UITheme;
import save.SaveSystem.GraphicsSettings;
import graphics.GraphicsManager;
import audio.AudioManager;

/**
 * Graphics hardware and rendering quality settings subpanel view.
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

    public static var NAMES:Array<String> = [
        "Textures", "Shadow Level", "Shadow Res", "Lighting", "Lighting Res",
        "Mipmapping", "Anisotropy", "Anti-Aliasing", "AA Level", "Model Geometry",
        "Reflections", "Reflection Level", "Render Scale", "UI Resolution"
    ];

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
            inter.onWheel = function(e:hxd.Event) {
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
     * @param idx Option index.
     * @return True if the option should be grayed out and non-interactive.
     */
    public function isOptionDisabled(idx:Int):Bool {
        switch (idx) {
            case 2: return settings.shadowLevel == "Off";
            case 6: return !settings.mipmapping;
            case 8: return settings.aaType == "None";
            case 11: return !settings.modelReflections;
            default: return false;
        }
    }

    /**
     * Cycles an option setting in forward (+1) or backward (-1) direction.
     *
     * @param idx Option index.
     * @param dir Direction multiplier.
     */
    public function cycleOption(idx:Int, dir:Int) {
        if (isOptionDisabled(idx)) {
            AudioManager.inst.playMenuBeep(220.0, 0.05);
            return;
        }

        AudioManager.inst.playMenuBeep(AUDIO_CYCLE_FREQ, 0.05);
        var s = settings;

        switch (idx) {
            case 0:
                if (isOpenedFromPause) return;
                var list = ["Off", "Very Low", "Low", "Medium", "High", "Ultra", "Unreal"];
                s.textures = cycleArray(list, s.textures, dir);
            case 1:
                var list = ["Off", "Normal", "High", "Ultra", "Dynamic"];
                s.shadowLevel = cycleArray(list, s.shadowLevel, dir);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyShadows();
            case 2:
                var list = [512, 1024, 2048, 4096];
                s.shadowRes = cycleArray(list, s.shadowRes, dir);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyShadows();
            case 3:
                if (isOpenedFromPause) return;
                var list = ["Low", "Medium", "High", "Ultra (RTX/Path)"];
                s.lightingLevel = cycleArray(list, s.lightingLevel, dir);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyLighting();
            case 4:
                var list = [512, 1024, 2048];
                s.lightingRes = cycleArray(list, s.lightingRes, dir);
            case 5:
                if (isOpenedFromPause) return;
                s.mipmapping = !s.mipmapping;
            case 6:
                if (isOpenedFromPause) return;
                var list = [1, 2, 4, 8, 16];
                s.anisotropic = cycleArray(list, s.anisotropic, dir);
            case 7:
                var list = ["None", "FXAA", "TSAA", "SMAA", "MSAA"];
                s.aaType = cycleArray(list, s.aaType, dir);
            case 8:
                var list = [2, 4, 8];
                s.aaLevel = cycleArray(list, s.aaLevel, dir);
            case 9:
                if (isOpenedFromPause) return;
                var list = ["Very Low", "Low", "Medium", "High", "Ultra"];
                s.modelGeometry = cycleArray(list, s.modelGeometry, dir);
            case 10:
                s.modelReflections = !s.modelReflections;
            case 11:
                var list = ["Low", "Medium", "High", "Ultra"];
                s.reflectionLevel = cycleArray(list, s.reflectionLevel, dir);
            case 12:
                var list = [0.25, 0.334, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0];
                s.renderScale = cycleArray(list, s.renderScale, dir);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyRenderScale();
            case 13:
                var list = ["720p (HD)", "1080p (FHD)", "1440p (2K)", "2160p (4K)", "Native / Match Window"];
                s.uiResolution = cycleArray(list, s.uiResolution, dir);
                if (GraphicsManager.inst != null) GraphicsManager.inst.applyUIResolution();
                if (onUIResolutionChanged != null) onUIResolutionChanged();
        }

        updateStyles();
    }

    function cycleArray<T>(arr:Array<T>, curr:T, dir:Int):T {
        var idx = arr.indexOf(curr);
        if (idx == -1) idx = 0;
        var next = (idx + dir + arr.length) % arr.length;
        return arr[next];
    }

    /**
     * Navigates cursor up or down with automated viewport scrolling.
     *
     * @param dir Navigation offset (-1 or +1).
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
     * @param dir Scroll direction delta (-1 or +1).
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
        var s = settings;
        var inGameLocked = isOpenedFromPause;

        var shadowResStr = isOptionDisabled(2) ? "[DISABLED]" : (s.shadowRes + "p");
        var anisoStr = isOptionDisabled(6) ? "[DISABLED]" : (s.anisotropic + "x");
        var aaLevelStr = isOptionDisabled(8) ? "[DISABLED]" : (s.aaLevel + "x");
        var reflLevelStr = isOptionDisabled(11) ? "[DISABLED]" : s.reflectionLevel;

        var vals = [
            s.textures + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.shadowLevel,
            shadowResStr,
            s.lightingLevel + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.lightingRes + "p",
            (s.mipmapping ? "Enabled" : "Disabled") + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            anisoStr + (inGameLocked && !isOptionDisabled(6) ? " [LOCKED IN-RUN]" : ""),
            s.aaType,
            aaLevelStr,
            s.modelGeometry + (inGameLocked ? " [LOCKED IN-RUN]" : ""),
            s.modelReflections ? "Active" : "Disabled",
            reflLevelStr,
            s.renderScale + "x (" + Math.round(s.renderScale * 100) + "%)",
            s.uiResolution
        ];

        var titles = [
            "Texture Fidelity:    ", "Shadow Quality:      ", "Shadow Buffer:       ", "Lighting Pipeline:   ", "Light Buffer:        ",
            "Mipmapping Filters:  ", "Anisotropy Sampling: ", "Anti-Aliasing Pass:  ", "AA Multiplier:       ", "Model Geometry LOD:  ",
            "Screen Reflections:  ", "Reflection Updates:  ", "3D Render Resolution:", "UI Interface Target: "
        ];

        for (i in 0...items.length) {
            var item = items[i];
            var isLocked = inGameLocked && (i == 0 || i == 3 || i == 5 || i == 6 || i == 9);
            var isDisabled = isOptionDisabled(i);

            if (i == selectedIndex) {
                if (isDisabled) {
                    item.textColor = UITheme.COLOR_TEXT_DISABLED;
                } else if (isLocked) {
                    item.textColor = UITheme.COLOR_TEXT_MUTED;
                } else {
                    item.textColor = UITheme.COLOR_ACCENT_CYAN;
                }
                item.text = "> " + titles[i] + vals[i] + " <";
            } else {
                if (isDisabled) {
                    item.textColor = UITheme.COLOR_TEXT_DISABLED;
                } else if (isLocked) {
                    item.textColor = UITheme.COLOR_TEXT_MUTED;
                } else {
                    item.textColor = UITheme.COLOR_TEXT_NORMAL;
                }
                item.text = "  " + titles[i] + vals[i] + "  ";
            }
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
}
