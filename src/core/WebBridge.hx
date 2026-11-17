package core;

import haxe.Json;
import haxe.io.Bytes;

/**
 * Zero-copy shared-memory mailbox bridging Haxe (`game.wasm` running in Ash worker)
 * with the browser main thread DOM UI overlay (`web/ui-overlay.js`) and Web APIs
 * (AudioContext, localStorage, WebSocket/HTTP relay, orientation gate, Playwright facade).
 *
 * Memory layout (131,072 bytes = 128 KB, little-endian, 4-byte aligned):
 *   0..15    : Magic header [0x4D4F4232, 0x57475055, 0x53484D31, 0x32303236] ("MOB2WGPUSHM12026")
 *   16..63   : Header & flag Int32 slots
 *   64..123  : Continuous Float32 telemetry & touch inputs
 *   124..255 : Initial URL query / room invite string (len @124, UTF-8 @128..255)
 *   256..32767   : Haxe -> JS UI/world state JSON snapshot (len @256, UTF-8 @260..32767)
 *   32768..65535 : Haxe -> JS SPSC event ring (writePtr @32768, readPtr @32772, data @32776..65535)
 *   65536..131071: JS -> Haxe SPSC command ring (writePtr @65536, readPtr @65540, data @65544..131071)
 */
class WebBridge {
    public static inline var MAILBOX_BYTES:Int = 131072;

    public static inline var MAGIC_0:Int = 0x4D4F4232; // "MOB2"
    public static inline var MAGIC_1:Int = 0x57475055; // "WGPU"
    public static inline var MAGIC_2:Int = 0x53484D31; // "SHM1"
    public static inline var MAGIC_3:Int = 0x32303236; // "2026"

    // Int32 header offsets
    public static inline var OFF_STATE_SEQ:Int       = 16;
    public static inline var OFF_CMD_SEQ:Int         = 20;
    public static inline var OFF_PORTRAIT_BLOCKED:Int = 24;
    public static inline var OFF_VIEWPORT_W:Int      = 28;
    public static inline var OFF_VIEWPORT_H:Int      = 32;
    public static inline var OFF_TOUCH_ACTIVE:Int    = 36;
    public static inline var OFF_TOUCH_HANDBRAKE:Int = 40;
    public static inline var OFF_TOUCH_BOOST:Int     = 44;
    public static inline var OFF_TOUCH_PAUSE:Int     = 48;
    public static inline var OFF_STORAGE_READY:Int   = 52;
    public static inline var OFF_GPU_READY:Int       = 56;
    public static inline var OFF_IN_MENU:Int         = 60;

    // Float32 telemetry & touch offsets
    public static inline var OFF_SPEED_KMH:Int       = 64;
    public static inline var OFF_RPM_NORM:Int        = 68;
    public static inline var OFF_GEAR:Int            = 72;
    public static inline var OFF_BOOST_PCT:Int       = 76;
    public static inline var OFF_LAP_PROGRESS:Int    = 80;
    public static inline var OFF_LAP_COUNT:Int       = 84;
    public static inline var OFF_RACE_TIME:Int       = 88;
    public static inline var OFF_CAR_X:Int           = 92;
    public static inline var OFF_CAR_Y:Int           = 96;
    public static inline var OFF_CAR_YAW:Int         = 100;
    public static inline var OFF_TOUCH_STEER:Int     = 104;
    public static inline var OFF_TOUCH_THROTTLE:Int  = 108;
    public static inline var OFF_TOUCH_BRAKE:Int     = 112;
    public static inline var OFF_STEER_OUT:Int       = 116;
    public static inline var OFF_FPS:Int             = 120;

    // URL query slot
    public static inline var OFF_QUERY_LEN:Int       = 124;
    public static inline var OFF_QUERY_DATA:Int      = 128;
    public static inline var MAX_QUERY_BYTES:Int     = 128;

    // Outbound State JSON snapshot (Haxe -> JS)
    public static inline var OFF_STATE_LEN:Int       = 256;
    public static inline var OFF_STATE_DATA:Int      = 260;
    public static inline var MAX_STATE_BYTES:Int     = 32508; // up to 32768

    // Outbound Event Ring (Haxe -> JS)
    public static inline var OFF_OUT_WRITE:Int       = 32768;
    public static inline var OFF_OUT_READ:Int        = 32772;
    public static inline var OFF_OUT_BUF:Int         = 32776;
    public static inline var OUT_RING_CAP:Int        = 32760; // 65536 - 32776

    // Inbound Command Ring (JS -> Haxe)
    public static inline var OFF_IN_WRITE:Int        = 65536;
    public static inline var OFF_IN_READ:Int         = 65540;
    public static inline var OFF_IN_BUF:Int          = 65544;
    public static inline var IN_RING_CAP:Int         = 65528; // 131072 - 65544

    public static final inst:WebBridge = new WebBridge();

    /** Pinned shared-memory buffer discovered once by JS via `WebAssembly.Memory.buffer`. */
    public var mailbox(default, null):Bytes;

    private var stateSeq:Int = 0;
    private var lastStateJson:String = "";
    public var localStorageCache:Map<String, String> = new Map();
    public var inboundQueue:Array<String> = [];

    private function new() {
        mailbox = Bytes.alloc(MAILBOX_BYTES);
        resetMailbox();
    }

    public function resetMailbox():Void {
        mailbox.fill(0, MAILBOX_BYTES, 0);
        // Write magic header bytes; write MAGIC_3 last so JS sees initialized state atomically
        mailbox.setInt32(0, MAGIC_0);
        mailbox.setInt32(4, MAGIC_1);
        mailbox.setInt32(8, MAGIC_2);
        mailbox.setInt32(OFF_VIEWPORT_W, 1280);
        mailbox.setInt32(OFF_VIEWPORT_H, 720);
        mailbox.setInt32(12, MAGIC_3);
        stateSeq = 0;
        lastStateJson = "";
    }

    public inline function setGpuReady(ready:Bool):Void {
        mailbox.setInt32(OFF_GPU_READY, ready ? 1 : 0);
    }

    public inline function setViewport(w:Int, h:Int):Void {
        mailbox.setInt32(OFF_VIEWPORT_W, w);
        mailbox.setInt32(OFF_VIEWPORT_H, h);
    }

    public inline function isPortraitBlocked():Bool {
        return mailbox.getInt32(OFF_PORTRAIT_BLOCKED) != 0;
    }

    public inline function setPortraitBlocked(blocked:Bool):Void {
        mailbox.setInt32(OFF_PORTRAIT_BLOCKED, blocked ? 1 : 0);
    }

    public inline function readTouchState():{
        active:Bool,
        steer:Float,
        throttle:Float,
        brake:Float,
        handbrake:Bool,
        boost:Bool,
        pause:Bool
    } {
        return {
            active: mailbox.getInt32(OFF_TOUCH_ACTIVE) != 0,
            steer: mailbox.getFloat(OFF_TOUCH_STEER),
            throttle: mailbox.getFloat(OFF_TOUCH_THROTTLE),
            brake: mailbox.getFloat(OFF_TOUCH_BRAKE),
            handbrake: mailbox.getInt32(OFF_TOUCH_HANDBRAKE) != 0,
            boost: mailbox.getInt32(OFF_TOUCH_BOOST) != 0,
            pause: mailbox.getInt32(OFF_TOUCH_PAUSE) != 0
        };
    }

    public inline function writeTelemetry(
        speedKmh:Float,
        rpmNorm:Float,
        gear:Int,
        boostPct:Float,
        lapProgress:Float,
        lapCount:Int,
        raceTime:Float,
        carX:Float,
        carY:Float,
        carYaw:Float,
        steerOut:Float,
        fps:Float,
        inMenu:Bool
    ):Void {
        mailbox.setFloat(OFF_SPEED_KMH, speedKmh);
        mailbox.setFloat(OFF_RPM_NORM, rpmNorm);
        mailbox.setFloat(OFF_GEAR, gear);
        mailbox.setFloat(OFF_BOOST_PCT, boostPct);
        mailbox.setFloat(OFF_LAP_PROGRESS, lapProgress);
        mailbox.setFloat(OFF_LAP_COUNT, lapCount);
        mailbox.setFloat(OFF_RACE_TIME, raceTime);
        mailbox.setFloat(OFF_CAR_X, carX);
        mailbox.setFloat(OFF_CAR_Y, carY);
        mailbox.setFloat(OFF_CAR_YAW, carYaw);
        mailbox.setFloat(OFF_STEER_OUT, steerOut);
        mailbox.setFloat(OFF_FPS, fps);
        mailbox.setInt32(OFF_IN_MENU, inMenu ? 1 : 0);
    }

    public function readUrlSearch():String {
        var len = mailbox.getInt32(OFF_QUERY_LEN);
        if (len <= 0 || len > MAX_QUERY_BYTES) return "";
        return mailbox.getString(OFF_QUERY_DATA, len, UTF8);
    }

    /**
     * Publishes the current UI/world/touch state snapshot as UTF-8 JSON when changed.
     */
    public function publishState(stateObj:Dynamic):Void {
        var json = Json.stringify(stateObj);
        if (json == lastStateJson) return;
        lastStateJson = json;

        var utf8 = Bytes.ofString(json, UTF8);
        var len = utf8.length;
        if (len > MAX_STATE_BYTES) {
            len = MAX_STATE_BYTES;
        }
        mailbox.blit(OFF_STATE_DATA, utf8, 0, len);
        mailbox.setInt32(OFF_STATE_LEN, len);
        stateSeq++;
        mailbox.setInt32(OFF_STATE_SEQ, stateSeq);
    }

    /**
     * Pushes a structured event packet onto the Haxe -> JS ring buffer (audio, save, net, URL).
     */
    public function pushEvent(eventObj:Dynamic):Bool {
        var msg = Json.stringify(eventObj);
        return writeRing(OFF_OUT_WRITE, OFF_OUT_READ, OFF_OUT_BUF, OUT_RING_CAP, msg);
    }

    /**
     * Drains all pending commands pushed from JS into the `inboundQueue` array.
     */
    public function pollCommands():Array<String> {
        var out:Array<String> = [];
        while (true) {
            var msg = readRing(OFF_IN_WRITE, OFF_IN_READ, OFF_IN_BUF, IN_RING_CAP);
            if (msg == null) break;
            out.push(msg);
        }
        return out;
    }

    /** Drains outbound events (for headless unit testing). */
    public function pollOutboundEventsForTest():Array<String> {
        var out:Array<String> = [];
        while (true) {
            var msg = readRing(OFF_OUT_WRITE, OFF_OUT_READ, OFF_OUT_BUF, OUT_RING_CAP);
            if (msg == null) break;
            out.push(msg);
        }
        return out;
    }

    /** Pushes a simulated JS -> Haxe command (for headless unit testing). */
    public function pushInboundForTest(jsonOrTag:String):Bool {
        return writeRing(OFF_IN_WRITE, OFF_IN_READ, OFF_IN_BUF, IN_RING_CAP, jsonOrTag);
    }

    private function writeRing(offWrite:Int, offRead:Int, offBuf:Int, cap:Int, text:String):Bool {
        var payload = Bytes.ofString(text, UTF8);
        var len = payload.length;
        var padded = (4 + len + 3) & ~3;
        if (padded >= cap) return false;

        var w = mailbox.getInt32(offWrite);
        var r = mailbox.getInt32(offRead);
        var used = w >= r ? (w - r) : (cap - r + w);
        var free = cap - used - 4;
        if (padded > free) return false;

        // If record would wrap at end of ring buffer, write skip sentinel (-1) and rewind to 0
        if (w + padded > cap) {
            if (r > w || r <= padded) return false;
            mailbox.setInt32(offBuf + w, -1);
            w = 0;
        }

        mailbox.setInt32(offBuf + w, len);
        mailbox.blit(offBuf + w + 4, payload, 0, len);
        var nextW = w + padded;
        if (nextW >= cap) nextW = 0;
        mailbox.setInt32(offWrite, nextW);
        return true;
    }

    private function readRing(offWrite:Int, offRead:Int, offBuf:Int, cap:Int):Null<String> {
        var w = mailbox.getInt32(offWrite);
        var r = mailbox.getInt32(offRead);
        if (w == r) return null;

        var len = mailbox.getInt32(offBuf + r);
        if (len < 0) {
            // Skip sentinel -> wrap read pointer to 0
            r = 0;
            mailbox.setInt32(offRead, 0);
            if (w == 0) return null;
            len = mailbox.getInt32(offBuf + 0);
        }

        if (len < 0 || len > cap - 4) {
            mailbox.setInt32(offRead, w);
            return null;
        }

        var str = mailbox.getString(offBuf + r + 4, len, UTF8);
        var padded = (4 + len + 3) & ~3;
        var nextR = r + padded;
        if (nextR >= cap) nextR = 0;
        mailbox.setInt32(offRead, nextR);
        return str;
    }
}
