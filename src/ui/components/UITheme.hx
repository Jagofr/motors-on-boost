package ui.components;

/**
 * Design system palette and visual constants for user interface theming.
 * Centralizes theme colors, alpha transparencies, card dimensions, and layout metrics
 * so visual aesthetics can be adjusted in a single source of truth.
 */
class UITheme {
    // =========================================================================
    // COLOR PALETTE
    // =========================================================================

    /** Primary electric cyan accent used for highlights, active icons, and focus rings. */
    public static inline var COLOR_ACCENT_CYAN:Int = 0x00E5FF;

    /** Secondary warm golden amber used for pause menus, warnings, and emphasis badges. */
    public static inline var COLOR_ACCENT_GOLD:Int = 0xFFEE00;

    /** Vibrant racing orange used for hero branding logos and game titles. */
    public static inline var COLOR_ACCENT_ORANGE:Int = 0xFF9800;

    /** Primary active text color for focused options and high-contrast headings. */
    public static inline var COLOR_TEXT_ACTIVE:Int = 0x00E5FF;

    /** Default body text color for standard menu labels and content copy. */
    public static inline var COLOR_TEXT_NORMAL:Int = 0xC2D1E0;

    /** Dimmed / secondary text color for subtitles, section headers, and category tags. */
    public static inline var COLOR_TEXT_MUTED:Int = 0x8FA1B3;

    /** Inactive / disabled text color for unavailable actions (e.g. Resume with no save). */
    public static inline var COLOR_TEXT_DISABLED:Int = 0x55606E;

    /** Warning / destructive red for errors, mute statuses, and alert borders. */
    public static inline var COLOR_RED_ALERT:Int = 0xE06C75;

    /** Positive status green used for active devices and confirmed badges. */
    public static inline var COLOR_GREEN_SUCCESS:Int = 0x98C379;

    /** Dark metallic slate color used for hardware controller plastic contours. */
    public static inline var COLOR_DARK_PANEL:Int = 0x21252B;

    /** Deep obsidian card background color. */
    public static inline var COLOR_CARD_BG:Int = 0x13171F;

    // =========================================================================
    // ALPHA / TRANSPARENCY METRICS
    // =========================================================================

    /** Dimming curtain darkness behind active modals. */
    public static inline var ALPHA_MODAL_DIMMER:Float = 0.78;

    /** Translucency opacity for floating frosted card surfaces. */
    public static inline var ALPHA_CARD_SURFACE:Float = 0.88;

    /** Cyber border outline line alpha. */
    public static inline var ALPHA_CARD_BORDER:Float = 0.45;

    /** Active selected row highlight slot fill alpha. */
    public static inline var ALPHA_SLOT_FILL:Float = 0.12;

    /** Active selected row highlight slot border alpha. */
    public static inline var ALPHA_SLOT_BORDER:Float = 0.70;

    /** Options tab button selected capsule fill alpha. */
    public static inline var ALPHA_TAB_FILL:Float = 0.18;

    // =========================================================================
    // MODAL CARD DIMENSIONS & CORNER RADII
    // =========================================================================

    /** Main menu modal frame width in pixels. */
    public static inline var MAIN_CARD_WIDTH:Float = 540.0;

    /** Main menu modal frame height in pixels. */
    public static inline var MAIN_CARD_HEIGHT:Float = 360.0;

    /** Main menu modal frame corner radius in pixels. */
    public static inline var MAIN_CARD_RADIUS:Float = 14.0;

    /** Pause menu modal frame width in pixels. */
    public static inline var PAUSE_CARD_WIDTH:Float = 500.0;

    /** Pause menu modal frame height in pixels. */
    public static inline var PAUSE_CARD_HEIGHT:Float = 320.0;

    /** Pause menu modal frame corner radius in pixels. */
    public static inline var PAUSE_CARD_RADIUS:Float = 14.0;

    /** Options configuration modal frame width in pixels. */
    public static inline var OPTIONS_CARD_WIDTH:Float = 920.0;

    /** Options configuration modal frame height in pixels. */
    public static inline var OPTIONS_CARD_HEIGHT:Float = 580.0;

    /** Options configuration modal frame corner radius in pixels. */
    public static inline var OPTIONS_CARD_RADIUS:Float = 16.0;

    /** Credits screen modal frame width in pixels. */
    public static inline var CREDITS_CARD_WIDTH:Float = 860.0;

    /** Credits screen modal frame height in pixels. */
    public static inline var CREDITS_CARD_HEIGHT:Float = 610.0;

    /** Credits screen modal frame corner radius in pixels. */
    public static inline var CREDITS_CARD_RADIUS:Float = 16.0;

    // =========================================================================
    // INTERACTIVE ROW & BUTTON SIZES
    // =========================================================================

    /** Main menu option row vertical stride spacing. */
    public static inline var MAIN_ROW_STRIDE:Float = 52.0;

    /** Pause menu option row vertical stride spacing. */
    public static inline var PAUSE_ROW_STRIDE:Float = 54.0;

    /** Options menu tab button spacing interval. */
    public static inline var OPTIONS_TAB_SPACING:Float = 170.0;

    /** Standard iconography square size for menu rows in pixels. */
    public static inline var ICON_SIZE_MENU:Int = 24;

    /** Tab header icon size in pixels. */
    public static inline var ICON_SIZE_TAB:Int = 22;

    /** Audio channel slider icon size in pixels. */
    public static inline var ICON_SIZE_AUDIO:Int = 28;

    /** Credits developer badge icon size in pixels. */
    public static inline var ICON_SIZE_CREDITS:Int = 28;

    /** Options and overlay back button interactive width. */
    public static inline var BACK_BUTTON_WIDTH:Float = 260.0;

    /** Options and overlay back button interactive height. */
    public static inline var BACK_BUTTON_HEIGHT:Float = 40.0;

    // =========================================================================
    // TOUCH VIRTUAL HUD METRICS
    // =========================================================================

    /** Touch button diameter in pixels for driving action buttons. */
    public static inline var TOUCH_BTN_SIZE:Float = 72.0;

    /** Touch steering button width in pixels. */
    public static inline var TOUCH_STEER_BTN_WIDTH:Float = 84.0;

    /** Touch steering button height in pixels. */
    public static inline var TOUCH_STEER_BTN_HEIGHT:Float = 84.0;

    /** Touch pause button size in pixels. */
    public static inline var TOUCH_PAUSE_BTN_SIZE:Float = 52.0;

    /** Touch virtual analog joystick base outer radius in pixels. */
    public static inline var TOUCH_STICK_BASE_RADIUS:Float = 65.0;

    /** Touch virtual analog joystick movable thumb knob radius in pixels. */
    public static inline var TOUCH_STICK_KNOB_RADIUS:Float = 30.0;

    /** Touch virtual analog joystick maximum travel deflection distance in pixels. */
    public static inline var TOUCH_STICK_MAX_TRAVEL:Float = 50.0;

    /** Inactive touch control capsule fill alpha. */
    public static inline var ALPHA_TOUCH_IDLE:Float = 0.28;

    /** Active/pressed touch control capsule fill alpha. */
    public static inline var ALPHA_TOUCH_PRESSED:Float = 0.72;

    /** Touch control outline border alpha. */
    public static inline var ALPHA_TOUCH_BORDER:Float = 0.65;
}

