package ui.views.multiplayer;

import audio.AudioManager;
import h2d.Interactive;
import h2d.Object;
import h2d.Text;
import net.MultiplayerManager;
import net.NetworkProtocol;
import net.NetworkProtocol.LobbyStatus;
import net.NetworkProtocol.NetworkRole;
import ui.FontManager;
import ui.UIIcons;
import ui.components.UITheme;
import world.WorldManager.MapMode;

/**
 * Interactive peer-to-peer multiplayer staging lobby.
 * Displays the active room code / invite URL, Host-authoritative map selector
 * (Highway Circuit or Sandbox Proving Grounds), live driver roster with assigned liveries,
 * and Host Start Match controls.
 */
class MultiplayerLobbyView extends Object {
    private var mp:Null<MultiplayerManager>;

    private var titleText:Text;
    private var subtitleText:Text;
    private var roomBannerText:Text;
    private var statusText:Text;

    private var mapHeader:Text;
    private var mapTitles:Array<Text> = [];
    private var mapDescs:Array<Text> = [];
    private var mapBadges:Array<Text> = [];
    public var mapInteractives:Array<Interactive> = [];

    private var rosterHeader:Text;
    private var rosterLines:Array<Text> = [];

    private var copyLinkText:Text;
    public var copyLinkInteractive:Interactive;

    private var joinCodeText:Text;
    public var joinCodeInteractive:Interactive;

    private var hostRoomText:Text;
    public var hostRoomInteractive:Interactive;

    private var startMatchText:Text;
    public var startMatchInteractive:Interactive;

    private var backBtnText:Text;
    public var backInteractive:Interactive;

    /** Callback triggered when user presses Back to exit multiplayer lobby. */
    public var onBack:Void->Void;

    /** Callback triggered so UIBuilder can redraw card backplate highlights. */
    public var onVisualRefresh:Void->Void;

    /** Highlighted map card index (0 = Circuit, 1 = Sandbox). */
    public var selectedMapIndex:Int = 0;

    /** Focused bottom action index (0 = Copy Invite / Host, 1 = Start Match). */
    public var focusedActionIdx:Int = 1;

    private var copyFeedbackTimer:Float = 0.0;

    public function new(?mpManager:MultiplayerManager, ?parent:Object) {
        super(parent);
        this.mp = mpManager;

        titleText = new Text(FontManager.titleFont, this);
        titleText.text = "MULTIPLAYER LOBBY";
        titleText.textColor = 0xFFFFFF;
        titleText.scale(1.18);

        subtitleText = new Text(FontManager.regularFont, this);
        subtitleText.text = "PEER-TO-PEER HOST VALIDATED MATCH";
        subtitleText.textColor = UITheme.COLOR_ACCENT_CYAN;
        subtitleText.scale(0.86);

        roomBannerText = new Text(FontManager.regularFont, this);
        roomBannerText.textColor = 0xFFFFFF;
        roomBannerText.scale(0.90);

        statusText = new Text(FontManager.regularFont, this);
        statusText.textColor = UITheme.COLOR_ACCENT_GOLD;
        statusText.scale(0.84);

        mapHeader = new Text(FontManager.regularFont, this);
        mapHeader.text = "SELECT MATCH ARENA (HOST PICK)";
        mapHeader.textColor = UITheme.COLOR_TEXT_MUTED;
        mapHeader.scale(0.84);

        var mTitles = ["HIGHWAY CIRCUIT", "SANDBOX PROVING GROUNDS"];
        var mDescs = [
            "Closed asphalt loop track\nHigh-speed banked corners & rails",
            "Open undulating off-road terrain\nRamps, jumps & asphalt skidpad"
        ];
        var modes:Array<MapMode> = [Circuit, Sandbox];

        for (i in 0...2) {
            var inter = new Interactive(360, 110, this);
            var idx = i;
            var mode = modes[i];
            inter.onClick = function(_) {
                if (!visible) return;
                if (mp != null && mp.role == Client) {
                    AudioManager.inst.playMenuBeep(220.0, 0.05);
                    return;
                }
                AudioManager.inst.playMenuBeep(460.0, 0.06);
                selectedMapIndex = idx;
                if (mp != null) mp.setSelectedMap(mode);
                refreshFromManager();
                if (onVisualRefresh != null) onVisualRefresh();
            };
            mapInteractives.push(inter);

            var t = new Text(FontManager.titleFont, this);
            t.text = mTitles[i];
            t.scale(0.88);
            mapTitles.push(t);

            var d = new Text(FontManager.regularFont, this);
            d.text = mDescs[i];
            d.textColor = UITheme.COLOR_TEXT_MUTED;
            d.scale(0.78);
            mapDescs.push(d);

            var b = new Text(FontManager.regularFont, this);
            b.scale(0.76);
            mapBadges.push(b);
        }

        rosterHeader = new Text(FontManager.regularFont, this);
        rosterHeader.text = "CONNECTED DRIVERS (0 / 8)";
        rosterHeader.textColor = UITheme.COLOR_ACCENT_CYAN;
        rosterHeader.scale(0.86);

        for (i in 0...NetworkProtocol.MAX_PLAYERS) {
            var line = new Text(FontManager.regularFont, this);
            line.text = "";
            line.scale(0.88);
            rosterLines.push(line);
        }

        copyLinkInteractive = new Interactive(220, 38, this);
        copyLinkInteractive.onOver = function(_) { if (visible) { focusedActionIdx = 0; if (onVisualRefresh != null) onVisualRefresh(); } };
        copyLinkInteractive.onClick = function(_) {
            if (!visible || mp == null || mp.roomId == "") return;
            MultiplayerManager.copyInviteLinkToClipboard(mp.getInviteLink());
            copyFeedbackTimer = 2.5;
            AudioManager.inst.playMenuBeep(560.0, 0.07);
            refreshFromManager();
        };
        copyLinkText = new Text(FontManager.regularFont, this);
        copyLinkText.text = "COPY INVITE LINK";
        copyLinkText.textColor = UITheme.COLOR_ACCENT_CYAN;
        copyLinkText.scale(0.92);

        hostRoomInteractive = new Interactive(170, 38, this);
        hostRoomInteractive.onClick = function(_) {
            if (!visible || mp == null) return;
            AudioManager.inst.playMenuBeep(500.0, 0.07);
            mp.hostRoom();
        };
        hostRoomText = new Text(FontManager.regularFont, this);
        hostRoomText.text = "HOST ROOM";
        hostRoomText.textColor = UITheme.COLOR_ACCENT_CYAN;
        hostRoomText.scale(0.90);

        joinCodeInteractive = new Interactive(170, 38, this);
        joinCodeInteractive.onClick = function(_) {
            if (!visible || mp == null) return;
            #if js
            var hasWin:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof window.prompt === 'function'");
            if (hasWin) {
                var entered:String = js.Browser.window.prompt("Paste Invite URL or Room Code (e.g. ABC123):", "");
                if (entered != null && StringTools.trim(entered) != "") {
                    var parsed = MultiplayerManager.extractRoomCode(entered);
                    AudioManager.inst.playMenuBeep(480.0, 0.07);
                    mp.joinRoom(parsed);
                }
            }
            #end
        };
        joinCodeText = new Text(FontManager.regularFont, this);
        joinCodeText.text = "JOIN BY CODE";
        joinCodeText.textColor = 0xFFFFFF;
        joinCodeText.scale(0.90);

        startMatchInteractive = new Interactive(220, 38, this);
        startMatchInteractive.onOver = function(_) { if (visible) { focusedActionIdx = 1; if (onVisualRefresh != null) onVisualRefresh(); } };
        startMatchInteractive.onClick = function(_) {
            if (!visible || mp == null) return;
            if (mp.role == Host && mp.status == WaitingInLobby) {
                AudioManager.inst.playMenuBeep(600.0, 0.09);
                mp.startMatch();
            } else {
                AudioManager.inst.playMenuBeep(220.0, 0.05);
            }
        };
        startMatchText = new Text(FontManager.titleFont, this);
        startMatchText.text = "START MATCH";
        startMatchText.textColor = UITheme.COLOR_ACCENT_GOLD;
        startMatchText.scale(0.86);

        backInteractive = new Interactive(UITheme.BACK_BUTTON_WIDTH, UITheme.BACK_BUTTON_HEIGHT, this);
        backInteractive.onOver = function(_) { if (visible) backBtnText.textColor = UITheme.COLOR_ACCENT_GOLD; };
        backInteractive.onOut = function(_) { if (visible) backBtnText.textColor = UITheme.COLOR_TEXT_NORMAL; };
        backInteractive.onClick = function(_) {
            if (!visible) return;
            AudioManager.inst.playMenuBeep(320.0, 0.06);
            if (onBack != null) onBack();
        };
        backBtnText = new Text(FontManager.regularFont, this);
        backBtnText.text = "< BACK";
        backBtnText.textColor = UITheme.COLOR_TEXT_NORMAL;
        backBtnText.scale(0.95);
    }

    public function setMultiplayerManager(mpManager:MultiplayerManager):Void {
        this.mp = mpManager;
        refreshFromManager();
    }

    public function isHostRole():Bool {
        return mp != null && mp.role == Host;
    }

    public function activate():Void {
        visible = true;
        focusedActionIdx = 1;
        refreshFromManager();
    }

    public function updateTimer(dt:Float):Void {
        if (copyFeedbackTimer > 0.0) {
            copyFeedbackTimer -= dt;
            if (copyFeedbackTimer <= 0.0) {
                copyFeedbackTimer = 0.0;
                refreshFromManager();
            }
        }
    }

    public function navigate(dir:Int):Void {
        if (mp != null && mp.role == Client) return;
        selectedMapIndex = (selectedMapIndex + dir + 2) % 2;
        AudioManager.inst.playMenuBeep(380.0, 0.04);
        if (mp != null) {
            mp.setSelectedMap(selectedMapIndex == 0 ? Circuit : Sandbox);
        }
        refreshFromManager();
        if (onVisualRefresh != null) onVisualRefresh();
    }

    public function confirmFocused():Void {
        if (mp == null) return;
        if (mp.role == Host && mp.status == WaitingInLobby) {
            AudioManager.inst.playMenuBeep(600.0, 0.09);
            mp.startMatch();
        } else if (mp.role == None || mp.status == Disconnected) {
            mp.hostRoom();
        }
    }

    public function refreshFromManager():Void {
        if (mp == null) return;

        selectedMapIndex = (mp.selectedMap == Sandbox) ? 1 : 0;

        var isHost = (mp.role == Host);
        var isClient = (mp.role == Client);
        var inLobby = (mp.status == WaitingInLobby);

        subtitleText.text = isHost
            ? "ROLE: HOST (AUTHORITATIVE VALIDATION & SERVER RELAY)"
            : (isClient ? "ROLE: CLIENT (WAITING FOR HOST START)" : "PEER-TO-PEER CLIENT/SERVER RELAY");
        subtitleText.textColor = isHost ? UITheme.COLOR_ACCENT_GOLD : UITheme.COLOR_ACCENT_CYAN;

        if (mp.roomId != "") {
            var link = mp.getInviteLink();
            if (link.length > 52) link = link.substr(0, 49) + "...";
            roomBannerText.text = "INVITE CODE: " + mp.roomId + "   |   INVITE: " + link;
        } else {
            roomBannerText.text = "NO ACTIVE ROOM  -  HOST A MATCH OR OPEN AN INVITE LINK (?room=CODE)";
        }

        if (mp.lastError != "") {
            statusText.text = "ERROR: " + mp.lastError;
            statusText.textColor = UITheme.COLOR_ACCENT_ORANGE;
        } else {
            statusText.text = mp.statusMessage;
            statusText.textColor = inLobby ? 0x00E676 : UITheme.COLOR_ACCENT_GOLD;
        }

        mapHeader.text = isHost
            ? "SELECT MATCH ARENA (HOST PICK)"
            : (isClient ? "ARENA CHOSEN BY HOST" : "SELECT ARENA");

        for (i in 0...2) {
            var isSel = (i == selectedMapIndex);
            mapTitles[i].textColor = isSel ? UITheme.COLOR_ACCENT_CYAN : 0xFFFFFF;
            mapBadges[i].text = isSel ? (isClient ? "[ HOST SELECTED ]" : "[ ACTIVE ARENA ]") : "";
            mapBadges[i].textColor = UITheme.COLOR_ACCENT_GOLD;
        }

        rosterHeader.text = "CONNECTED DRIVERS (" + mp.peers.length + " / " + NetworkProtocol.MAX_PLAYERS + ")";
        for (i in 0...rosterLines.length) {
            if (i < mp.peers.length) {
                var p = mp.peers[i];
                var tag = p.isHost ? "[HOST] " : ("[P" + (p.slotIndex + 1) + "] ");
                var youTag = (p.peerId == mp.localPeerId) ? "  (YOU)" : "";
                rosterLines[i].text = tag + p.name + youTag;
                rosterLines[i].textColor = p.colorHex;
                rosterLines[i].visible = true;
            } else {
                rosterLines[i].text = "-- OPEN GRID SLOT --";
                rosterLines[i].textColor = 0x455364;
                rosterLines[i].visible = (i < 4 || mp.peers.length > 4);
            }
        }

        copyLinkInteractive.visible = (mp.roomId != "");
        copyLinkText.visible = copyLinkInteractive.visible;
        copyLinkText.text = (copyFeedbackTimer > 0.0) ? "INVITE LINK COPIED!" : "COPY INVITE LINK";
        copyLinkText.textColor = (copyFeedbackTimer > 0.0) ? 0x00E676 : UITheme.COLOR_ACCENT_CYAN;

        var showOfflineBtns = (!inLobby && mp.status != Connecting);
        hostRoomInteractive.visible = showOfflineBtns;
        hostRoomText.visible = showOfflineBtns;
        joinCodeInteractive.visible = showOfflineBtns;
        joinCodeText.visible = showOfflineBtns;

        startMatchInteractive.visible = isHost && inLobby;
        startMatchText.visible = startMatchInteractive.visible;
    }

    public function layout(sw:Float, sh:Float):Void {
        var cardW = Math.min(UITheme.LOBBY_CARD_WIDTH, sw - 28.0);
        var cardH = Math.min(UITheme.LOBBY_CARD_HEIGHT, sh - 76.0);
        var cardX = (sw - cardW) * 0.5;
        var cardY = Math.max(46.0, (sh - cardH) * 0.5 + 6.0);

        titleText.x = cardX + 24.0;
        titleText.y = cardY + 14.0;

        subtitleText.x = cardX + cardW - 24.0 - subtitleText.textWidth * subtitleText.scaleX;
        subtitleText.y = cardY + 20.0;

        roomBannerText.x = cardX + 38.0;
        roomBannerText.y = cardY + 72.0;

        statusText.x = cardX + 38.0;
        statusText.y = cardY + 95.0;

        var bodyTop = cardY + 132.0;
        var bodyH = cardH - 208.0;
        var leftW = (cardW - 64.0) * 0.52;
        var rightW = (cardW - 64.0) - leftW;
        var rightX = cardX + 24.0 + leftW + 16.0;

        mapHeader.x = cardX + 24.0;
        mapHeader.y = bodyTop - 25.0;

        var mapBtnH = (bodyH - 12.0) * 0.5;
        for (i in 0...2) {
            var my = bodyTop + i * (mapBtnH + 12.0);
            mapInteractives[i].x = cardX + 24.0;
            mapInteractives[i].y = my;
            mapInteractives[i].width = leftW;
            mapInteractives[i].height = mapBtnH;

            mapTitles[i].x = cardX + 40.0;
            mapTitles[i].y = my + 12.0;

            mapDescs[i].x = cardX + 40.0;
            mapDescs[i].y = my + 42.0;

            mapBadges[i].x = cardX + 40.0;
            mapBadges[i].y = my + mapBtnH - 28.0;
        }

        rosterHeader.x = rightX + 14.0;
        rosterHeader.y = bodyTop + 10.0;
        for (i in 0...rosterLines.length) {
            rosterLines[i].x = rightX + 16.0;
            rosterLines[i].y = bodyTop + 36.0 + i * 26.0;
        }

        var btnY = cardY + cardH - 58.0;
        var halfBtnW = Math.min(230.0, (cardW - 200.0) * 0.5);

        copyLinkInteractive.x = cardX + 24.0;
        copyLinkInteractive.y = btnY;
        copyLinkInteractive.width = halfBtnW;
        copyLinkInteractive.height = 38.0;
        copyLinkText.x = copyLinkInteractive.x + (halfBtnW - copyLinkText.textWidth * copyLinkText.scaleX) * 0.5;
        copyLinkText.y = btnY + 1.0;

        hostRoomInteractive.x = cardX + 24.0;
        hostRoomInteractive.y = btnY;
        hostRoomInteractive.width = 160.0;
        hostRoomInteractive.height = 38.0;
        hostRoomText.x = hostRoomInteractive.x + 28.0;
        hostRoomText.y = btnY + 1.0;

        joinCodeInteractive.x = cardX + 200.0;
        joinCodeInteractive.y = btnY;
        joinCodeInteractive.width = 160.0;
        joinCodeInteractive.height = 38.0;
        joinCodeText.x = joinCodeInteractive.x + 24.0;
        joinCodeText.y = btnY + 1.0;

        startMatchInteractive.x = cardX + cardW - 24.0 - halfBtnW;
        startMatchInteractive.y = btnY;
        startMatchInteractive.width = halfBtnW;
        startMatchInteractive.height = 38.0;
        startMatchText.x = startMatchInteractive.x + (halfBtnW - startMatchText.textWidth * startMatchText.scaleX) * 0.5;
        startMatchText.y = btnY - 9.0;

        backInteractive.x = (sw - UITheme.BACK_BUTTON_WIDTH) * 0.5;
        backInteractive.y = btnY + 4.0;
        backBtnText.x = backInteractive.x + (UITheme.BACK_BUTTON_WIDTH - backBtnText.textWidth * backBtnText.scaleX) * 0.5;
        backBtnText.y = btnY;
    }
}
