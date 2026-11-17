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

/**
 * Browser relay transport bridged to `web/ui-overlay.js` via `core.WebBridge`.
 * Browser main-thread handles WebSocket -> HTTP POST poll (`/relay.ashx`) -> BroadcastChannel fallback.
 */
class WebSocketTransport implements ISocketTransport {
    private static var NEXT_ID:Int = 1;
    private static var ACTIVE:Map<Int, WebSocketTransport> = new Map();

    private var transportId:Int;
    private var _connected:Bool = false;
    private var _connectSent:Bool = false;
    private var _connId:String = "";
    private var _roomId:String = "";
    private var _isHost:Bool = false;

    public var isConnected(get, never):Bool;
    public var connId(get, never):String;
    public var roomId(get, never):String;
    public var isHost(get, never):Bool;

    inline function get_isConnected():Bool return _connected;
    inline function get_connId():String return _connId;
    inline function get_roomId():String return _roomId;
    inline function get_isHost():Bool return _isHost;

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

    public function new() {
        transportId = NEXT_ID++;
    }

    public static function dispatchBridgeEvent(ev:Dynamic):Void {
        if (ev == null) return;
        var tid:Int = ev.id != null ? ev.id : 0;
        var tr = ACTIVE.get(tid);
        if (tr == null) return;
        tr.handleEvent(ev);
    }

    private function handleEvent(ev:Dynamic):Void {
        var op:String = ev.op;
        switch (op) {
            case "open":
                _connected = true;
                if (ev.connId != null) _connId = Std.string(ev.connId);
                if (onOpen != null) onOpen();
            case "close":
                _connected = false;
                _connectSent = false;
                _roomId = "";
                _isHost = false;
                var reason = ev.reason != null ? Std.string(ev.reason) : "closed";
                if (onClose != null) onClose(reason);
            case "error":
                if (!_connected) _connectSent = false;
                var err = ev.error != null ? Std.string(ev.error) : "transport error";
                if (onError != null) onError(err);
            case "hosted":
                _roomId = ev.roomId != null ? Std.string(ev.roomId) : "";
                if (ev.connId != null) _connId = Std.string(ev.connId);
                _isHost = true;
                if (onRoomHosted != null) onRoomHosted(_roomId, _connId);
            case "joined":
                _roomId = ev.roomId != null ? Std.string(ev.roomId) : "";
                if (ev.connId != null) _connId = Std.string(ev.connId);
                _isHost = false;
                if (onRoomJoined != null) onRoomJoined(_roomId, _connId);
            case "peer_join":
                if (onPeerSocketConnected != null && ev.peerId != null) {
                    onPeerSocketConnected(Std.string(ev.peerId));
                }
            case "peer_leave":
                if (onPeerSocketDisconnected != null && ev.peerId != null) {
                    onPeerSocketDisconnected(Std.string(ev.peerId));
                }
            case "from_peer":
                if (onRelayedFromPeer != null && ev.fromId != null) {
                    onRelayedFromPeer(Std.string(ev.fromId), ev.payload);
                }
            case "from_host":
                if (onRelayedFromHost != null) {
                    onRelayedFromHost(ev.payload);
                }
            case "host_lost":
                _roomId = "";
                _isHost = false;
                if (onHostDisconnected != null) onHostDisconnected();
            default:
        }
    }

    public function connect(?url:String):Void {
        _connectSent = true;
        ACTIVE.set(transportId, this);
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "connect",
            url: url != null ? url : ""
        });
    }

    public function disconnect():Void {
        _connected = false;
        _connectSent = false;
        _roomId = "";
        _isHost = false;
        ACTIVE.remove(transportId);
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "disconnect"
        });
    }

    public function hostRoom(?requestedRoomId:String):Void {
        if (!_connected && !_connectSent) connect();
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "host_room",
            roomId: requestedRoomId != null ? requestedRoomId : ""
        });
    }

    public function joinRoom(roomId:String):Void {
        if (!_connected && !_connectSent) connect();
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "join_room",
            roomId: roomId != null ? roomId : ""
        });
    }

    public function sendToHost(payload:Dynamic):Void {
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "send_to_host",
            payload: payload
        });
    }

    public function sendToPeer(targetId:String, payload:Dynamic):Void {
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "send_to_peer",
            targetId: targetId,
            payload: payload
        });
    }

    public function broadcastToPeers(payload:Dynamic):Void {
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "broadcast",
            payload: payload
        });
    }

    public function leaveRoom():Void {
        _roomId = "";
        _isHost = false;
        core.WebBridge.inst.pushEvent({
            type: "net_cmd",
            id: transportId,
            op: "leave_room"
        });
    }
}