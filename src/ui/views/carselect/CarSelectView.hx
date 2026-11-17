package ui.views.carselect;

import ui.nodes.UINodes.UIObject as Object;
import ui.nodes.UINodes.UIText as Text;
import ui.nodes.UINodes.UIInteractive as Interactive;
import ui.FontManager;
import ui.components.UITheme;
import physics.CarConfig;
import world.WorldManager.MapMode;
import audio.AudioManager;

/**
 * Singleplayer vehicle selection and paint customization screen view.
 * Allows selecting one of 3 distinct chassis/drivetrain archetypes:
 *   0: GT Race Car (AWD)
 *   1: Sports Hatch (FWD)
 *   2: Low Sports Coupe (RWD)
 * plus optional paint color swatch customization before launching the chosen map.
 *
 * @class CarSelectView
 * @extends ui.nodes.UINodes.UIObject
 * @module ui/views/carselect/CarSelectView
 */
@:keep
class CarSelectView extends Object {
    public var titleText:Text;
    public var subtitleText:Text;
    public var backBtnText:Text;
    public var backInteractive:Interactive;

    /** Target map chosen in MapSelect before entering CarSelect. */
    public var targetMap:MapMode = Circuit;

    /** Currently selected car archetype index (0: Race AWD, 1: Hatch FWD, 2: Coupe RWD). */
    public var selectedCarIndex:Int = 0;

    /** Currently selected paint color swatch index into `CarConfig.PAINT_PALETTE`. */
    public var selectedColorIndex:Int = 0;

    /** Keyboard/controller focus row (0 = Vehicle Cards, 1 = Paint Swatches). */
    public var focusRow:Int = 0;

    /** True once the player explicitly picks a custom paint color on this screen. */
    public var hasCustomColor:Bool = false;

    public var carTitles:Array<Text> = [];
    public var carTags:Array<Text> = [];
    public var carDescs:Array<Text> = [];
    public var carInteractives:Array<Interactive> = [];

    public var onCarSelected:Null<MapMode -> String -> Int -> Void>;
    public var onPreviewChanged:Null<String -> Int -> Void>;
    public var onBack:Null<Void -> Void>;
    public var onSelectionChanged:Null<Void -> Void>;

    public function new(?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.titleFont, this);
        titleText.text = "GARAGE // SELECT VEHICLE";
        titleText.textColor = UITheme.COLOR_ACCENT_CYAN;

        subtitleText = new Text(FontManager.regularFont, this);
        subtitleText.text = "CHOOSE DRIVETRAIN & PAINT COLOR";
        subtitleText.textColor = UITheme.COLOR_TEXT_MUTED;

        backBtnText = new Text(FontManager.regularFont, this);
        backBtnText.text = "< BACK";
        backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;

        backInteractive = new Interactive(UITheme.BACK_BUTTON_WIDTH, UITheme.BACK_BUTTON_HEIGHT, this);
        backInteractive.onClick = function(_) {
            if (visible && onBack != null) {
                AudioManager.inst.playMenuBeep(320.0, 0.06);
                onBack();
            }
        };

        for (i in 0...CarConfig.VEHICLE_PRESETS.length) {
            var meta = CarConfig.VEHICLE_PRESETS[i];
            var tTitle = new Text(FontManager.titleFont, this);
            tTitle.text = meta.name + " (" + meta.drivetrain + ")";
            carTitles.push(tTitle);

            var tTag = new Text(FontManager.regularFont, this);
            tTag.text = meta.tag;
            carTags.push(tTag);

            var tDesc = new Text(FontManager.regularFont, this);
            tDesc.text = meta.desc;
            carDescs.push(tDesc);

            var inter = new Interactive(250, 260, this);
            inter.onClick = function(_) {
                if (visible) selectCar(i);
            };
            carInteractives.push(inter);
        }

        updateStyles();
    }

    public function activate(mapMode:MapMode, ?savedCarId:String, ?savedPaintHex:Null<Int>):Void {
        targetMap = mapMode;
        visible = true;
        focusRow = 0;

        if (savedCarId != null) {
            selectedCarIndex = CarConfig.getPresetIndex(savedCarId);
        }
        var meta = CarConfig.VEHICLE_PRESETS[selectedCarIndex];
        if (savedPaintHex != null) {
            var cIdx = CarConfig.getColorIndex(savedPaintHex);
            if (cIdx >= 0) {
                selectedColorIndex = cIdx;
                hasCustomColor = (savedPaintHex != meta.defaultColorHex);
            } else {
                selectedColorIndex = meta.defaultColorIdx;
                hasCustomColor = false;
            }
        } else if (!hasCustomColor) {
            selectedColorIndex = meta.defaultColorIdx;
        }

        subtitleText.text = (mapMode == Sandbox ? "SANDBOX PROVING GROUNDS" : "HIGHWAY CIRCUIT") + "  //  SELECT CAR & PAINT";
        updateStyles();
        emitPreview();
    }

    public inline function getSelectedCarId():String {
        return CarConfig.VEHICLE_PRESETS[selectedCarIndex].id;
    }

    public inline function getSelectedColorHex():Int {
        return CarConfig.PAINT_PALETTE[selectedColorIndex].hex;
    }

    public function selectCar(idx:Int):Void {
        var count = CarConfig.VEHICLE_PRESETS.length;
        selectedCarIndex = ((idx % count) + count) % count;
        if (!hasCustomColor) {
            selectedColorIndex = CarConfig.VEHICLE_PRESETS[selectedCarIndex].defaultColorIdx;
        }
        AudioManager.inst.playMenuBeep(390.0, 0.04);
        updateStyles();
        emitPreview();
        if (onSelectionChanged != null) onSelectionChanged();
    }

    public function navigate(dir:Int):Void {
        selectCar(selectedCarIndex + dir);
    }

    public function selectColor(idx:Int):Void {
        var count = CarConfig.PAINT_PALETTE.length;
        selectedColorIndex = ((idx % count) + count) % count;
        hasCustomColor = true;
        AudioManager.inst.playMenuBeep(440.0, 0.04);
        updateStyles();
        emitPreview();
        if (onSelectionChanged != null) onSelectionChanged();
    }

    public function cycleColor(dir:Int):Void {
        selectColor(selectedColorIndex + dir);
    }

    public function toggleFocusRow(dir:Int):Void {
        focusRow = (focusRow == 0) ? 1 : 0;
        AudioManager.inst.playMenuBeep(340.0, 0.03);
        if (onSelectionChanged != null) onSelectionChanged();
    }

    public function confirmSelection():Void {
        AudioManager.inst.playMenuBeep(540.0, 0.08);
        if (onCarSelected != null) {
            onCarSelected(targetMap, getSelectedCarId(), getSelectedColorHex());
        }
    }

    function emitPreview():Void {
        if (onPreviewChanged != null) {
            onPreviewChanged(getSelectedCarId(), getSelectedColorHex());
        }
    }

    public function updateStyles():Void {
        for (i in 0...carTitles.length) {
            var isSel = (i == selectedCarIndex);
            carTitles[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : 0xFFFFFF;
            carTags[i].textColor = isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_TEXT_MUTED;
            carDescs[i].textColor = isSel ? UITheme.COLOR_TEXT_NORMAL : UITheme.COLOR_TEXT_MUTED;
        }
    }

    public function layout(sw:Float, sh:Float):Void {
        var cardW = Math.min(920.0, sw - 32.0);
        var cardH = Math.min(540.0, sh - 100.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(60.0, (sh - cardH) * 0.5 + 6.0);

        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = Math.max(12.0, cardY - 46.0);
        }
        if (subtitleText != null) {
            subtitleText.x = (sw - subtitleText.textWidth) * 0.5;
            subtitleText.y = cardY + 18.0;
        }
        if (backBtnText != null && backInteractive != null) {
            backBtnText.x = cardX + 24.0;
            backBtnText.y = cardY + 18.0;
            backInteractive.x = cardX + 16.0;
            backInteractive.y = cardY + 10.0;
        }

        var count = carTitles.length;
        var padX = 24.0;
        var gap = 16.0;
        var colW = (cardW - padX * 2.0 - gap * (count - 1)) / count;
        var boxY = cardY + 66.0;
        var boxH = cardH - 160.0;

        for (i in 0...count) {
            var cx = cardX + padX + i * (colW + gap);
            carTitles[i].x = cx + 14.0;
            carTitles[i].y = boxY + 16.0;
            carTags[i].x = cx + 14.0;
            carTags[i].y = boxY + 46.0;
            carDescs[i].maxWidth = colW - 28.0;
            carDescs[i].x = cx + 14.0;
            carDescs[i].y = boxY + 72.0;

            carInteractives[i].x = cx;
            carInteractives[i].y = boxY;
            carInteractives[i].width = colW;
            carInteractives[i].height = boxH;
        }
    }
}
