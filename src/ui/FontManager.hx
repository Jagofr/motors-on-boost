package ui;

import h2d.Font;
import hxd.res.DefaultFont;
import hxd.res.FontBuilder;

/**
 * Typography resource manager and font cache.
 * Resolves font sizes for standard body copy, section titles, hero headings,
 * and exposes unicode glyph symbols for UI audio sliders.
 */
class FontManager {
    /** Primary body copy font (21pt). */
    public static var regularFont:Font;

    /** Section subheadings and button text font (34pt). */
    public static var titleFont:Font;

    /** Hero banners and title splash font (46pt). */
    public static var heroFont:Font;

    /** Standard iconography font fallback. */
    public static var iconFont:Font;

    /** Large iconography font fallback. */
    public static var largeIconFont:Font;

    /** Material Symbol codepoint for volume speaker. */
    public static inline var ICON_VOLUME:String    = "\uE050";

    /** Material Symbol codepoint for muted volume. */
    public static inline var ICON_MUTE:String      = "\uE04F";

    /** Material Symbol codepoint for music note. */
    public static inline var ICON_MUSIC:String     = "\uE405";

    /** Material Symbol codepoint for sound equalizer. */
    public static inline var ICON_SFX:String       = "\uE1B8";

    /** Material Symbol codepoint for gamepad controller. */
    public static inline var ICON_GAMEPAD:String   = "\uEB4C";

    /** Material Symbol codepoint for keyboard. */
    public static inline var ICON_KEYBOARD:String  = "\uE312";

    /** Material Symbol codepoint for graphics display settings. */
    public static inline var ICON_GRAPHICS:String  = "\uE429";

    /** Material Symbol codepoint for settings gear cog. */
    public static inline var ICON_SETTINGS:String  = "\uE8B8";

    /** Material Symbol codepoint for play triangle. */
    public static inline var ICON_PLAY:String      = "\uE037";

    /** Material Symbol codepoint for restart / reload arrow. */
    public static inline var ICON_RESTART:String   = "\uE042";

    /** Material Symbol codepoint for info badge / credits. */
    public static inline var ICON_CREDITS:String   = "\uE88E";

    /** Material Symbol codepoint for exit door. */
    public static inline var ICON_EXIT:String      = "\uE879";

    /** Material Symbol codepoint for checkbox active state. */
    public static inline var ICON_CHECK_ON:String  = "\uE834";

    /** Material Symbol codepoint for checkbox blank state. */
    public static inline var ICON_CHECK_OFF:String = "\uE835";

    /** Material Symbol codepoint for return back navigation. */
    public static inline var ICON_BACK:String      = "\uE5C4";

    /** Filled geometric square glyph utilized in procedural volume slider bars. */
    public static inline var BLOCK_FILLED:String   = "■";

    /** Empty geometric square glyph utilized in procedural volume slider bars. */
    public static inline var BLOCK_EMPTY:String    = "□";

    /**
     * Initializes typeface assets and builds bitmap font caches at targeted resolutions.
     */
    public static function init() {
        var baseChars = hxd.Charset.DEFAULT_CHARS + "■□▲▼◄►—•⌂∞><|#[]+-%:!?/\\@$&*\"'`;:=~";

        #if js
        try {
            var stackSansName = "fonts/stack_sans.ttf";
            regularFont = FontBuilder.getFont(stackSansName, 21, {
                chars: baseChars,
                antiAliasing: true
            });

            titleFont = FontBuilder.getFont(stackSansName, 34, {
                chars: baseChars,
                antiAliasing: true
            });

            heroFont = FontBuilder.getFont(stackSansName, 46, {
                chars: baseChars,
                antiAliasing: true
            });

            var symbolsName = "fonts/symbols.ttf";
            var iconGlyphs = ICON_VOLUME + ICON_MUTE + ICON_MUSIC + ICON_SFX +
                             ICON_GAMEPAD + ICON_KEYBOARD + ICON_GRAPHICS +
                             ICON_SETTINGS + ICON_PLAY + ICON_RESTART + ICON_CREDITS +
                             ICON_EXIT + ICON_CHECK_ON + ICON_CHECK_OFF + ICON_BACK;

            iconFont = FontBuilder.getFont(symbolsName, 22, {
                chars: iconGlyphs,
                antiAliasing: true
            });

            largeIconFont = FontBuilder.getFont(symbolsName, 32, {
                chars: iconGlyphs,
                antiAliasing: true
            });

            sanitizeAllFonts();
        } catch (e:haxe.Exception) {
            fallbackToDefault();
        }
        #else
        fallbackToDefault();
        #end
    }

    /**
     * Fallback strategy assigning Heaps built-in default bitmap font when custom TTFs fail.
     */
    static function fallbackToDefault() {
        regularFont = DefaultFont.get();
        titleFont = DefaultFont.get();
        heroFont = DefaultFont.get();
        iconFont = DefaultFont.get();
        largeIconFont = DefaultFont.get();
        sanitizeAllFonts();
    }

    /**
     * Ensures all dynamic and fallback fonts possess valid non-null baseLine and lineHeight properties.
     * Prevents textHeight calculations in Heaps h2d.Text from producing NaN when baseLine is undefined.
     */
    @:access(h2d.Font)
    static function sanitizeAllFonts() {
        var fonts = [regularFont, titleFont, heroFont, iconFont, largeIconFont];
        for (f in fonts) {
            if (f != null) {
                #if js
                if (untyped f.baseLine == null || js.Syntax.code("isNaN({0})", f.baseLine) || f.baseLine == 0) {
                    f.baseLine = f.lineHeight > 0 ? f.lineHeight : f.size;
                }
                #else
                if (f.baseLine == 0) {
                    f.baseLine = f.lineHeight > 0 ? f.lineHeight : f.size;
                }
                #end
            }
        }
    }
}