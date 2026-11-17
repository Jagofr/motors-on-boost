package input;

import window.KeyCode;

/**
 * Platform-neutral virtual keyboard state & scan-code table replacing `hxd.Key`.
 * Numeric codes preserve standard JS / Heaps key codes so persisted `SaveSystem` bindings remain compatible.
 */
class InputKey {
    public static inline var MOUSE_LEFT:Int   = 1;
    public static inline var MOUSE_RIGHT:Int  = 2;
    public static inline var MOUSE_MIDDLE:Int = 3;

    public static inline var BACKSPACE:Int = 8;
    public static inline var TAB:Int       = 9;
    public static inline var ENTER:Int     = 13;
    public static inline var SHIFT:Int     = 16;
    public static inline var CTRL:Int      = 17;
    public static inline var ALT:Int       = 18;
    public static inline var ESCAPE:Int    = 27;
    public static inline var SPACE:Int     = 32;
    public static inline var PGUP:Int      = 33;
    public static inline var PGDOWN:Int    = 34;
    public static inline var END:Int       = 35;
    public static inline var HOME:Int      = 36;
    public static inline var LEFT:Int      = 37;
    public static inline var UP:Int        = 38;
    public static inline var RIGHT:Int     = 39;
    public static inline var DOWN:Int      = 40;
    public static inline var INSERT:Int    = 45;
    public static inline var DELETE:Int    = 46;

    public static inline var NUMBER_0:Int = 48;
    public static inline var NUMBER_1:Int = 49;
    public static inline var NUMBER_2:Int = 50;
    public static inline var NUMBER_3:Int = 51;
    public static inline var NUMBER_4:Int = 52;
    public static inline var NUMBER_5:Int = 53;
    public static inline var NUMBER_6:Int = 54;
    public static inline var NUMBER_7:Int = 55;
    public static inline var NUMBER_8:Int = 56;
    public static inline var NUMBER_9:Int = 57;

    public static inline var A:Int = 65;
    public static inline var B:Int = 66;
    public static inline var C:Int = 67;
    public static inline var D:Int = 68;
    public static inline var E:Int = 69;
    public static inline var F:Int = 70;
    public static inline var G:Int = 71;
    public static inline var H:Int = 72;
    public static inline var I:Int = 73;
    public static inline var J:Int = 74;
    public static inline var K:Int = 75;
    public static inline var L:Int = 76;
    public static inline var M:Int = 77;
    public static inline var N:Int = 78;
    public static inline var O:Int = 79;
    public static inline var P:Int = 80;
    public static inline var Q:Int = 81;
    public static inline var R:Int = 82;
    public static inline var S:Int = 83;
    public static inline var T:Int = 84;
    public static inline var U:Int = 85;
    public static inline var V:Int = 86;
    public static inline var W:Int = 87;
    public static inline var X:Int = 88;
    public static inline var Y:Int = 89;
    public static inline var Z:Int = 90;

    public static inline var NUMPAD_0:Int = 96;
    public static inline var NUMPAD_1:Int = 97;
    public static inline var NUMPAD_2:Int = 98;
    public static inline var NUMPAD_3:Int = 99;
    public static inline var NUMPAD_4:Int = 100;
    public static inline var NUMPAD_5:Int = 101;
    public static inline var NUMPAD_6:Int = 102;
    public static inline var NUMPAD_7:Int = 103;
    public static inline var NUMPAD_8:Int = 104;
    public static inline var NUMPAD_9:Int = 105;
    public static inline var NUMPAD_MULT:Int = 106;
    public static inline var NUMPAD_ADD:Int  = 107;
    public static inline var NUMPAD_SUB:Int  = 109;
    public static inline var NUMPAD_DOT:Int  = 110;
    public static inline var NUMPAD_DIV:Int  = 111;

    public static inline var F1:Int  = 112;
    public static inline var F2:Int  = 113;
    public static inline var F3:Int  = 114;
    public static inline var F4:Int  = 115;
    public static inline var F5:Int  = 116;
    public static inline var F6:Int  = 117;
    public static inline var F7:Int  = 118;
    public static inline var F8:Int  = 119;
    public static inline var F9:Int  = 120;
    public static inline var F10:Int = 121;
    public static inline var F11:Int = 122;
    public static inline var F12:Int = 123;

    public static inline var SEMICOLON:Int  = 186;
    public static inline var EQUALS:Int     = 187;
    public static inline var COMMA:Int      = 188;
    public static inline var MINUS:Int      = 189;
    public static inline var PERIOD:Int     = 190;
    public static inline var SLASH:Int      = 191;
    public static inline var BACKQUOTE:Int  = 192;
    public static inline var LBRACKET:Int   = 219;
    public static inline var BACKSLASH:Int  = 220;
    public static inline var RBRACKET:Int   = 221;
    public static inline var QUOTE:Int      = 222;

    private static var keyDownMap:Map<Int, Bool> = new Map();
    private static var keyLatchMap:Map<Int, Bool> = new Map();

    public static inline function isDown(code:Int):Bool {
        return keyDownMap.get(code) == true;
    }

    public static inline function isDownOrTapped(code:Int):Bool {
        return keyDownMap.get(code) == true || keyLatchMap.get(code) == true;
    }

    public static inline function setKeyState(code:Int, down:Bool):Void {
        if (code != 0) {
            if (down && keyDownMap.get(code) != true) {
                keyLatchMap.set(code, true);
            }
            keyDownMap.set(code, down);
        }
    }

    public static function clearLatches():Void {
        keyLatchMap.clear();
    }

    public static function clearAll():Void {
        keyDownMap.clear();
        keyLatchMap.clear();
    }

    /** Maps `hlwindow` W3C `window.KeyCode` to `InputKey` scan code. */
    public static function fromWindowKeyCode(code:KeyCode):Int {
        var kc:Int = code;
        return switch (kc) {
            case KeyCode.KeyA: A; case KeyCode.KeyB: B; case KeyCode.KeyC: C; case KeyCode.KeyD: D; case KeyCode.KeyE: E;
            case KeyCode.KeyF: F; case KeyCode.KeyG: G; case KeyCode.KeyH: H; case KeyCode.KeyI: I; case KeyCode.KeyJ: J;
            case KeyCode.KeyK: K; case KeyCode.KeyL: L; case KeyCode.KeyM: M; case KeyCode.KeyN: N; case KeyCode.KeyO: O;
            case KeyCode.KeyP: P; case KeyCode.KeyQ: Q; case KeyCode.KeyR: R; case KeyCode.KeyS: S; case KeyCode.KeyT: T;
            case KeyCode.KeyU: U; case KeyCode.KeyV: V; case KeyCode.KeyW: W; case KeyCode.KeyX: X; case KeyCode.KeyY: Y;
            case KeyCode.KeyZ: Z;
            case KeyCode.Digit0: NUMBER_0; case KeyCode.Digit1: NUMBER_1; case KeyCode.Digit2: NUMBER_2;
            case KeyCode.Digit3: NUMBER_3; case KeyCode.Digit4: NUMBER_4; case KeyCode.Digit5: NUMBER_5;
            case KeyCode.Digit6: NUMBER_6; case KeyCode.Digit7: NUMBER_7; case KeyCode.Digit8: NUMBER_8;
            case KeyCode.Digit9: NUMBER_9;
            case KeyCode.Numpad0: NUMPAD_0; case KeyCode.Numpad1: NUMPAD_1; case KeyCode.Numpad2: NUMPAD_2;
            case KeyCode.Numpad3: NUMPAD_3; case KeyCode.Numpad4: NUMPAD_4; case KeyCode.Numpad5: NUMPAD_5;
            case KeyCode.Numpad6: NUMPAD_6; case KeyCode.Numpad7: NUMPAD_7; case KeyCode.Numpad8: NUMPAD_8;
            case KeyCode.Numpad9: NUMPAD_9;
            case KeyCode.NumpadEnter: ENTER;
            case KeyCode.NumpadAdd: NUMPAD_ADD;
            case KeyCode.NumpadSubtract: NUMPAD_SUB;
            case KeyCode.NumpadMultiply: NUMPAD_MULT;
            case KeyCode.NumpadDivide: NUMPAD_DIV;
            case KeyCode.NumpadDecimal: NUMPAD_DOT;
            case KeyCode.ArrowLeft: LEFT;
            case KeyCode.ArrowUp: UP;
            case KeyCode.ArrowRight: RIGHT;
            case KeyCode.ArrowDown: DOWN;
            case KeyCode.Space: SPACE;
            case KeyCode.ShiftLeft | KeyCode.ShiftRight: SHIFT;
            case KeyCode.ControlLeft | KeyCode.ControlRight: CTRL;
            case KeyCode.AltLeft | KeyCode.AltRight: ALT;
            case KeyCode.Enter: ENTER;
            case KeyCode.Escape: ESCAPE;
            case KeyCode.Tab: TAB;
            case KeyCode.Backspace: BACKSPACE;
            case KeyCode.Delete: DELETE;
            case KeyCode.Insert: INSERT;
            case KeyCode.Home: HOME;
            case KeyCode.End: END;
            case KeyCode.PageUp: PGUP;
            case KeyCode.PageDown: PGDOWN;
            case KeyCode.F1: F1; case KeyCode.F2: F2; case KeyCode.F3: F3; case KeyCode.F4: F4;
            case KeyCode.F5: F5; case KeyCode.F6: F6; case KeyCode.F7: F7; case KeyCode.F8: F8;
            case KeyCode.F9: F9; case KeyCode.F10: F10; case KeyCode.F11: F11; case KeyCode.F12: F12;
            case KeyCode.Semicolon: SEMICOLON;
            case KeyCode.Equal: EQUALS;
            case KeyCode.Comma: COMMA;
            case KeyCode.Minus: MINUS;
            case KeyCode.Period: PERIOD;
            case KeyCode.Slash: SLASH;
            case KeyCode.Backquote: BACKQUOTE;
            case KeyCode.BracketLeft: LBRACKET;
            case KeyCode.Backslash: BACKSLASH;
            case KeyCode.BracketRight: RBRACKET;
            case KeyCode.Quote: QUOTE;
            default: 0;
        };
    }
}
