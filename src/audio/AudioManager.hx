package audio;

import config.GameConfig;
import core.WebBridge;

/**
 * Procedural audio manager coordinating WebAudio synthesis across the `WebBridge`
 * shared-memory mailbox (avoiding direct DOM/WebAudio worker assumptions).
 */
class AudioManager {
    public static var inst:AudioManager;

    public var config:AudioConfig;
    public var masterVolume:Float = 0.8;
    public var musicVolume:Float = 0.7;
    public var sfxVolume:Float = 0.9;
    public var suspended:Bool = false;

    public function new(?config:AudioConfig) {
        this.config = config != null ? config : GameConfig.getDefault().audio;
        masterVolume = this.config.defaultMaster;
        musicVolume = this.config.defaultMusic;
        sfxVolume = this.config.defaultSfx;
        inst = this;
        WebBridge.inst.pushEvent({
            type: "audio_init",
            master: masterVolume,
            music: musicVolume,
            sfx: sfxVolume
        });
    }

    public function playMenuBeep(freq:Float = 440.0, duration:Float = 0.06):Void {
        var gain = Math.max(0.0, Math.min(1.0, masterVolume * sfxVolume));
        if (gain <= 0.01 || suspended) return;
        WebBridge.inst.pushEvent({
            type: "audio_beep",
            freq: freq,
            duration: duration,
            gain: gain
        });
    }

    public function suspend():Void {
        suspended = true;
        WebBridge.inst.pushEvent({ type: "audio_suspend" });
    }

    public function resume():Void {
        suspended = false;
        WebBridge.inst.pushEvent({ type: "audio_resume" });
    }
}
