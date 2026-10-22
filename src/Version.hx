package;

/**
 * Global build metadata and application version definitions.
 * Centralized single source of truth for semantic versioning, build number, and release tagging.
 */
class Version {
    /** Semantic version string: Major.Minor.Patch (Milestone v1.0.0) */
    public static inline var NUMBER:String = "1.0.0";

    /** Monotonically increasing build compilation counter tallied from 0 for v1.0.0 milestone. */
    public static inline var BUILD:Int = 6;

    /** Build compilation counter formatted with zero-padding (0000 format). */
    public static inline var BUILD_STRING:String = "0006";

    /** Human-readable release designation. */
    public static inline var CHANNEL:String = "Alpha";

    /** Full formatted display string with build number in 0000 format. */
    public static inline var DISPLAY:String = "v" + NUMBER + " (Build " + BUILD_STRING + ")";

    /** Short version string. */
    public static inline var SHORT:String = "v" + NUMBER;

    /** Build release date. */
    public static inline var BUILD_DATE:String = "2026-10-22";
}
