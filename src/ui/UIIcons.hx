package ui;

import h2d.Tile;
import h2d.Graphics;

/**
 * Enumeration of vector-drawn UI iconography types rendered procedurally into cached textures.
 */
enum IconType {
    /** Right-pointing triangle arrow representing race play. */
    Play;

    /** Right-pointing triangle representing race resume. */
    Resume;

    /** Circular sweep arrow representing circuit restart. */
    Restart;

    /** Gear cog symbol representing settings menu. */
    Settings;

    /** Computer monitor silhouette representing display/graphics configuration. */
    Graphics;

    /** Speaker horn emitting acoustic sound waves representing volume. */
    Volume;

    /** Speaker horn with cancel strikethrough representing mute. */
    Mute;

    /** Musical eighth note representing background soundtrack channel. */
    Music;

    /** Sound wave equalization bars representing sound effects channel. */
    Sfx;

    /** Keyboard layout silhouette representing digital keyboard controls. */
    Keyboard;

    /** Gamepad controller silhouette representing analog stick and button controls. */
    Gamepad;

    /** Information shield badge representing credits and disclosures. */
    Credits;

    /** Mobile touch screen silhouette representing touch controls. */
    Touch;

    /** Exit doorway with directional arrow representing exit to title. */
    Exit;
}

/**
 * Procedural UI iconography renderer and texture tile cache.
 * Avoids variable TTF font baseline misalignment bugs by rendering vector graphics directly
 * to high-resolution GPU textures via `h2d.Graphics.drawTo()`.
 */
class UIIcons {
    /** In-memory tile cache keyed by `Type_Size_HexColor`. */
    static var cache:Map<String, Tile> = new Map();

    /**
     * Retrieves or procedurally draws a cached icon tile matching the given parameters.
     *
     * @param type IconType enum variant identifying glyph to draw.
     * @param size Square dimension in pixels of the output icon tile (default: 24).
     * @param color Hexadecimal fill and line color (default: 0x00E5FF cyan).
     * @return Cached GPU texture tile ready for assignment to `h2d.Bitmap`.
     */
    public static function get(type:IconType, size:Int = 24, color:Int = 0x00E5FF):Tile {
        var key = Std.string(type) + "_" + size + "_" + StringTools.hex(color);
        if (cache.exists(key)) return cache.get(key);

        var g = new Graphics();
        g.lineStyle(2.0, color, 1.0);
        g.beginFill(color, 1.0);

        var s = size * 1.0;
        var pad = s * 0.15;
        var w = s - (pad * 2.0);

        switch (type) {
            case Play | Resume:
                // Right-facing triangle polygon
                g.moveTo(pad + w * 0.2, pad);
                g.lineTo(pad + w * 0.9, pad + w * 0.5);
                g.lineTo(pad + w * 0.2, pad + w);
                g.lineTo(pad + w * 0.2, pad);

            case Restart:
                // Circular sweep arrow
                g.endFill();
                g.drawCircle(s * 0.5, s * 0.5, w * 0.38);
                g.beginFill(color, 1.0);
                g.moveTo(s * 0.5, pad);
                g.lineTo(s * 0.5 + w * 0.25, pad + w * 0.25);
                g.lineTo(s * 0.5 - w * 0.25, pad + w * 0.25);
                g.lineTo(s * 0.5, pad);

            case Settings:
                // Mechanical gear cog concentric circles
                g.endFill();
                g.drawCircle(s * 0.5, s * 0.5, w * 0.25);
                g.lineStyle(3.0, color, 1.0);
                g.drawCircle(s * 0.5, s * 0.5, w * 0.42);

            case Graphics:
                // Computer display monitor with stand
                g.endFill();
                g.drawRoundedRect(pad, pad, w, w * 0.65, 3);
                g.lineStyle(2.0, color, 1.0);
                g.moveTo(s * 0.5, pad + w * 0.65); g.lineTo(s * 0.5, pad + w * 0.9);
                g.moveTo(pad + w * 0.25, pad + w * 0.9); g.lineTo(pad + w * 0.75, pad + w * 0.9);

            case Volume:
                // Speaker horn body and acoustic sound arc
                g.moveTo(pad, pad + w * 0.3);
                g.lineTo(pad + w * 0.35, pad + w * 0.3);
                g.lineTo(pad + w * 0.65, pad);
                g.lineTo(pad + w * 0.65, pad + w);
                g.lineTo(pad + w * 0.35, pad + w * 0.7);
                g.lineTo(pad, pad + w * 0.7);
                g.lineTo(pad, pad + w * 0.3);
                g.endFill();
                g.lineStyle(2.0, color, 1.0);
                g.moveTo(pad + w * 0.8, pad + w * 0.3);
                g.lineTo(pad + w * 0.8, pad + w * 0.7);

            case Mute:
                // Speaker horn body with red diagonal strikethrough cross
                g.moveTo(pad, pad + w * 0.3);
                g.lineTo(pad + w * 0.35, pad + w * 0.3);
                g.lineTo(pad + w * 0.65, pad);
                g.lineTo(pad + w * 0.65, pad + w);
                g.lineTo(pad + w * 0.35, pad + w * 0.7);
                g.lineTo(pad, pad + w * 0.7);
                g.lineTo(pad, pad + w * 0.3);
                g.endFill();
                g.lineStyle(2.0, 0xE06C75, 1.0);
                g.moveTo(pad + w * 0.75, pad + w * 0.3); g.lineTo(pad + w * 0.95, pad + w * 0.7);
                g.moveTo(pad + w * 0.95, pad + w * 0.3); g.lineTo(pad + w * 0.75, pad + w * 0.7);

            case Music:
                // Musical eighth note stave and dual note heads
                g.endFill();
                g.lineStyle(2.5, color, 1.0);
                g.moveTo(pad + w * 0.45, pad + w * 0.7);
                g.lineTo(pad + w * 0.45, pad + w * 0.15);
                g.lineTo(pad + w * 0.85, pad + w * 0.35);
                g.lineTo(pad + w * 0.85, pad + w * 0.8);
                g.beginFill(color, 1.0);
                g.drawCircle(pad + w * 0.3, pad + w * 0.75, w * 0.18);
                g.drawCircle(pad + w * 0.7, pad + w * 0.85, w * 0.18);

            case Sfx:
                // Graphic audio spectrum equalizer bars
                g.endFill();
                g.lineStyle(2.5, color, 1.0);
                g.moveTo(pad + w * 0.15, pad + w * 0.2); g.lineTo(pad + w * 0.15, pad + w * 0.8);
                g.moveTo(pad + w * 0.5, pad);            g.lineTo(pad + w * 0.5, pad + w);
                g.moveTo(pad + w * 0.85, pad + w * 0.35); g.lineTo(pad + w * 0.85, pad + w * 0.65);

            case Keyboard:
                // Keyboard frame outline with individual keycap blocks
                g.endFill();
                g.drawRoundedRect(pad, pad + w * 0.15, w, w * 0.7, 4);
                g.beginFill(color, 1.0);
                g.drawRect(pad + w * 0.2, pad + w * 0.35, w * 0.15, w * 0.12);
                g.drawRect(pad + w * 0.45, pad + w * 0.35, w * 0.15, w * 0.12);
                g.drawRect(pad + w * 0.7, pad + w * 0.35, w * 0.15, w * 0.12);
                g.drawRect(pad + w * 0.3, pad + w * 0.6, w * 0.4, w * 0.12);

            case Gamepad:
                // Gamepad contour with D-Pad and dual face buttons
                g.endFill();
                g.drawRoundedRect(pad, pad + w * 0.2, w, w * 0.6, 6);
                g.beginFill(color, 1.0);
                g.drawRect(pad + w * 0.2, pad + w * 0.45, w * 0.15, w * 0.08);
                g.drawRect(pad + w * 0.235, pad + w * 0.415, w * 0.08, w * 0.15);
                g.drawCircle(pad + w * 0.75, pad + w * 0.45, w * 0.06);
                g.drawCircle(pad + w * 0.65, pad + w * 0.55, w * 0.06);

            case Credits:
                // Circular information badge with exclamation/info dot and bar
                g.endFill();
                g.drawCircle(s * 0.5, s * 0.5, w * 0.45);
                g.beginFill(color, 1.0);
                g.drawCircle(s * 0.5, pad + w * 0.25, w * 0.07);
                g.drawRect(s * 0.5 - w * 0.05, pad + w * 0.45, w * 0.1, w * 0.32);

            case Touch:
                // Mobile smartphone screen outline with touch target indicator
                g.endFill();
                g.drawRoundedRect(pad + w * 0.15, pad, w * 0.7, w, 4);
                g.beginFill(color, 1.0);
                g.drawCircle(s * 0.5, pad + w * 0.86, w * 0.05);
                g.drawCircle(s * 0.5, pad + w * 0.45, w * 0.10);

            case Exit:
                // Open doorway frame with outbound directional arrow
                g.endFill();
                g.drawRect(pad, pad, w * 0.55, w);
                g.lineStyle(2.0, color, 1.0);
                g.moveTo(pad + w * 0.35, s * 0.5); g.lineTo(pad + w * 0.95, s * 0.5);
                g.moveTo(pad + w * 0.75, pad + w * 0.28); g.lineTo(pad + w * 0.95, s * 0.5);
                g.lineTo(pad + w * 0.75, pad + w * 0.72);
        }
        g.endFill();

        // Render vector graphics directly onto GPU render target texture
        var tex = new h3d.mat.Texture(size, size, [Target]);
        g.drawTo(tex);
        var tile = Tile.fromTexture(tex);
        cache.set(key, tile);
        return tile;
    }
}