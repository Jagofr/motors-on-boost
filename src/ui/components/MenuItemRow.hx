package ui.components;

import h2d.Object;
import h2d.Text;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Interactive;
import ui.FontManager;

/**
 * Reusable menu item row combining an icon, text label, and interactive hitzone.
 * Formatted with styling defaults driven by `UITheme`.
 */
class MenuItemRow extends Object {
    /** Icon bitmap display. */
    public var iconBmp:Bitmap;

    /** Text label display. */
    public var labelTxt:Text;

    /** Mouse/pointer interactive hit area. */
    public var interactive:Interactive;

    /** Default interactive width for standard menu rows. */
    public static inline var DEFAULT_WIDTH:Float = 440.0;

    /** Default interactive height for standard menu rows. */
    public static inline var DEFAULT_HEIGHT:Float = 44.0;

    /**
     * Instantiates an interactive menu item row.
     *
     * @param iconTile Icon texture tile to display.
     * @param label Text caption of the option.
     * @param width Width of the interactive hit area.
     * @param height Height of the interactive hit area.
     * @param parent Optional parent 2D scene object.
     */
    public function new(iconTile:Tile, label:String, width:Float = DEFAULT_WIDTH, height:Float = DEFAULT_HEIGHT, ?parent:Object) {
        super(parent);

        iconBmp = new Bitmap(iconTile, this);
        labelTxt = new Text(FontManager.regularFont, this);
        labelTxt.text = label;

        interactive = new Interactive(width, height, this);
    }

    /**
     * Styles the row elements based on selection and enabled states.
     *
     * @param isSelected True if the row is currently highlighted/focused.
     * @param isEnabled True if the option can be triggered.
     * @param activeColor Color applied when focused.
     * @param normalColor Color applied when idle.
     * @param disabledColor Color applied when inactive/disabled.
     */
    public function setStyle(
        isSelected:Bool,
        isEnabled:Bool = true,
        activeColor:Int = UITheme.COLOR_ACCENT_CYAN,
        normalColor:Int = UITheme.COLOR_TEXT_NORMAL,
        disabledColor:Int = UITheme.COLOR_TEXT_DISABLED
    ) {
        if (!isEnabled) {
            labelTxt.textColor = disabledColor;
            iconBmp.color.setColor(disabledColor);
            return;
        }

        if (isSelected) {
            labelTxt.textColor = activeColor;
            iconBmp.color.setColor(activeColor);
        } else {
            labelTxt.textColor = normalColor;
            iconBmp.color.setColor(UITheme.COLOR_TEXT_MUTED);
        }
    }
}
