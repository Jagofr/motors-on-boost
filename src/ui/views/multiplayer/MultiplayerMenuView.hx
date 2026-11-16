package ui.views.multiplayer;

import audio.AudioManager;
import h2d.Bitmap;
import h2d.Interactive;
import h2d.Object;
import h2d.Text;
import net.MultiplayerManager;
import ui.FontManager;
import ui.UIIcons;
import ui.components.UITheme;

/**
 * Peer-to-peer multiplayer entry menu ("Host or Join").
 * Presents two side-by-side options: hosting a new Host-validated room or
 * joining an existing lobby directly by entering or pasting a 6-character Invite Code.
 *
 * @class MultiplayerMenuView
 * @extends h2d.Object
 * @module ui/views/multiplayer/MultiplayerMenuView
 */
@:keep
class MultiplayerMenuView extends Object {
    /** Screen header title text. */
    public var titleText:Text;

    /** Screen header subtitle text. */
    public var subtitleText:Text;

    /** Back button text and interactive hitzone. */
    public var backBtnText:Text;
    public var backInteractive:Interactive;

    /** Card headers, tags, descriptions, launch labels, icons, and click hitzones (0 = Host, 1 = Join). */
    public var modeTitles:Array<Text> = [];
    public var modeTags:Array<Text> = [];
    public var modeDescs:Array<Text> = [];
    public var modeLaunchLabels:Array<Text> = [];
    public var modeIcons:Array<Bitmap> = [];
    public var modeInteractives:Array<Interactive> = [];

    /** Invite code entry UI elements inside the Join card preview terminal. */
    public var codeBoxLabel:Text;
    public var codeValueText:Text;
    public var codeHintText:Text;
    public var codeBoxInteractive:Interactive;
    public var clearCodeText:Text;
    public var clearCodeInteractive:Interactive;

    /** Currently selected card index (0 = Host a Match, 1 = Join by Invite Code). */
    public var selectedIndex:Int = 0;

    /** Currently entered room invite code string (normalized uppercase). */
    public var enteredCode:String = "";

    /** Callback triggered when Host a Match is confirmed. */
    public var onHostSelected:Null<Void->Void>;

    /** Callback triggered when Join by Invite Code is confirmed with a non-empty normalized code. */
    public var onJoinSelected:Null<String->Void>;

    /** Callback triggered when the player exits back to the Main Menu. */
    public var onBack:Null<Void->Void>;

    /** Callback triggered when card focus or code state changes so backplates redraw cleanly. */
    public var onSelectionChanged:Null<Void->Void>;

    private var consumedBackspaceCancel:Bool = false;
    private var defaultHintMessage:String = "Type A-Z / 0-9, paste link, or tap box";

    public function new(?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.titleFont, this);
        titleText.text = "MULTIPLAYER // HOST OR JOIN";
        titleText.textColor = UITheme.COLOR_ACCENT_CYAN;

        subtitleText = new Text(FontManager.regularFont, this);
        subtitleText.text = "CHOOSE SESSION ROLE OR ENTER A 6-CHARACTER INVITE CODE";
        subtitleText.textColor = UITheme.COLOR_TEXT_MUTED;

        backBtnText = new Text(FontManager.regularFont, this);
        backBtnText.text = "< BACK";
        backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;

        backInteractive = new Interactive(UITheme.BACK_BUTTON_WIDTH, UITheme.BACK_BUTTON_HEIGHT, this);
        backInteractive.onOver = function(_) {
            if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_GOLD;
        };
        backInteractive.onOut = function(_) {
            if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;
        };
        backInteractive.onClick = function(_) {
            if (visible && onBack != null) {
                AudioManager.inst.playMenuBeep(320.0, 0.06);
                onBack();
            }
        };

        var titles = [
            "HOST A MATCH",
            "JOIN BY INVITE CODE"
        ];
        var tags = [
            "CREATE LOBBY  |  HOST VALIDATED  |  UP TO 8 DRIVERS",
            "ENTER 6-CHAR INVITE CODE  |  OR PASTE INVITE LINK"
        ];
        var descs = [
            "Open a new relay lobby, pick Highway Circuit or Sandbox, and validate connected peers.",
            "Type or paste the Host's room code (e.g. X5VC8D) below to enter their match directly."
        ];
        var launches = [
            "CREATE & HOST LOBBY >",
            "JOIN WITH INVITE CODE >"
        ];
        var iconTypes = [
            UIIcons.IconType.Multiplayer,
            UIIcons.IconType.Play
        ];

        for (i in 0...2) {
            var idx = i;
            var ic = new Bitmap(UIIcons.get(iconTypes[i], UITheme.ICON_SIZE_MENU, UITheme.COLOR_ACCENT_CYAN), this);
            modeIcons.push(ic);

            var tTitle = new Text(FontManager.titleFont, this);
            tTitle.text = titles[i];
            modeTitles.push(tTitle);

            var tTag = new Text(FontManager.regularFont, this);
            tTag.text = tags[i];
            modeTags.push(tTag);

            var tDesc = new Text(FontManager.regularFont, this);
            tDesc.text = descs[i];
            tDesc.lineSpacing = 2.0;
            modeDescs.push(tDesc);

            var tLaunch = new Text(FontManager.regularFont, this);
            tLaunch.text = launches[i];
            modeLaunchLabels.push(tLaunch);

            var inter = new Interactive(360, 320, this);
            inter.onOver = function(_) {
                if (visible && selectedIndex != idx) {
                    selectedIndex = idx;
                    updateStyles();
                    if (onSelectionChanged != null) onSelectionChanged();
                }
            };
            inter.onClick = function(_) {
                if (!visible) return;
                selectedIndex = idx;
                updateStyles();
                if (onSelectionChanged != null) onSelectionChanged();
                confirmSelection();
            };
            modeInteractives.push(inter);
        }

        // Interactive Invite Code box overlays inside Card 1's preview region (added after modeInteractives)
        codeBoxLabel = new Text(FontManager.regularFont, this);
        codeBoxLabel.text = "INVITE CODE:";
        codeBoxLabel.textColor = UITheme.COLOR_ACCENT_CYAN;
        codeBoxLabel.scale(0.84);

        codeBoxInteractive = new Interactive(220, 40, this);
        codeBoxInteractive.onClick = function(_) {
            if (!visible) return;
            selectedIndex = 1;
            codeHintText.text = defaultHintMessage;
            codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
            #if js
            var hasWin:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof window.prompt === 'function'");
            if (hasWin) {
                var entered:String = js.Browser.window.prompt("Enter Invite Code or Paste Invite Link (e.g. X5VC8D):", enteredCode);
                if (entered != null) {
                    setInviteCode(entered);
                    AudioManager.inst.playMenuBeep(480.0, 0.05);
                    return;
                }
            }
            #end
            updateStyles();
            if (onSelectionChanged != null) onSelectionChanged();
        };

        codeValueText = new Text(FontManager.titleFont, this);
        codeValueText.scale(0.95);

        clearCodeInteractive = new Interactive(58, 40, this);
        clearCodeInteractive.onClick = function(_) {
            if (!visible) return;
            selectedIndex = 1;
            enteredCode = "";
            codeHintText.text = defaultHintMessage;
            codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
            AudioManager.inst.playMenuBeep(300.0, 0.04);
            updateStyles();
            if (onSelectionChanged != null) onSelectionChanged();
        };
        clearCodeText = new Text(FontManager.regularFont, this);
        clearCodeText.text = "CLEAR";
        clearCodeText.textColor = UITheme.COLOR_TEXT_MUTED;
        clearCodeText.scale(0.80);

        codeHintText = new Text(FontManager.regularFont, this);
        codeHintText.text = defaultHintMessage;
        codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
        codeHintText.scale(0.76);

        #if js
        var hasDom:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof window.addEventListener === 'function'");
        if (hasDom) {
            js.Browser.window.addEventListener("paste", function(ev:Dynamic) {
                if (!visible) return;
                try {
                    var clip:String = ev != null && ev.clipboardData != null ? ev.clipboardData.getData("text") : "";
                    if (clip != null && StringTools.trim(clip) != "") {
                        setInviteCode(clip);
                        AudioManager.inst.playMenuBeep(520.0, 0.05);
                    }
                } catch (_e:Dynamic) {}
            }, true);

            js.Browser.window.addEventListener("keydown", function(ev:Dynamic) {
                if (!visible || ev == null) return;
                if (ev.ctrlKey || ev.altKey || ev.metaKey) return;
                var key:String = ev.key != null ? Std.string(ev.key) : "";
                if (key == "Backspace") {
                    if (selectedIndex == 1 && enteredCode.length > 0) {
                        if (backspaceCode() && ev.preventDefault != null) ev.preventDefault();
                    }
                    return;
                }
                if (key.length == 1) {
                    var code = key.charCodeAt(0);
                    var isAlphaNum = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
                    if (!isAlphaNum) return;
                    var upper = key.toUpperCase();
                    if (selectedIndex == 1 || (upper != "W" && upper != "A" && upper != "S" && upper != "D")) {
                        appendCodeChar(upper);
                    }
                }
            }, true);
        }
        #end

        updateStyles();
    }

    /**
     * Activates the Host-or-Join view cleanly without discarding a partially entered code.
     */
    public function activate():Void {
        visible = true;
        consumedBackspaceCancel = false;
        if (codeHintText != null) {
            codeHintText.text = defaultHintMessage;
            codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
        }
        updateStyles();
    }

    /**
     * Replaces the entered Invite Code with a sanitized/normalized code extracted from raw text or URL.
     */
    public function setInviteCode(raw:String):Void {
        enteredCode = MultiplayerManager.extractRoomCode(raw);
        if (enteredCode != "") selectedIndex = 1;
        if (codeHintText != null) {
            codeHintText.text = defaultHintMessage;
            codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
        }
        updateStyles();
        if (onSelectionChanged != null) onSelectionChanged();
    }

    /**
     * Appends one alphanumeric character to the Invite Code buffer (max 8 chars) and selects Join card.
     */
    public function appendCodeChar(ch:String):Void {
        var clean = MultiplayerManager.extractRoomCode(ch);
        if (clean == "") return;
        for (i in 0...clean.length) {
            if (enteredCode.length < 8) {
                enteredCode += clean.charAt(i);
            }
        }
        selectedIndex = 1;
        if (codeHintText != null) {
            codeHintText.text = defaultHintMessage;
            codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
        }
        AudioManager.inst.playMenuBeep(440.0, 0.03);
        updateStyles();
        if (onSelectionChanged != null) onSelectionChanged();
    }

    /**
     * Removes the last character from the Invite Code buffer and flags backspace suppression for UI cancel.
     */
    public function backspaceCode():Bool {
        if (enteredCode.length <= 0) return false;
        enteredCode = enteredCode.substr(0, enteredCode.length - 1);
        consumedBackspaceCancel = true;
        if (codeHintText != null) {
            codeHintText.text = defaultHintMessage;
            codeHintText.textColor = UITheme.COLOR_TEXT_MUTED;
        }
        AudioManager.inst.playMenuBeep(300.0, 0.03);
        updateStyles();
        if (onSelectionChanged != null) onSelectionChanged();
        return true;
    }

    /**
     * Returns true once if Backspace edited the code buffer this frame so UI cancel does not exit the menu.
     */
    public function consumeBackspaceCancel():Bool {
        if (!consumedBackspaceCancel) return false;
        consumedBackspaceCancel = false;
        return true;
    }

    /**
     * When Card 1 (Join by Invite Code) is focused, WASD letters type into the code box instead of moving cards.
     */
    public function shouldCaptureWasdAsText():Bool {
        return selectedIndex == 1;
    }

    /**
     * Navigates between Host a Match (0) and Join by Invite Code (1).
     */
    public function navigate(dir:Int):Void {
        selectedIndex = (selectedIndex + dir + 2) % 2;
        AudioManager.inst.playMenuBeep(380.0, 0.04);
        updateStyles();
        if (onSelectionChanged != null) onSelectionChanged();
    }

    /**
     * Executes the active card: launches Host room creation or validates and joins the entered Invite Code.
     */
    public function confirmSelection():Void {
        if (selectedIndex == 0) {
            AudioManager.inst.playMenuBeep(540.0, 0.08);
            if (onHostSelected != null) onHostSelected();
            return;
        }

        var code = MultiplayerManager.extractRoomCode(enteredCode);
        if (code == "") {
            #if js
            var hasWin:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof window.prompt === 'function'");
            if (hasWin) {
                var prompted:String = js.Browser.window.prompt("Enter 6-character Invite Code or Paste Invite Link:", "");
                if (prompted != null && StringTools.trim(prompted) != "") {
                    code = MultiplayerManager.extractRoomCode(prompted);
                    enteredCode = code;
                }
            }
            #end
        }

        if (code != "") {
            enteredCode = code;
            updateStyles();
            AudioManager.inst.playMenuBeep(540.0, 0.08);
            if (onJoinSelected != null) onJoinSelected(code);
        } else {
            AudioManager.inst.playMenuBeep(220.0, 0.06);
            if (codeHintText != null) {
                codeHintText.text = "ENTER A 6-CHAR INVITE CODE FIRST (TYPE A-Z / 0-9)";
                codeHintText.textColor = UITheme.COLOR_ACCENT_ORANGE;
            }
            updateStyles();
        }
    }

    /**
     * Refreshes colors and Invite Code display formatting across both cards.
     */
    public function updateStyles():Void {
        for (i in 0...2) {
            var isSel = (i == selectedIndex);
            modeTitles[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : 0xFFFFFF;
            modeTags[i].textColor = isSel ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_TEXT_MUTED;
            modeDescs[i].textColor = isSel ? UITheme.COLOR_TEXT_NORMAL : UITheme.COLOR_TEXT_MUTED;
            modeLaunchLabels[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_TEXT_MUTED;
            modeIcons[i].color.setColor(isSel ? UITheme.COLOR_ACCENT_CYAN : UITheme.COLOR_TEXT_MUTED);
        }

        if (codeValueText != null) {
            if (enteredCode.length > 0) {
                codeValueText.text = enteredCode;
                codeValueText.textColor = UITheme.COLOR_ACCENT_GOLD;
            } else {
                codeValueText.text = "- - - - - -";
                codeValueText.textColor = (selectedIndex == 1) ? 0xA0B8D0 : UITheme.COLOR_TEXT_MUTED;
            }
        }
        if (clearCodeText != null) {
            clearCodeText.textColor = (enteredCode.length > 0) ? UITheme.COLOR_ACCENT_ORANGE : 0x7A8FA6;
        }
    }

    /**
     * Layouts the Host-or-Join cards, Invite Code box, and interactive hitzones.
     */
    public function layout(sw:Float, sh:Float):Void {
        var cardW = Math.min(UITheme.MAP_SELECT_CARD_WIDTH, sw - 32.0);
        var cardH = Math.min(UITheme.MAP_SELECT_CARD_HEIGHT, sh - 110.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(68.0, (sh - cardH) * 0.5 + 8.0);

        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = Math.max(14.0, cardY - 52.0);
        }

        if (subtitleText != null) {
            subtitleText.x = (sw - subtitleText.textWidth) * 0.5;
            subtitleText.y = cardY + 20.0;
        }

        if (backBtnText != null && backInteractive != null) {
            backBtnText.x = cardX + 28.0;
            backBtnText.y = cardY + 20.0;
            backInteractive.x = cardX + 20.0;
            backInteractive.y = cardY + 12.0;
            backInteractive.width = UITheme.BACK_BUTTON_WIDTH;
            backInteractive.height = UITheme.BACK_BUTTON_HEIGHT;
        }

        var padX = 28.0;
        var gap = 24.0;
        var modeCardW = (cardW - (padX * 2.0) - gap) * 0.5;
        var modeCardH = cardH - 134.0;
        var modeCardY = cardY + 74.0;
        var prevH = Math.max(84.0, modeCardH * 0.40);

        for (i in 0...2) {
            var mx = cardX + padX + i * (modeCardW + gap);
            var contentY = modeCardY + 16.0 + prevH + 10.0;

            modeIcons[i].x = mx + 18.0;
            modeIcons[i].y = contentY + 4.0;

            modeTitles[i].x = mx + 50.0;
            modeTitles[i].y = contentY;

            modeTags[i].x = mx + 18.0;
            modeTags[i].y = contentY + 36.0;

            modeDescs[i].maxWidth = modeCardW - 36.0;
            modeDescs[i].x = mx + 18.0;
            modeDescs[i].y = contentY + 62.0;

            var pillH = 38.0;
            var pillY = modeCardY + modeCardH - pillH - 14.0;
            modeLaunchLabels[i].x = mx + (modeCardW - modeLaunchLabels[i].textWidth) * 0.5;
            modeLaunchLabels[i].y = pillY - 1.0;

            modeInteractives[i].x = mx;
            modeInteractives[i].y = modeCardY;
            modeInteractives[i].width = modeCardW;
            modeInteractives[i].height = modeCardH;
        }

        // Layout Invite Code terminal elements inside Card 1's preview box
        var mx1 = cardX + padX + (modeCardW + gap);
        var prevX = mx1 + 16.0;
        var prevY = modeCardY + 16.0;
        var prevW = modeCardW - 32.0;

        codeBoxLabel.x = prevX + 14.0;
        codeBoxLabel.y = prevY + 9.0;

        var boxX = prevX + 14.0;
        var boxY = prevY + 34.0;
        var boxW = Math.max(120.0, prevW - 92.0);
        var boxH = 40.0;

        codeBoxInteractive.x = boxX;
        codeBoxInteractive.y = boxY;
        codeBoxInteractive.width = boxW;
        codeBoxInteractive.height = boxH;

        codeValueText.x = boxX + 14.0;
        codeValueText.y = boxY - 11.0;

        var clrX = prevX + prevW - 72.0;
        clearCodeInteractive.x = clrX;
        clearCodeInteractive.y = boxY;
        clearCodeInteractive.width = 58.0;
        clearCodeInteractive.height = boxH;
        clearCodeText.x = clrX + (58.0 - clearCodeText.textWidth * clearCodeText.scaleX) * 0.5;
        clearCodeText.y = boxY + 4.0;

        codeHintText.x = prevX + 14.0;
        codeHintText.y = prevY + prevH - 28.0;
    }
}
