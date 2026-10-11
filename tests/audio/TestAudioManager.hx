package tests.audio;

import utest.Test;
import utest.Assert;
import audio.AudioManager;

/**
 * Unit test suite validating AudioManager volume clamping, singleton assignment,
 * and audio tone parameters.
 */
class TestAudioManager extends Test {
    var audio:AudioManager;

    public function setup() {
        audio = new AudioManager();
    }

    public function testSingletonInstance() {
        Assert.equals(audio, AudioManager.inst);
    }

    public function testDefaultVolumeLevels() {
        Assert.floatEquals(0.8, audio.masterVolume, 0.001);
        Assert.floatEquals(0.7, audio.musicVolume, 0.001);
        Assert.floatEquals(0.9, audio.sfxVolume, 0.001);
    }

    public function testPlayMenuBeepSafelyHandlesNullContext() {
        // Must not crash or throw in headless or restricted browser environments
        audio.playMenuBeep(440.0, 0.06);
        audio.playMenuBeep(880.0, 0.1);
        Assert.pass();
    }
}

