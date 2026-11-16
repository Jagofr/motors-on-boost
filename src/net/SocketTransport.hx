package net;

import haxe.Json;

/**
 * Abstract socket transport interface separating the dumb room relay (WebSocket / BroadcastChannel / InMemory)
 * from Host-authoritative game validation in MultiplayerManager.
 */
interface ISocketTransport {
    public var isConnected(get, never):Bool;
    public var connId(get, never):String;
    public var roomId(get, never):String;
    public var isHost(get, never):Bool;

    public var onOpen:Void->Void;
    public var onClose:String->Void;
    public var onError:String->Void;
    public var onRoomHosted:String->String->Void;
    public var onRoomJoined:String->String->Void;
    public var onPeerSocketConnected:String->Void;
    public var onPeerSocketDisconnected:String->Void;
    public var onRelayedFromPeer:String->Dynamic->Void;
    public var onRelayedFromHost:Dynamic->Void;
    public var onHostDisconnected:Void->Void;

    public function connect(?url:String):Void;
    public function disconnect():Void;
    public function hostRoom(?requestedRoomId:String):Void;
    public function joinRoom(roomId:String):Void;
    public function sendToHost(payload:Dynamic):Void;
    public function sendToPeer(targetId:String, payload:Dynamic):Void;
    public function broadcastToPeers(payload:Dynamic):Void;
    public function leaveRoom():Void;
}

/**
 * Pure deterministic in-memory socket relay hub mirroring server/socket-relay.js
 * with zero game validation logic, used by automated unit tests.
 */
class InMemoryRelayHub {
    private var nextSeq:Int = 1;
    private var rooms:Map<String, { id:String, host:InMemorySocketTransport, peers:Array<InMemorySocketTransport> }> = new Map();

    public function new() {}

    public function allocConnId():String {
        return "mem_" + (nextSeq++);
    }

    public function createTransport():InMemorySocketTransport {
        return new InMemorySocketTransport(this);
    }

    public function hostRoom(client:InMemorySocketTransport, ?requestedRoomId:String):Void {
        detach(client);
        var code = (requestedRoomId != null && StringTools.trim(requestedRoomId) != "")
            ? StringTools.trim(requestedRoomId).toUpperCase()
            : ("ROOM" + (nextSeq++));
        if (rooms.exists(code)) {
            code = "ROOM" + (nextSeq++);
        }
        client.assignRoom(code, true);
        rooms.set(code, { id: code, host: client, peers: [] });
        if (client.onRoomHosted != null) client.onRoomHosted(code, client.connId);
    }

    public function joinRoom(client:InMemorySocketTransport, roomId:String):Void {
        detach(client);
        var code = roomId != null ? StringTools.trim(roomId).toUpperCase() : "";
        var room = rooms.get(code);
        if (room == null) {
            if (client.onError != null) client.onError('Room "' + code + '" was not found or host went offline.');
            return;
        }
        client.assignRoom(code, false);
        room.peers.push(client);
        if (client.onRoomJoined != null) client.onRoomJoined(code, client.connId);
        if (room.host.onPeerSocketConnected != null) room.host.onPeerSocketConnected(client.connId);
    }

    public function relayToHost(client:InMemorySocketTransport, payload:Dynamic):Void {
        if (client.roomId == "" || client.isHost) return;
        var room = rooms.get(client.roomId);
        if (room != null && room.host.onRelayedFromPeer != null) {
            room.host.onRelayedFromPeer(client.connId, Json.parse(Json.stringify(payload)));
        }
    }

    public function relayToPeer(hostClient:InMemorySocketTransport, targetId:String, payload:Dynamic):Void {
        if (hostClient.roomId == "" || !hostClient.isHost) return;
        var room = rooms.get(hostClient.roomId);
        if (room == null) return;
        for (peer in room.peers) {
            if (peer.connId == targetId && peer.onRelayedFromHost != null) {
                peer.onRelayedFromHost(Json.parse(Json.stringify(payload)));
                break;
            }
        }
    }

    public function relayBroadcast(hostClient:InMemorySocketTransport, payload:Dynamic):Void {
        if (hostClient.roomId == "" || !hostClient.isHost) return;
        var room = rooms.get(hostClient.roomId);
        if (room == null) return;
        var serialized = Json.stringify(payload);
        for (peer in room.peers) {
            if (peer.onRelayedFromHost != null) {
                peer.onRelayedFromHost(Json.parse(serialized));
            }
        }
    }

    public function detach(client:InMemorySocketTransport):Void {
        if (client.roomId == "") return;
        var code = client.roomId;
        var wasHost = client.isHost;
        client.assignRoom("", false);
        var room = rooms.get(code);
        if (room == null) return;

        if (wasHost && room.host == client) {
            var oldPeers = room.peers.copy();
            room.peers = [];
            rooms.remove(code);
            for (peer in oldPeers) {
                peer.assignRoom("", false);
                if (peer.onHostDisconnected != null) peer.onHostDisconnected();
            }
        } else {
            room.peers.remove(client);
            if (room.host.onPeerSocketDisconnected != null) {
                room.host.onPeerSocketDisconnected(client.connId);
            }
        }
    }
}

/**
 * In-memory implementation of ISocketTransport backed by InMemoryRelayHub.
 */
class InMemorySocketTransport implements ISocketTransport {
    private var hub:InMemoryRelayHub;
    private var _connected:Bool = false;
    private var _connId:String = "";
    private var _roomId:String = "";
    private var _isHost:Bool = false;

    public var isConnected(get, never):Bool;
    public var connId(get, never):String;
    public var roomId(get, never):String;
    public var isHost(get, never):Bool;

    public var onOpen:Void->Void;
    public var onClose:String->Void;
    public var onError:String->Void;
    public var onRoomHosted:String->String->Void;
    public var onRoomJoined:String->String->Void;
    public var onPeerSocketConnected:String->Void;
    public var onPeerSocketDisconnected:String->Void;
    public var onRelayedFromPeer:String->Dynamic->Void;
    public var onRelayedFromHost:Dynamic->Void;
    public var onHostDisconnected:Void->Void;

    public function new(hub:InMemoryRelayHub) {
        this.hub = hub;
        this._connId = hub.allocConnId();
    }

    function get_isConnected():Bool return _connected;
    function get_connId():String return _connId;
    function get_roomId():String return _roomId;
    function get_isHost():Bool return _isHost;

    @:allow(net.InMemoryRelayHub)
    function assignRoom(rid:String, hosting:Bool):Void {
        _roomId = rid;
        _isHost = hosting;
    }

    public function connect(?url:String):Void {
        _connected = true;
        if (onOpen != null) onOpen();
    }

    public function disconnect():Void {
        hub.detach(this);
        _connected = false;
        if (onClose != null) onClose("disconnected");
    }

    public function hostRoom(?requestedRoomId:String):Void {
        if (!_connected) connect();
        hub.hostRoom(this, requestedRoomId);
    }

    public function joinRoom(roomId:String):Void {
        if (!_connected) connect();
        hub.joinRoom(this, roomId);
    }

    public function sendToHost(payload:Dynamic):Void {
        hub.relayToHost(this, payload);
    }

    public function sendToPeer(targetId:String, payload:Dynamic):Void {
        hub.relayToPeer(this, targetId, payload);
    }

    public function broadcastToPeers(payload:Dynamic):Void {
        hub.relayBroadcast(this, payload);
    }

    public function leaveRoom():Void {
        hub.detach(this);
    }
}

/**
 * Browser WebSocket + HTTP relay client (`/relay.ashx`) with BroadcastChannel fallback only when
 * no HTTP/WS server endpoint is reachable (e.g. `file://` or static server without relay).
 */
class WebSocketTransport implements ISocketTransport {
    private var _connected:Bool = false;
    private var _connId:String = "";
    private var _roomId:String = "";
    private var _isHost:Bool = false;
    private var _explicitUrl:String = "";
    private var _ws:Dynamic = null;
    private var _wsConnecting:Bool = false;
    private var _welcomeReceived:Bool = false;
    private var _useHttpRelay:Bool = false;
    private var _httpOutbox:Array<Dynamic> = [];
    private var _httpInFlight:Bool = false;
    private var _httpPollTimerId:Dynamic = null;
    private var _httpFailures:Int = 0;
    private var _useBroadcastFallback:Bool = false;
    private var _bc:Dynamic = null;
    private var _bcPeers:Array<String> = [];
    private var _bcJoinedAck:Bool = false;
    private var _bcJoinTimerId:Dynamic = null;
    private var _pendingAction:Null<Void->Void> = null;
    private var _fallbackTimerId:Dynamic = null;

    public var isConnected(get, never):Bool;
    public var connId(get, never):String;
    public var roomId(get, never):String;
    public var isHost(get, never):Bool;

    public var onOpen:Void->Void;
    public var onClose:String->Void;
    public var onError:String->Void;
    public var onRoomHosted:String->String->Void;
    public var onRoomJoined:String->String->Void;
    public var onPeerSocketConnected:String->Void;
    public var onPeerSocketDisconnected:String->Void;
    public var onRelayedFromPeer:String->Dynamic->Void;
    public var onRelayedFromHost:Dynamic->Void;
    public var onHostDisconnected:Void->Void;

    public function new() {}

    function get_isConnected():Bool return _connected;
    function get_connId():String return _connId;
    function get_roomId():String return _roomId;
    function get_isHost():Bool return _isHost;

    private function resolveWsUrl(?explicitUrl:String):String {
        if (explicitUrl != null && explicitUrl != "") return explicitUrl;
        #if js
        var hasWindow:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof window.location !== 'undefined'");
        if (hasWindow) {
            var loc = js.Browser.location;
            if (loc.protocol == "http:" || loc.protocol == "https:") {
                var proto = (loc.protocol == "https:") ? "wss:" : "ws:";
                return proto + "//" + loc.host + "/relay.ashx";
            }
        }
        #end
        return "ws://127.0.0.1:8090/relay.ashx";
    }

    private function resolveHttpRelayUrl():String {
        #if js
        if (_explicitUrl != null && _explicitUrl != "") {
            if (StringTools.startsWith(_explicitUrl, "wss://")) return "https://" + _explicitUrl.substr(6);
            if (StringTools.startsWith(_explicitUrl, "ws://")) return "http://" + _explicitUrl.substr(5);
            return _explicitUrl;
        }
        var hasWindow:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof window.location !== 'undefined'");
        if (hasWindow) {
            var loc = js.Browser.location;
            if (loc.protocol == "http:" || loc.protocol == "https:") {
                return loc.protocol + "//" + loc.host + "/relay.ashx";
            }
        }
        #end
        return "";
    }

    public function connect(?url:String):Void {
        #if js
        var canBrowser:Bool = js.Syntax.code("typeof window !== 'undefined'");
        if (!canBrowser) {
            if (onError != null) onError("Relay transport unavailable outside browser runtime.");
            return;
        }
        if (_connected || _wsConnecting || _useHttpRelay) return;

        _explicitUrl = (url != null) ? url : "";
        _welcomeReceived = false;
        _useHttpRelay = false;
        _useBroadcastFallback = false;
        _httpOutbox = [];
        _httpInFlight = false;
        _httpFailures = 0;

        var hasWs:Bool = js.Syntax.code("typeof WebSocket !== 'undefined'");
        var httpUrl = resolveHttpRelayUrl();
        if (!hasWs || (httpUrl == "" && _explicitUrl == "")) {
            if (httpUrl != "") activateHttpRelay();
            else activateBroadcastFallback();
            return;
        }

        var targetUrl = resolveWsUrl(url);
        _wsConnecting = true;

        try {
            var sock:Dynamic = js.Syntax.code("new WebSocket({0})", targetUrl);
            _ws = sock;

            _fallbackTimerId = js.Browser.window.setTimeout(function() {
                if (!_welcomeReceived && !_useHttpRelay && !_useBroadcastFallback) {
                    closeRawWs();
                    activateHttpRelay();
                }
            }, 1000);

            sock.onopen = function(_ev:Dynamic) {
                // Wait briefly for relay 'welcome' frame
            };

            sock.onmessage = function(ev:Dynamic) {
                try {
                    var msg:Dynamic = Json.parse(Std.string(ev.data));
                    handleWsEnvelope(msg);
                } catch (_err:Dynamic) {}
            };

            sock.onerror = function(_ev:Dynamic) {
                if (!_welcomeReceived) {
                    clearFallbackTimer();
                    closeRawWs();
                    activateHttpRelay();
                } else if (onError != null) {
                    onError("WebSocket transport error.");
                }
            };

            sock.onclose = function(_ev:Dynamic) {
                clearFallbackTimer();
                var wasWelcome = _welcomeReceived;
                _wsConnecting = false;
                if (!wasWelcome) {
                    closeRawWs();
                    activateHttpRelay();
                    return;
                }
                _connected = false;
                _roomId = "";
                _isHost = false;
                if (onClose != null) onClose("Socket closed.");
            };
        } catch (_err:Dynamic) {
            clearFallbackTimer();
            closeRawWs();
            activateHttpRelay();
        }
        #end
    }

    private function closeRawWs():Void {
        if (_ws != null) {
            try {
                _ws.onopen = null;
                _ws.onmessage = null;
                _ws.onerror = null;
                _ws.onclose = null;
                _ws.close();
            } catch (_e:Dynamic) {}
            _ws = null;
        }
        _wsConnecting = false;
    }

    private function clearFallbackTimer():Void {
        #if js
        if (_fallbackTimerId != null) {
            js.Browser.window.clearTimeout(_fallbackTimerId);
            _fallbackTimerId = null;
        }
        #end
    }

    private function clearHttpPollTimer():Void {
        #if js
        if (_httpPollTimerId != null) {
            js.Browser.window.clearInterval(_httpPollTimerId);
            _httpPollTimerId = null;
        }
        #end
    }

    private function clearBcJoinTimer():Void {
        #if js
        if (_bcJoinTimerId != null) {
            js.Browser.window.clearTimeout(_bcJoinTimerId);
            _bcJoinTimerId = null;
        }
        #end
    }

    private function activateHttpRelay():Void {
        #if js
        if (_useHttpRelay || _useBroadcastFallback) return;
        clearFallbackTimer();
        closeRawWs();

        var httpUrl = resolveHttpRelayUrl();
        var hasXhr:Bool = js.Syntax.code("typeof XMLHttpRequest !== 'undefined'");
        if (httpUrl == "" || !hasXhr) {
            activateBroadcastFallback();
            return;
        }

        _useHttpRelay = true;
        _httpFailures = 0;
        _httpInFlight = false;

        clearHttpPollTimer();
        _httpPollTimerId = js.Browser.window.setInterval(function() {
            if (_useHttpRelay && !_httpInFlight) {
                flushHttpRelay(true);
            }
        }, 60);

        flushHttpRelay(true);
        #end
    }

    private function flushHttpRelay(allowEmpty:Bool):Void {
        #if js
        if (!_useHttpRelay) return;
        if (_httpInFlight) return;
        if (!allowEmpty && _httpOutbox.length == 0) return;

        var httpUrl = resolveHttpRelayUrl();
        if (httpUrl == "") return;

        var batch = _httpOutbox.copy();
        _httpOutbox = [];
        _httpInFlight = true;

        try {
            var xhr:Dynamic = js.Syntax.code("new XMLHttpRequest()");
            xhr.open("POST", httpUrl, true);
            xhr.timeout = 4500;
            xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");

            var handleFailure = function(statusCode:Int) {
                _httpInFlight = false;
                if (!_useHttpRelay) return;
                _httpFailures++;
                if (!_welcomeReceived && (statusCode == 404 || statusCode == 405 || statusCode == 501 || _httpFailures >= 2)) {
                    clearHttpPollTimer();
                    _useHttpRelay = false;
                    _httpOutbox = [];
                    activateBroadcastFallback();
                    return;
                }
                if (_welcomeReceived && _httpFailures >= 25) {
                    _httpFailures = 0;
                    if (onError != null) onError("Connection to multiplayer relay was interrupted.");
                }
            };

            xhr.onreadystatechange = function() {
                if (xhr.readyState != 4) return;
                if (!_useHttpRelay) {
                    _httpInFlight = false;
                    return;
                }
                if (xhr.status >= 200 && xhr.status < 300) {
                    _httpFailures = 0;
                    _httpInFlight = false;
                    try {
                        var res:Dynamic = Json.parse(Std.string(xhr.responseText));
                        if (res != null && res.connId != null && Std.string(res.connId) != "") {
                            _connId = Std.string(res.connId);
                        }
                        if (res != null && res.events != null) {
                            var evs:Array<Dynamic> = cast res.events;
                            for (ev in evs) {
                                handleWsEnvelope(ev);
                            }
                        }
                    } catch (_e:Dynamic) {}
                    if (_useHttpRelay && _httpOutbox.length > 0 && !_httpInFlight) {
                        flushHttpRelay(false);
                    }
                } else {
                    handleFailure(Std.int(xhr.status));
                }
            };

            xhr.onerror = function() handleFailure(0);
            xhr.ontimeout = function() handleFailure(0);

            var payload = Json.stringify({ connId: _connId, messages: batch });
            xhr.send(payload);
        } catch (_err:Dynamic) {
            _httpInFlight = false;
            _useHttpRelay = false;
            clearHttpPollTimer();
            activateBroadcastFallback();
        }
        #end
    }

    private function activateBroadcastFallback():Void {
        #if js
        if (_useBroadcastFallback) return;
        clearFallbackTimer();
        clearHttpPollTimer();
        closeRawWs();
        _useHttpRelay = false;

        var hasBC:Bool = js.Syntax.code("typeof BroadcastChannel !== 'undefined'");
        if (!hasBC) {
            _connected = false;
            if (onError != null) onError("Could not connect to multiplayer relay (/relay.ashx).");
            return;
        }

        _useBroadcastFallback = true;
        _connected = true;
        if (_connId == "") {
            _connId = "tab_" + Std.string(Math.floor(Math.random() * 900000) + 100000);
        }
        _bc = js.Syntax.code("new BroadcastChannel('mob_p2p_relay')");
        _bc.onmessage = function(ev:Dynamic) {
            handleBroadcastEnvelope(ev.data);
        };

        if (onOpen != null) onOpen();
        flushPendingAction();
        #end
    }

    private function handleWsEnvelope(msg:Dynamic):Void {
        if (msg == null) return;
        var msgType:String = Std.string(msg.type);
        switch (msgType) {
            case "welcome":
                clearFallbackTimer();
                _welcomeReceived = true;
                _wsConnecting = false;
                _connected = true;
                _connId = Std.string(msg.connId);
                if (onOpen != null) onOpen();
                flushPendingAction();
            case "room_hosted":
                _roomId = Std.string(msg.roomId);
                _isHost = true;
                if (msg.connId != null) _connId = Std.string(msg.connId);
                if (onRoomHosted != null) onRoomHosted(_roomId, _connId);
            case "room_joined":
                _roomId = Std.string(msg.roomId);
                _isHost = false;
                if (msg.connId != null) _connId = Std.string(msg.connId);
                if (onRoomJoined != null) onRoomJoined(_roomId, _connId);
            case "peer_socket_connected":
                if (onPeerSocketConnected != null) onPeerSocketConnected(Std.string(msg.peerId));
            case "peer_socket_disconnected":
                if (onPeerSocketDisconnected != null) onPeerSocketDisconnected(Std.string(msg.peerId));
            case "relayed_from_peer":
                if (onRelayedFromPeer != null) onRelayedFromPeer(Std.string(msg.fromId), msg.payload);
            case "relayed_from_host":
                if (onRelayedFromHost != null) onRelayedFromHost(msg.payload);
            case "host_disconnected":
                _roomId = "";
                _isHost = false;
                if (onHostDisconnected != null) onHostDisconnected();
            case "relay_error":
                if (onError != null) onError(Std.string(msg.message));
            default:
        }
    }

    private function handleBroadcastEnvelope(msg:Dynamic):Void {
        if (msg == null || msg.fromId == _connId) return;
        var t:String = Std.string(msg.type);
        if (_isHost && _roomId != "" && msg.roomId == _roomId) {
            if (t == "join_room") {
                var pid = Std.string(msg.fromId);
                if (_bcPeers.indexOf(pid) < 0) _bcPeers.push(pid);
                if (_bc != null) _bc.postMessage({ type: "room_joined", roomId: _roomId, targetId: pid, fromId: _connId });
                if (onPeerSocketConnected != null) onPeerSocketConnected(pid);
            } else if (t == "relay_to_host") {
                if (onRelayedFromPeer != null) onRelayedFromPeer(Std.string(msg.fromId), msg.payload);
            } else if (t == "leave_room") {
                var pid = Std.string(msg.fromId);
                _bcPeers.remove(pid);
                if (onPeerSocketDisconnected != null) onPeerSocketDisconnected(pid);
            }
        } else if (!_isHost && _roomId != "" && msg.roomId == _roomId) {
            if (t == "room_joined" && msg.targetId == _connId) {
                _bcJoinedAck = true;
                clearBcJoinTimer();
                if (onRoomJoined != null) onRoomJoined(_roomId, _connId);
            } else if (t == "relay_to_peer" && msg.targetId == _connId) {
                if (onRelayedFromHost != null) onRelayedFromHost(msg.payload);
            } else if (t == "relay_broadcast") {
                if (onRelayedFromHost != null) onRelayedFromHost(msg.payload);
            } else if (t == "host_disconnected") {
                _roomId = "";
                _isHost = false;
                if (onHostDisconnected != null) onHostDisconnected();
            }
        }
    }

    private function flushPendingAction():Void {
        if (_pendingAction != null) {
            var fn = _pendingAction;
            _pendingAction = null;
            fn();
        }
    }

    private function sendRaw(obj:Dynamic):Void {
        if (_useHttpRelay && _welcomeReceived && !_useBroadcastFallback) {
            _httpOutbox.push(obj);
            flushHttpRelay(false);
            return;
        }
        if (_ws != null && _welcomeReceived && !_useBroadcastFallback && !_useHttpRelay) {
            try {
                _ws.send(Json.stringify(obj));
            } catch (_e:Dynamic) {}
        }
    }

    public function disconnect():Void {
        clearFallbackTimer();
        clearHttpPollTimer();
        clearBcJoinTimer();
        leaveRoom();
        _pendingAction = null;
        _httpOutbox = [];
        _httpInFlight = false;
        closeRawWs();
        if (_bc != null) {
            try { _bc.close(); } catch (_e:Dynamic) {}
            _bc = null;
        }
        _connected = false;
        _wsConnecting = false;
        _welcomeReceived = false;
        _useHttpRelay = false;
        _useBroadcastFallback = false;
    }

    public function hostRoom(?requestedRoomId:String):Void {
        if (!_connected || (!_useBroadcastFallback && !_welcomeReceived)) {
            _pendingAction = function() hostRoom(requestedRoomId);
            connect();
            return;
        }
        if (_useBroadcastFallback) {
            clearBcJoinTimer();
            var code = (requestedRoomId != null && StringTools.trim(requestedRoomId) != "")
                ? StringTools.trim(requestedRoomId).toUpperCase()
                : makeFallbackCode();
            _roomId = code;
            _isHost = true;
            _bcPeers = [];
            if (onRoomHosted != null) onRoomHosted(_roomId, _connId);
            return;
        }
        sendRaw({ type: "host_room", roomId: requestedRoomId });
    }

    public function joinRoom(roomId:String):Void {
        var clean = roomId != null ? StringTools.trim(roomId).toUpperCase() : "";
        if (!_connected || (!_useBroadcastFallback && !_welcomeReceived)) {
            _pendingAction = function() joinRoom(clean);
            connect();
            return;
        }
        if (_useBroadcastFallback) {
            #if js
            clearBcJoinTimer();
            _bcJoinedAck = false;
            _roomId = clean;
            _isHost = false;
            if (_bc != null) _bc.postMessage({ type: "join_room", roomId: clean, fromId: _connId });
            _bcJoinTimerId = js.Browser.window.setTimeout(function() {
                if (_useBroadcastFallback && !_isHost && _roomId == clean && !_bcJoinedAck) {
                    _roomId = "";
                    if (onError != null) onError('Room "' + clean + '" was not found on this browser (local fallback active).');
                }
            }, 2500);
            #end
            return;
        }
        sendRaw({ type: "join_room", roomId: clean });
    }

    public function sendToHost(payload:Dynamic):Void {
        if (_useBroadcastFallback) {
            if (_bc != null && _roomId != "") _bc.postMessage({ type: "relay_to_host", roomId: _roomId, fromId: _connId, payload: payload });
            return;
        }
        sendRaw({ type: "relay_to_host", payload: payload });
    }

    public function sendToPeer(targetId:String, payload:Dynamic):Void {
        if (_useBroadcastFallback) {
            if (_bc != null && _roomId != "") _bc.postMessage({ type: "relay_to_peer", roomId: _roomId, targetId: targetId, fromId: _connId, payload: payload });
            return;
        }
        sendRaw({ type: "relay_to_peer", targetId: targetId, payload: payload });
    }

    public function broadcastToPeers(payload:Dynamic):Void {
        if (_useBroadcastFallback) {
            if (_bc != null && _roomId != "") _bc.postMessage({ type: "relay_broadcast", roomId: _roomId, fromId: _connId, payload: payload });
            return;
        }
        sendRaw({ type: "relay_broadcast", payload: payload });
    }

    public function leaveRoom():Void {
        clearBcJoinTimer();
        if (_useBroadcastFallback) {
            if (_bc != null && _roomId != "") {
                if (_isHost) {
                    _bc.postMessage({ type: "host_disconnected", roomId: _roomId, fromId: _connId });
                } else {
                    _bc.postMessage({ type: "leave_room", roomId: _roomId, fromId: _connId });
                }
            }
            _roomId = "";
            _isHost = false;
            _bcPeers = [];
            return;
        }
        if ((_ws != null || _useHttpRelay) && _welcomeReceived && _roomId != "") {
            sendRaw({ type: "leave_room" });
        }
        _roomId = "";
        _isHost = false;
    }

    private function makeFallbackCode():String {
        var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var s = "";
        for (i in 0...6) s += chars.charAt(Math.floor(Math.random() * chars.length));
        return s;
    }
}
