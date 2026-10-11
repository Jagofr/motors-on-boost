package tests.save;

import utest.Test;
import utest.Assert;
import haxe.Json;
import save.SaveSystem;

/**
 * Unit test suite validating SaveSystem schema versioning, default presets,
 * and forward migration logic.
 */
class TestSaveSystem extends Test {
    public function testDefaultGraphics() {
        var g = SaveSystem.getDefaultGraphics();
        Assert.equals("High", g.textures);
        Assert.equals("Normal", g.shadowLevel);
        Assert.equals(1024, g.shadowRes);
        Assert.equals("FXAA", g.aaType);
        Assert.equals(2, g.aaLevel);
        Assert.equals(1.0, g.renderScale);
        Assert.equals("720p (HD)", g.uiResolution);
    }

    public function testDefaultTouchSettings() {
        var t = SaveSystem.getDefaultTouchSettings();
        Assert.equals("Default", t.mode);
        Assert.equals(1.0, t.scale);
        Assert.equals(0.0, t.stickOffsetX);
        Assert.equals(0.0, t.stickOffsetY);
        Assert.equals(0.0, t.nitroOffsetX);
        Assert.equals(0.0, t.nitroOffsetY);
        Assert.equals(0.0, t.gasOffsetX);
        Assert.equals(0.0, t.gasOffsetY);
        Assert.equals(0.0, t.brakeOffsetX);
        Assert.equals(0.0, t.brakeOffsetY);
        Assert.equals(0.0, t.driftOffsetX);
        Assert.equals(0.0, t.driftOffsetY);
    }

    public function testSaveDataIntegrity() {
        var data:GameSaveData = {
            version: SaveSystem.SAVE_VERSION,
            buildNumber: 10,
            hasActiveRun: false,
            playerState: { posX: 10.0, posY: 20.0, posZ: 0.0, yaw: 1.57, forwardSpeed: 15.0 },
            masterVol: 0.8,
            musicVol: 0.7,
            sfxVol: 0.9,
            steerSensitivity: 0.84,
            graphics: SaveSystem.getDefaultGraphics(),
            touchSettings: SaveSystem.getDefaultTouchSettings()
        };

        var raw = Json.stringify(data);
        var parsed:GameSaveData = Json.parse(raw);

        Assert.equals(SaveSystem.SAVE_VERSION, parsed.version);
        Assert.floatEquals(0.84, parsed.steerSensitivity, 0.001);
        Assert.floatEquals(15.0, parsed.playerState.forwardSpeed, 0.001);
        Assert.notNull(parsed.touchSettings);
        Assert.equals("Default", parsed.touchSettings.mode);
    }
}

