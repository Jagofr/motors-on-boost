package ui;

import ui.nodes.UINodes.UIFont as Font;
import ui.nodes.UINodes.UIText as Text;

/**
 * Virtual typography descriptors matching the HTML5/CSS3 DOM overlay stylesheet (`ui-overlay.css`).
 */
class FontManager {
    public static var regularFont:Font;
    public static var titleFont:Font;
    public static var heroFont:Font;
    public static var iconFont:Font;
    public static var largeIconFont:Font;

    public static inline var ICON_VOLUME:String    = "\uE050";
    public static inline var ICON_MUTE:String      = "\uE04F";
    public static inline var ICON_MUSIC:String     = "\uE405";
    public static inline var ICON_SFX:String       = "\uE1B8";
    public static inline var ICON_GAMEPAD:String   = "\uEB4C";
    public static inline var ICON_KEYBOARD:String  = "\uE312";
    public static inline var ICON_GRAPHICS:String  = "\uE429";
    public static inline var ICON_SETTINGS:String  = "\uE8B8";
    public static inline var ICON_PLAY:String      = "\uE037";
    public static inline var ICON_RESTART:String   = "\uE042";
    public static inline var ICON_CREDITS:String   = "\uE88E";
    public static inline var ICON_EXIT:String      = "\uE879";
    public static inline var ICON_CHECK_ON:String  = "\uE834";
    public static inline var ICON_CHECK_OFF:String = "\uE835";
    public static inline var ICON_BACK:String      = "\uE5C4";

    public static inline var BLOCK_FILLED:String   = "■";
    public static inline var BLOCK_EMPTY:String    = "□";

    private static var initialized:Bool = false;

    public static function init():Void {
        if (initialized) return;
        initialized = true;
        regularFont = new Font("Stack Sans Headline", 21);
        titleFont = new Font("Stack Sans Headline", 34);
        heroFont = new Font("Stack Sans Headline", 46);
        iconFont = new Font("Material Symbols Rounded", 22);
        largeIconFont = new Font("Material Symbols Rounded", 32);
    }

    /** Creates an isolated font descriptor with safe non-NaN metrics. */
    public static function getScaled(baseFont:Font, targetSize:Int):Font {
        var f = baseFont != null ? baseFont.clone() : new Font("Stack Sans Headline", targetSize);
        f.resizeTo(targetSize);
        return f;
    }

    /** Computes safe bounding metrics for text elements. */
    public static function applySafeMetrics(textObj:Text):Void {
        if (textObj == null || textObj.font == null) return;
        if (Math.isNaN(textObj.font.lineHeight) || textObj.font.lineHeight <= 0) {
            textObj.font.lineHeight = textObj.font.size * 1.25;
        }
    }
}
