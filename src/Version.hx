package;

/**
 * Global build metadata and application version definitions.
 * Centralized single source of truth for semantic versioning, build number, and release tagging.
 */
class Version {
    /** Semantic version string: Major.Minor.Patch */
    public static inline var NUMBER:String = "0.1.4";

    /** Monotonically increasing build compilation counter. */
    public static inline var BUILD:Int = 148;

    /** Human-readable release designation. */
    public static inline var CHANNEL:String = "Alpha";

    /** Full formatted display string with build number. */
    public static inline var DISPLAY:String = "v" + NUMBER + " (Build " + BUILD + ")";

    /** Short version string. */
    public static inline var SHORT:String = "v" + NUMBER;

    /** Build release date. */
    public static inline var BUILD_DATE:String = "2026-10-09";
}
