package net;

import world.WorldManager.MapMode;

/**
 * Peer role within a peer-to-peer client/server multiplayer session.
 */
enum NetworkRole {
    None;
    Host;
    Client;
}

/**
 * Lifecycle stage of the local multiplayer session.
 */
enum LobbyStatus {
    Disconnected;
    Connecting;
    WaitingInLobby;
    InMatch;
}

/**
 * Host-assigned slot metadata for a driver in the lobby and active race.
 */
typedef PeerSlotInfo = {
    var peerId:String;
    var name:String;
    var slotIndex:Int;
    var colorHex:Int;
    var isHost:Bool;
    var ready:Bool;
}

/**
 * Starting grid spawn coordinate assigned by the Host for each peer.
 */
typedef SpawnSlot = {
    var peerId:String;
    var x:Float;
    var y:Float;
    var z:Float;
    var yaw:Float;
}

/**
 * Unvalidated kinematics + input packet sent by a joining Client to the Host.
 */
typedef ClientInputPacket = {
    var type:String;
    var peerId:String;
    var seq:Int;
    var throttle:Float;
    var brake:Float;
    var steer:Float;
    var handbrake:Bool;
    var boosting:Bool;
    var x:Float;
    var y:Float;
    var z:Float;
    var yaw:Float;
    var pitch:Float;
    var roll:Float;
    var forwardSpeed:Float;
    var lateralVelocity:Float;
    var wheelSpinAngle:Float;
}

/**
 * Host-validated remote vehicle snapshot broadcast to all peers.
 */
typedef NetCarState = {
    var peerId:String;
    var name:String;
    var slotIndex:Int;
    var colorHex:Int;
    var x:Float;
    var y:Float;
    var z:Float;
    var yaw:Float;
    var pitch:Float;
    var roll:Float;
    var forwardSpeed:Float;
    var lateralVelocity:Float;
    var steerAngle:Float;
    var wheelSpinAngle:Float;
    var boosting:Bool;
}

/**
 * Shared protocol identifiers, limits, and map conversion helpers.
 */
@:keep
class NetworkProtocol {
    public static inline var MSG_JOIN_REQUEST:String = "join_request";
    public static inline var MSG_JOIN_ACCEPTED:String = "join_accepted";
    public static inline var MSG_JOIN_REJECTED:String = "join_rejected";
    public static inline var MSG_LOBBY_STATE:String = "lobby_state";
    public static inline var MSG_START_MATCH:String = "start_match";
    public static inline var MSG_CLIENT_STATE:String = "client_state";
    public static inline var MSG_WORLD_SNAPSHOT:String = "world_snapshot";
    public static inline var MSG_HOST_RETURN_TO_LOBBY:String = "host_return_to_lobby";

    public static inline var MAP_CIRCUIT:String = "circuit";
    public static inline var MAP_SANDBOX:String = "sandbox";

    public static inline var MAX_PLAYERS:Int = 8;

    /** Distinct vivid car liveries assigned sequentially by Host slot index. */
    public static var PLAYER_COLORS:Array<Int> = [
        0xE64A19, // Slot 0 (Host): Radiant Sports Orange
        0x00E5FF, // Slot 1: Electric Cyan
        0xFFD600, // Slot 2: Racing Yellow
        0x00E676, // Slot 3: Neon Lime
        0xFF2E93, // Slot 4: Hyper Magenta
        0x9C27B0, // Slot 5: Royal Violet
        0xFFFFFF, // Slot 6: Pearl White
        0x2979FF  // Slot 7: Cobalt Blue
    ];

    public static function getPaletteColor(slotIndex:Int):Int {
        var idx = slotIndex % PLAYER_COLORS.length;
        if (idx < 0) idx += PLAYER_COLORS.length;
        return PLAYER_COLORS[idx];
    }

    public static function mapModeToId(mode:MapMode):String {
        return switch (mode) {
            case Sandbox: MAP_SANDBOX;
            case Circuit: MAP_CIRCUIT;
        };
    }

    public static function mapIdToMode(id:String):MapMode {
        return (id == MAP_SANDBOX) ? Sandbox : Circuit;
    }

    public static function getMapDisplayName(mode:MapMode):String {
        return switch (mode) {
            case Sandbox: "SANDBOX PROVING GROUNDS";
            case Circuit: "HIGHWAY CIRCUIT";
        };
    }
}
