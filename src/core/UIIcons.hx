package core;

import h2d.Tile;
import h2d.Graphics;

enum IconType {
    Play;
    Resume;
    Restart;
    Settings;
    Graphics;
    Volume;
    Mute;
    Music;
    Sfx;
    Keyboard;
    Gamepad;
    Credits;
    Exit;
}

class UIIcons {
    static var cache:Map<String, Tile> = new Map();

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
                // Right-facing triangle
                g.moveTo(pad + w * 0.2, pad);
                g.lineTo(pad + w * 0.9, pad + w * 0.5);
                g.lineTo(pad + w * 0.2, pad + w);
                g.lineTo(pad + w * 0.2, pad);

            case Restart:
                // Circular arrow
                g.endFill();
                g.drawCircle(s * 0.5, s * 0.5, w * 0.38);
                g.beginFill(color, 1.0);
                g.moveTo(s * 0.5, pad);
                g.lineTo(s * 0.5 + w * 0.25, pad + w * 0.25);
                g.lineTo(s * 0.5 - w * 0.25, pad + w * 0.25);
                g.lineTo(s * 0.5, pad);

            case Settings:
                // Gear / cog
                g.endFill();
                g.drawCircle(s * 0.5, s * 0.5, w * 0.25);
                g.lineStyle(3.0, color, 1.0);
                g.drawCircle(s * 0.5, s * 0.5, w * 0.42);

            case Graphics:
                // Display Monitor
                g.endFill();
                g.drawRoundedRect(pad, pad, w, w * 0.65, 3);
                g.lineStyle(2.0, color, 1.0);
                g.moveTo(s * 0.5, pad + w * 0.65); g.lineTo(s * 0.5, pad + w * 0.9);
                g.moveTo(pad + w * 0.25, pad + w * 0.9); g.lineTo(pad + w * 0.75, pad + w * 0.9);

            case Volume:
                // Speaker horn + sound waves
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
                // Eighth note
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
                // Sound equalizer bars
                g.endFill();
                g.lineStyle(2.5, color, 1.0);
                g.moveTo(pad + w * 0.15, pad + w * 0.2); g.lineTo(pad + w * 0.15, pad + w * 0.8);
                g.moveTo(pad + w * 0.5, pad);            g.lineTo(pad + w * 0.5, pad + w);
                g.moveTo(pad + w * 0.85, pad + w * 0.35); g.lineTo(pad + w * 0.85, pad + w * 0.65);

            case Keyboard:
                // Keyboard grid
                g.endFill();
                g.drawRoundedRect(pad, pad + w * 0.15, w, w * 0.7, 4);
                g.beginFill(color, 1.0);
                g.drawRect(pad + w * 0.2, pad + w * 0.35, w * 0.15, w * 0.12);
                g.drawRect(pad + w * 0.45, pad + w * 0.35, w * 0.15, w * 0.12);
                g.drawRect(pad + w * 0.7, pad + w * 0.35, w * 0.15, w * 0.12);
                g.drawRect(pad + w * 0.3, pad + w * 0.6, w * 0.4, w * 0.12);

            case Gamepad:
                // Gamepad silhouette
                g.endFill();
                g.drawRoundedRect(pad, pad + w * 0.2, w, w * 0.6, 6);
                g.beginFill(color, 1.0);
                // Dpad + buttons
                g.drawRect(pad + w * 0.2, pad + w * 0.45, w * 0.15, w * 0.08);
                g.drawRect(pad + w * 0.235, pad + w * 0.415, w * 0.08, w * 0.15);
                g.drawCircle(pad + w * 0.75, pad + w * 0.45, w * 0.06);
                g.drawCircle(pad + w * 0.65, pad + w * 0.55, w * 0.06);

            case Credits:
                // Info badge
                g.endFill();
                g.drawCircle(s * 0.5, s * 0.5, w * 0.45);
                g.beginFill(color, 1.0);
                g.drawCircle(s * 0.5, pad + w * 0.25, w * 0.07);
                g.drawRect(s * 0.5 - w * 0.05, pad + w * 0.45, w * 0.1, w * 0.32);

            case Exit:
                // Exit door with arrow
                g.endFill();
                g.drawRect(pad, pad, w * 0.55, w);
                g.lineStyle(2.0, color, 1.0);
                g.moveTo(pad + w * 0.35, s * 0.5); g.lineTo(pad + w * 0.95, s * 0.5);
                g.moveTo(pad + w * 0.75, pad + w * 0.28); g.lineTo(pad + w * 0.95, s * 0.5);
                g.lineTo(pad + w * 0.75, pad + w * 0.72);
        }
        g.endFill();

        var bounds = g.getBounds();
        var tile = Tile.fromColor(0, size, size, 0.0);
        // Draw to texture tile
        var tex = new h3d.mat.Texture(size, size, [Target]);
        g.drawTo(tex);
        tile = Tile.fromTexture(tex);
        cache.set(key, tile);
        return tile;
    }
}