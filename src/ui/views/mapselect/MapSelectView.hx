package ui.views.mapselect;

import ui.nodes.UINodes.UIObject as Object;
import ui.nodes.UINodes.UIText as Text;
import ui.nodes.UINodes.UIBitmap as Bitmap;
import ui.nodes.UINodes.UIInteractive as Interactive;
import ui.FontManager;
import ui.UIIcons;
import ui.components.UITheme;
import ui.components.UIEnums.MenuAction;
import audio.AudioManager;

/**
 * Singleplayer map selection screen view.
 * Allows the player to choose between the Highway Circuit and Open Sandbox Proving Grounds
 * before starting a singleplayer driving session.
 *
 * @class MapSelectView
 * @extends ui.nodes.UINodes.UIObject
 * @module ui/views/mapselect/MapSelectView
 */
@:keep
class MapSelectView extends Object {
    /** Screen header title text. */
    public var titleText:Text;

    /** Screen header subtitle text. */
    public var subtitleText:Text;

    /** Back button text and interactive hitzone. */
    public var backBtnText:Text;
    public var backInteractive:Interactive;

    /** Map titles, tags, descriptions, and launch button labels. */
    public var mapTitles:Array<Text> = [];
    public var mapTags:Array<Text> = [];
    public var mapDescs:Array<Text> = [];
    public var mapLaunchLabels:Array<Text> = [];
    public var mapIcons:Array<Bitmap> = [];
    public var mapInteractives:Array<Interactive> = [];

    /** Dispatched actions corresponding to each map card. */
    public static var MAP_ACTIONS:Array<MenuAction> = [
        StartGame,
        StartSandbox
    ];

    /** Currently selected map index (0: Highway Circuit, 1: Sandbox Proving Grounds). */
    public var selectedIndex:Int = 0;

    /** Callback invoked when a map is confirmed to start the session. */
    public var onMapSelected:MenuAction->Void;

    /** Callback invoked when the user returns to the main menu. */
    public var onBack:Void->Void;

    /** Callback invoked when selection focus changes so backplate cards redraw. */
    public var onSelectionChanged:Void->Void;

    /**
     * Instantiates the singleplayer map selection screen view.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.titleFont, this);
        titleText.text = "SINGLEPLAYER // SELECT MAP";
        titleText.textColor = UITheme.COLOR_ACCENT_CYAN;

        subtitleText = new Text(FontManager.regularFont, this);
        subtitleText.text = "CHOOSE DRIVING ENVIRONMENT";
        subtitleText.textColor = UITheme.COLOR_TEXT_MUTED;

        backBtnText = new Text(FontManager.regularFont, this);
        backBtnText.text = "< BACK";
        backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;

        backInteractive = new Interactive(UITheme.BACK_BUTTON_WIDTH, UITheme.BACK_BUTTON_HEIGHT, this);
        backInteractive.onOver = function(_) {
            if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_GOLD;
        };
        backInteractive.onOut = function(_) {
            if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;
        };
        backInteractive.onClick = function(_) {
            if (visible && onBack != null) {
                AudioManager.inst.playMenuBeep(320.0, 0.06);
                onBack();
            }
        };

        var titles = [
            "HIGHWAY CIRCUIT",
            "SANDBOX PROVING GROUNDS"
        ];
        var tags = [
            "CIRCUIT RACE  |  TRAFFIC AI  |  3 LAPS",
            "FREE ROAM  |  400m x 400m  |  STUNT TERRAIN"
        ];
        var descs = [
            "High-speed 4-lane highway loop with street lights, guardrails, and two-way traffic.",
            "Open proving grounds with cyber-grid hills, 12.5m mountain pass, and stunt ramps."
        ];
        var iconTypes = [
            UIIcons.IconType.Play,
            UIIcons.IconType.Sandbox
        ];

        for (i in 0...2) {
            var ic = new Bitmap(UIIcons.get(iconTypes[i], UITheme.ICON_SIZE_MENU, UITheme.COLOR_ACCENT_CYAN), this);
            mapIcons.push(ic);

            var tTitle = new Text(FontManager.titleFont, this);
            tTitle.text = titles[i];
            mapTitles.push(tTitle);

            var tTag = new Text(FontManager.regularFont, this);
            tTag.text = tags[i];
            mapTags.push(tTag);

            var tDesc = new Text(FontManager.regularFont, this);
            tDesc.text = descs[i];
            tDesc.lineSpacing = 2.0;
            mapDescs.push(tDesc);

            var tLaunch = new Text(FontManager.regularFont, this);
            tLaunch.text = (i == 0) ? "LAUNCH HIGHWAY CIRCUIT >" : "LAUNCH SANDBOX MAP >";
            mapLaunchLabels.push(tLaunch);

            var inter = new Interactive(360, 320, this);
            inter.onOver = function(_) {
                if (visible && selectedIndex != i) {
                    selectedIndex = i;
                    updateStyles();
                    if (onSelectionChanged != null) onSelectionChanged();
                }
            };
            inter.onClick = function(_) {
                if (visible) {
                    selectedIndex = i;
                    updateStyles();
                    if (onSelectionChanged != null) onSelectionChanged();
                    confirmSelection();
                }
            };
            mapInteractives.push(inter);
        }

        updateStyles();
    }

    /**
     * Activates the map selection screen.
     */
    public function activate() {
        visible = true;
        updateStyles();
    }

    /**
     * Navigates between available map cards.
     *
     * @param dir Navigation direction offset (-1 or +1).
     */
    public function navigate(dir:Int) {
        var count = MAP_ACTIONS.length;
        selectedIndex = (selectedIndex + dir + count) % count;
        AudioManager.inst.playMenuBeep(380.0, 0.04);
        updateStyles();
        if (onSelectionChanged != null) onSelectionChanged();
    }

    /**
     * Confirms the currently highlighted map card and starts the game session.
     */
    public function confirmSelection() {
        AudioManager.inst.playMenuBeep(520.0, 0.08);
        if (onMapSelected != null) {
            onMapSelected(MAP_ACTIONS[selectedIndex]);
        }
    }

    /**
     * Updates typography and icon colors based on active card selection.
     */
    public function updateStyles() {
        for (i in 0...2) {
            var isSel = (i == selectedIndex);
            mapTitles[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : 0xFFFFFF;
            mapTags[i].textColor = isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_TEXT_MUTED;
            mapDescs[i].textColor = isSel ? UITheme.COLOR_TEXT_NORMAL : UITheme.COLOR_TEXT_MUTED;
            mapLaunchLabels[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_TEXT_MUTED;
            mapIcons[i].color.setColor(isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_TEXT_MUTED);
        }
    }

    /**
     * Positions map cards, text descriptions, and interactive bounds relative to viewport dimensions.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        var cardW = Math.min(UITheme.MAP_SELECT_CARD_WIDTH, sw - 32.0);
        var cardH = Math.min(UITheme.MAP_SELECT_CARD_HEIGHT, sh - 110.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(68.0, (sh - cardH) * 0.5 + 8.0);

        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = Math.max(14.0, cardY - 52.0);
        }

        if (subtitleText != null) {
            subtitleText.x = (sw - subtitleText.textWidth) * 0.5;
            subtitleText.y = cardY + 20.0;
        }

        if (backBtnText != null && backInteractive != null) {
            backBtnText.x = cardX + 28.0;
            backBtnText.y = cardY + 20.0;
            backInteractive.x = cardX + 20.0;
            backInteractive.y = cardY + 12.0;
            backInteractive.width = UITheme.BACK_BUTTON_WIDTH;
            backInteractive.height = UITheme.BACK_BUTTON_HEIGHT;
        }

        var padX = 28.0;
        var gap = 24.0;
        var mapCardW = (cardW - (padX * 2.0) - gap) * 0.5;
        var mapCardH = cardH - 134.0;
        var mapCardY = cardY + 74.0;
        var prevH = Math.max(84.0, mapCardH * 0.40);

        for (i in 0...2) {
            var mx = cardX + padX + i * (mapCardW + gap);
            var contentY = mapCardY + 16.0 + prevH + 10.0;

            mapIcons[i].x = mx + 18.0;
            mapIcons[i].y = contentY + 4.0;

            mapTitles[i].x = mx + 50.0;
            mapTitles[i].y = contentY;

            mapTags[i].x = mx + 18.0;
            mapTags[i].y = contentY + 36.0;

            mapDescs[i].maxWidth = mapCardW - 36.0;
            mapDescs[i].x = mx + 18.0;
            mapDescs[i].y = contentY + 62.0;

            var pillH = 38.0;
            var pillY = mapCardY + mapCardH - pillH - 14.0;
            mapLaunchLabels[i].x = mx + (mapCardW - mapLaunchLabels[i].textWidth) * 0.5;
            mapLaunchLabels[i].y = pillY + 8.0;

            mapInteractives[i].x = mx;
            mapInteractives[i].y = mapCardY;
            mapInteractives[i].width = mapCardW;
            mapInteractives[i].height = mapCardH;
        }
    }
}

