package core;

import h2d.Font;
import hxd.res.DefaultFont;
import hxd.res.FontBuilder;

class FontManager {
    public static var regularFont:Font;
    public static var titleFont:Font;
    public static var heroFont:Font;
    public static var iconFont:Font;
    public static var largeIconFont:Font;

    // Direct Unicode codepoint characters
    public static inline var ICON_VOLUME:String    = "\uE050"; // volume_up
    public static inline var ICON_MUTE:String      = "\uE04F"; // volume_off
    public static inline var ICON_MUSIC:String     = "\uE405"; // music_note
    public static inline var ICON_SFX:String       = "\uE1B8"; // graphic_eq
    public static inline var ICON_GAMEPAD:String   = "\uEB4C"; // sports_esports
    public static inline var ICON_KEYBOARD:String  = "\uE312"; // keyboard
    public static inline var ICON_GRAPHICS:String  = "\uE429"; // tune / display
    public static inline var ICON_SETTINGS:String  = "\uE8B8"; // settings
    public static inline var ICON_PLAY:String      = "\uE037"; // play_arrow
    public static inline var ICON_RESTART:String   = "\uE042"; // replay
    public static inline var ICON_CREDITS:String   = "\uE88E"; // info / badge
    public static inline var ICON_EXIT:String      = "\uE879"; // exit_to_app
    public static inline var ICON_CHECK_ON:String  = "\uE834"; // check_box
    public static inline var ICON_CHECK_OFF:String = "\uE835"; // check_box_outline_blank
    public static inline var ICON_BACK:String      = "\uE5C4"; // arrow_back

    // Geometric UI Blocks for Sliders
    public static inline var BLOCK_FILLED:String   = "■";
    public static inline var BLOCK_EMPTY:String    = "□";

    public static function init() {
        var baseChars = hxd.Charset.DEFAULT_CHARS + "■□▲▼◄►—•⌂∞><|#[]+-%:!?/\\@$&*";

        #if js
        try {
            var stackSansName = "fonts/StackSansHeadline-VariableFont_wght.ttf";
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

            // Clean, simplified filename
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
        } catch (e:Dynamic) {
            fallbackToDefault();
        }
        #else
        fallbackToDefault();
        #end
    }

    static function fallbackToDefault() {
        regularFont = DefaultFont.get();
        titleFont = DefaultFont.get();
        heroFont = DefaultFont.get();
        iconFont = DefaultFont.get();
        largeIconFont = DefaultFont.get();
    }
}