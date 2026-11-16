package net;

import h3d.Vector;
import input.InputController;
import net.NetworkProtocol.ClientInputPacket;
import net.NetworkProtocol.NetCarState;
import net.NetworkProtocol.NetworkRole;
import net.NetworkProtocol.LobbyStatus;
import net.NetworkProtocol.PeerSlotInfo;
import net.NetworkProtocol.SpawnSlot;
import net.SocketTransport.ISocketTransport;
import physics.CarPhysics;
import world.IGroundProvider;
import world.Track;
import world.WorldManager.MapMode;

/**
 * Host-authoritative peer-to-peer multiplayer coordinator.
 * All validation — protocol version checks, room capacity enforcement, callsign sanitization,
 * map selection authority, staggered grid spawning, anti-teleport clamping, speed bounds, and
 * boundary enforcement — executes exclusively on the Host client, while the server acts strictly
 * as a stateless socket connection relay.
 */
class MultiplayerManager {
    /** Network snapshot dispatch rate (seconds between updates; 0.04s = 25 Hz). */
    public static inline var SYNC_INTERVAL:Float = 0.04;

    /** Maximum permitted vehicle speed scalar accepted by Host validation (m/s). */
    public static inline var MAX_VALID_FORWARD_SPEED:Float = 95.0;

    /** Maximum permitted reverse speed scalar accepted by Host validation (m/s). */
    public static inline var MAX_VALID_REVERSE_SPEED:Float = -25.0;

    /** Maximum permitted lateral slip speed accepted by Host validation (m/s). */
    public static inline var MAX_VALID_LATERAL_SPEED:Float = 45.0;

    /** Interval between automatic MSG_JOIN_REQUEST retries while waiting for Host validation (seconds). */
    public static inline var JOIN_RETRY_INTERVAL:Float = 0.8;

    /** Maximum wait before aborting a stalled join attempt with an actionable error message (seconds). */
    public static inline var JOIN_TIMEOUT_SECONDS:Float = 8.0;

    /** Underlying stateless socket relay transport. */
    public var transport(default, null):ISocketTransport;

    /** Current network role of this client instance. */
    public var role(default, null):NetworkRole = None;

    /** Current lobby/match lifecycle state. */
    public var status(default, null):LobbyStatus = Disconnected;

    /** Active room code assigned by relay when hosting or joined by invite link. */
    public var roomId(default, null):String = "";

    /** Ephemeral socket peer ID assigned by relay. */
    public var localPeerId(default, null):String = "";

    /** Local player callsign advertised during join requests or room creation. */
    public var localCallsign:String = "DRIVER";

    /** Host-selected track/sandbox map for the upcoming match. */
    public var selectedMap(default, null):MapMode = Circuit;

    /** Current driver roster synced from Host. */
    public var peers(default, null):Array<PeerSlotInfo> = [];

    /** Latest validated remote vehicle states keyed by peerId. */
    public var remoteStates(default, null):Map<String, NetCarState> = new Map();

    /** Starting spawn slot assigned for this instance on match start. */
    public var localSpawnSlot(default, null):Null<SpawnSlot> = null;

    /** Human-readable status banner for Lobby HUD. */
    public var statusMessage:String = "Host a room to invite friends, or open an invite link.";

    /** Most recent validation/connection rejection reason if any. */
    public var lastError:String = "";

    /** Outgoing client packet sequence counter. */
    public var clientInputSeq:Int = 0;

    public var onLobbyChanged:Void->Void;
    public var onMatchStart:MapMode->SpawnSlot->Array<PeerSlotInfo>->Void;
    public var onJoinRejected:String->Void;
    public var onHostDisconnected:Void->Void;
    public var onReturnToLobby:Void->Void;

    private var syncAccum:Float = 0.0;
    private var localWheelSpinAngle:Float = 0.0;
    private var peerLastPacketTime:Map<String, Float> = new Map();
    private var elapsedMatchTime:Float = 0.0;
    private var pendingJoinRoomId:String = "";
    private var joinRetryAccum:Float = 0.0;
    private var joinElapsed:Float = 0.0;
    private var lastFrameUpdateMs:Float = 0.0;
    private var lastHostState:Null<NetCarState> = null;
    private var bgTimerId:Dynamic = null;

    public function new(transport:ISocketTransport) {
        this.transport = transport;
        bindTransportEvents();
        #if js
        var hasBrowserDoc:Bool = js.Syntax.code("typeof window !== 'undefined' && typeof document !== 'undefined' && typeof window.setInterval === 'function'");
        if (hasBrowserDoc) {
            bgTimerId = js.Browser.window.setInterval(function() {
                var hidden:Bool = js.Syntax.code("Boolean(document.hidden)");
                var nowMs:Float = Date.now().getTime();
                if (hidden || (lastFrameUpdateMs > 0.0 && (nowMs - lastFrameUpdateMs) > 350.0)) {
                    update(0.4, true);
                }
            }, 400);
        }
        #end
    }

    private function sendJoinRequestToHost():Void {
        transport.sendToHost({
            type: NetworkProtocol.MSG_JOIN_REQUEST,
            version: Version.NUMBER,
            name: localCallsign
        });
    }

    private function resetJoinTimers():Void {
        pendingJoinRoomId = "";
        joinRetryAccum = 0.0;
        joinElapsed = 0.0;
    }

    private function bindTransportEvents():Void {
        transport.onError = function(err:String) {
            lastError = err;
            statusMessage = err;
            resetJoinTimers();
            if (status == Connecting) {
                status = Disconnected;
                role = None;
                roomId = "";
            }
            emitLobbyChanged();
        };

        transport.onRoomHosted = function(rid:String, cid:String) {
            resetJoinTimers();
            role = Host;
            status = WaitingInLobby;
            roomId = rid;
            localPeerId = cid;
            lastError = "";
            peers = [{
                peerId: cid,
                name: sanitizeCallsign(localCallsign, 0, true),
                slotIndex: 0,
                colorHex: NetworkProtocol.getPaletteColor(0),
                isHost: true,
                ready: true
            }];
            remoteStates.clear();
            statusMessage = "Hosting room " + rid + " (Host validates all peers & physics).";
            emitLobbyChanged();
        };

        transport.onRoomJoined = function(rid:String, cid:String) {
            role = Client;
            status = Connecting;
            roomId = rid;
            localPeerId = cid;
            joinRetryAccum = 0.0;
            lastError = "";
            statusMessage = "Connected to relay. Waiting for Host validation...";
            emitLobbyChanged();

            sendJoinRequestToHost();
        };

        transport.onPeerSocketConnected = function(_peerId:String) {
            // Host waits for peer's MSG_JOIN_REQUEST to validate version, capacity, and callsign.
        };

        transport.onPeerSocketDisconnected = function(peerId:String) {
            if (role != Host) return;
            var removed = removePeerById(peerId);
            remoteStates.remove(peerId);
            peerLastPacketTime.remove(peerId);
            if (removed) {
                statusMessage = "Driver left room (" + peers.length + "/" + NetworkProtocol.MAX_PLAYERS + ").";
                if (status == WaitingInLobby) {
                    broadcastLobbyState();
                }
                emitLobbyChanged();
            }
        };

        transport.onRelayedFromPeer = function(fromId:String, payload:Dynamic) {
            if (role != Host || payload == null) return;
            var msgType:String = Std.string(payload.type);
            if (msgType == NetworkProtocol.MSG_JOIN_REQUEST) {
                handlePeerJoinRequest(fromId, payload);
            } else if (msgType == NetworkProtocol.MSG_CLIENT_STATE) {
                var prevTime = peerLastPacketTime.exists(fromId) ? peerLastPacketTime.get(fromId) : elapsedMatchTime;
                var dtWindow = Math.max(0.016, elapsedMatchTime - prevTime);
                if (validateClientPacket(fromId, payload, activeGroundProvider, dtWindow) != null) {
                    peerLastPacketTime.set(fromId, elapsedMatchTime);
                    #if js
                    if (status == InMatch && lastFrameUpdateMs > 0.0) {
                        var nowMs:Float = Date.now().getTime();
                        if ((nowMs - lastFrameUpdateMs) > 65.0) {
                            elapsedMatchTime += 0.04;
                            broadcastHostWorldSnapshot();
                        }
                    }
                    #end
                }
            }
        };

        transport.onRelayedFromHost = function(payload:Dynamic) {
            if (role != Client || payload == null) return;
            handleHostMessage(payload);
        };

        transport.onHostDisconnected = function() {
            if (role == Client) {
                resetJoinTimers();
                var wasMatch = (status == InMatch);
                role = None;
                status = Disconnected;
                roomId = "";
                peers = [];
                remoteStates.clear();
                lastError = "Host closed the room.";
                statusMessage = "Host disconnected.";
                if (onHostDisconnected != null) onHostDisconnected();
                emitLobbyChanged();
                if (wasMatch && onReturnToLobby != null) onReturnToLobby();
            }
        };
    }

    /** Optional ground reference registered by WorldManager while a match is running for Host boundary validation. */
    public var activeGroundProvider:Null<IGroundProvider> = null;

    /**
     * Advances Client join-handshake retry and timeout tracking.
     *
     * @param dt Elapsed time in seconds.
     * @param isBackgroundTick True when triggered by the background visibility timer rather than `Main.update`.
     */
    public function update(dt:Float, isBackgroundTick:Bool = false):Void {
        if (!isBackgroundTick) {
            lastFrameUpdateMs = Date.now().getTime();
        }
        if (dt <= 0.0) return;

        if (role == Client && status == Connecting) {
            joinElapsed += dt;
            joinRetryAccum += dt;
            if (joinElapsed >= JOIN_TIMEOUT_SECONDS) {
                var timedOutRoom = pendingJoinRoomId != "" ? pendingJoinRoomId : roomId;
                resetJoinTimers();
                transport.leaveRoom();
                role = None;
                status = Disconnected;
                roomId = "";
                peers = [];
                lastError = 'Room "' + timedOutRoom + '" did not respond. Verify the Invite Code and that the Host is in the lobby.';
                statusMessage = lastError;
                emitLobbyChanged();
            } else if (joinRetryAccum >= JOIN_RETRY_INTERVAL) {
                joinRetryAccum = 0.0;
                if (roomId != "") {
                    sendJoinRequestToHost();
                }
            }
        }
    }

    /**
     * Starts hosting a new multiplayer room via the stateless relay server.
     */
    public function hostRoom(?customRoomId:String, ?callsign:String):Void {
        if (callsign != null && StringTools.trim(callsign) != "") {
            localCallsign = callsign;
        }
        resetJoinTimers();
        lastError = "";
        role = Host;
        status = Connecting;
        peers = [];
        remoteStates.clear();
        statusMessage = "Opening relay room...";
        emitLobbyChanged();
        transport.hostRoom(customRoomId);
    }

    /**
     * Joins an existing Host room using a room code / invite link parameter.
     */
    public function joinRoom(targetRoomId:String, ?callsign:String):Void {
        var cleanRoom = extractRoomCode(targetRoomId);
        if (cleanRoom == "") {
            lastError = "Enter or open a valid Room Code.";
            statusMessage = lastError;
            emitLobbyChanged();
            return;
        }
        if (callsign != null && StringTools.trim(callsign) != "") {
            localCallsign = callsign;
        }
        lastError = "";
        role = Client;
        status = Connecting;
        roomId = "";
        pendingJoinRoomId = cleanRoom;
        joinRetryAccum = 0.0;
        joinElapsed = 0.0;
        peers = [];
        remoteStates.clear();
        statusMessage = "Joining room " + cleanRoom + "...";
        emitLobbyChanged();
        transport.joinRoom(cleanRoom);
    }

    /**
     * Host-only validation of an incoming peer join request.
     * Enforces lobby phase, room player cap, exact game version match, slot allocation, and unique callsigns.
     */
    public function handlePeerJoinRequest(peerId:String, payload:Dynamic):Bool {
        if (role != Host) return false;

        if (status != WaitingInLobby) {
            rejectPeer(peerId, "Match already in progress.");
            return false;
        }

        var clientVer = (payload != null && payload.version != null) ? Std.string(payload.version) : "unknown";
        if (clientVer != Version.NUMBER) {
            rejectPeer(peerId, "Version mismatch: Host is v" + Version.NUMBER + ", Client is v" + clientVer + ".");
            return false;
        }

        for (existing in peers) {
            if (existing.peerId == peerId) {
                transport.sendToPeer(peerId, {
                    type: NetworkProtocol.MSG_JOIN_ACCEPTED,
                    roomId: roomId,
                    peerId: peerId,
                    mapId: NetworkProtocol.mapModeToId(selectedMap),
                    peers: peers
                });
                return true;
            }
        }

        if (peers.length >= NetworkProtocol.MAX_PLAYERS) {
            rejectPeer(peerId, "Room is full (" + NetworkProtocol.MAX_PLAYERS + "/" + NetworkProtocol.MAX_PLAYERS + ").");
            return false;
        }

        var slotIndex = allocateLowestSlotIndex();
        var rawName = (payload != null && payload.name != null) ? Std.string(payload.name) : "";
        var cleanName = ensureUniqueCallsign(sanitizeCallsign(rawName, slotIndex, false));
        var peerInfo:PeerSlotInfo = {
            peerId: peerId,
            name: cleanName,
            slotIndex: slotIndex,
            colorHex: NetworkProtocol.getPaletteColor(slotIndex),
            isHost: false,
            ready: true
        };
        peers.push(peerInfo);

        transport.sendToPeer(peerId, {
            type: NetworkProtocol.MSG_JOIN_ACCEPTED,
            roomId: roomId,
            peerId: peerId,
            mapId: NetworkProtocol.mapModeToId(selectedMap),
            peers: peers
        });
        broadcastLobbyState();
        statusMessage = cleanName + " joined (" + peers.length + "/" + NetworkProtocol.MAX_PLAYERS + ").";
        emitLobbyChanged();
        return true;
    }

    private function rejectPeer(peerId:String, reason:String):Void {
        transport.sendToPeer(peerId, {
            type: NetworkProtocol.MSG_JOIN_REJECTED,
            reason: reason
        });
    }

    /**
     * Selects the active match map (`Circuit` or `Sandbox`). Ignored for Clients when Host owns the lobby.
     */
    public function setSelectedMap(mode:MapMode):Void {
        if (role == Client) return;
        selectedMap = mode;
        if (role == Host && status == WaitingInLobby) {
            broadcastLobbyState();
        }
        emitLobbyChanged();
    }

    /**
     * Launches the match for Host and all joined peers with staggered starting grid slots.
     */
    public function startMatch():Bool {
        if (role != Host || status != WaitingInLobby) return false;

        status = InMatch;
        syncAccum = 0.0;
        elapsedMatchTime = 0.0;
        remoteStates.clear();
        peerLastPacketTime.clear();

        var spawns = computeGridSpawns(selectedMap, peers);
        var hostSpawn = spawns[0];
        for (sp in spawns) {
            if (sp.peerId == localPeerId) {
                hostSpawn = sp;
            }
        }
        localSpawnSlot = hostSpawn;
        var hostPeer = findPeer(localPeerId);
        lastHostState = {
            peerId: localPeerId,
            name: hostPeer != null ? hostPeer.name : sanitizeCallsign(localCallsign, 0, true),
            slotIndex: 0,
            colorHex: hostPeer != null ? hostPeer.colorHex : NetworkProtocol.getPaletteColor(0),
            x: hostSpawn.x,
            y: hostSpawn.y,
            z: hostSpawn.z,
            yaw: hostSpawn.yaw,
            pitch: 0.0,
            roll: 0.0,
            forwardSpeed: 0.0,
            lateralVelocity: 0.0,
            steerAngle: 0.0,
            wheelSpinAngle: 0.0,
            boosting: false
        };
        initRemoteStatesFromSpawns(spawns);

        transport.broadcastToPeers({
            type: NetworkProtocol.MSG_START_MATCH,
            roomId: roomId,
            mapId: NetworkProtocol.mapModeToId(selectedMap),
            spawns: spawns,
            peers: peers
        });

        emitLobbyChanged();
        if (onMatchStart != null) onMatchStart(selectedMap, hostSpawn, peers);
        return true;
    }

    /**
     * Returns all peers from active race back to the Host's lobby.
     */
    public function returnToLobby():Void {
        remoteStates.clear();
        peerLastPacketTime.clear();
        if (role == Host) {
            status = WaitingInLobby;
            transport.broadcastToPeers({
                type: NetworkProtocol.MSG_HOST_RETURN_TO_LOBBY
            });
            broadcastLobbyState();
            statusMessage = "Returned to room " + roomId + " lobby.";
        }
        emitLobbyChanged();
        if (onReturnToLobby != null) onReturnToLobby();
    }

    /**
     * Leaves the current room cleanly and resets network role to None.
     */
    public function leaveRoom():Void {
        resetJoinTimers();
        transport.leaveRoom();
        role = None;
        status = Disconnected;
        roomId = "";
        localPeerId = "";
        peers = [];
        remoteStates.clear();
        peerLastPacketTime.clear();
        localSpawnSlot = null;
        lastHostState = null;
        lastError = "";
        statusMessage = "Disconnected from multiplayer lobby.";
        emitLobbyChanged();
    }

    private function broadcastHostWorldSnapshot():Void {
        var snapshot:Array<NetCarState> = [];
        if (lastHostState != null) {
            snapshot.push(lastHostState);
        }
        for (p in peers) {
            if (p.peerId == localPeerId) continue;
            var st = remoteStates.get(p.peerId);
            if (st != null) snapshot.push(st);
        }
        transport.broadcastToPeers({
            type: NetworkProtocol.MSG_WORLD_SNAPSHOT,
            states: snapshot
        });
    }

    /**
     * Called once per simulation frame during an active multiplayer match.
     * Clients stream state packets to the Host; Host validates packets and broadcasts authoritative snapshots.
     */
    public function updateInMatch(dt:Float, localCar:CarPhysics, input:InputController, ground:IGroundProvider):Void {
        if (status != InMatch || localCar == null) return;

        activeGroundProvider = ground;
        elapsedMatchTime += dt;
        localWheelSpinAngle += (localCar.forwardSpeed * dt) / 0.36;

        syncAccum += dt;
        if (syncAccum < SYNC_INTERVAL) return;
        syncAccum = 0.0;

        var steerVal = (input != null) ? input.steer : 0.0;

        if (role == Host) {
            var hostPeer = findPeer(localPeerId);
            var hostColor = hostPeer != null ? hostPeer.colorHex : NetworkProtocol.getPaletteColor(0);
            var hostName = hostPeer != null ? hostPeer.name : sanitizeCallsign(localCallsign, 0, true);

            lastHostState = {
                peerId: localPeerId,
                name: hostName,
                slotIndex: 0,
                colorHex: hostColor,
                x: localCar.pos.x,
                y: localCar.pos.y,
                z: localCar.pos.z,
                yaw: localCar.yaw + localCar.driftAngle,
                pitch: localCar.pitch,
                roll: localCar.roll,
                forwardSpeed: localCar.forwardSpeed,
                lateralVelocity: localCar.lateralVelocity,
                steerAngle: -steerVal * 0.55,
                wheelSpinAngle: localWheelSpinAngle,
                boosting: localCar.isBoosting
            };

            broadcastHostWorldSnapshot();
        } else if (role == Client) {
            clientInputSeq++;
            var pkt:ClientInputPacket = {
                type: NetworkProtocol.MSG_CLIENT_STATE,
                peerId: localPeerId,
                seq: clientInputSeq,
                throttle: input != null ? input.throttle : 0.0,
                brake: input != null ? input.brake : 0.0,
                steer: steerVal,
                handbrake: input != null ? input.handbrake : false,
                boosting: localCar.isBoosting,
                x: localCar.pos.x,
                y: localCar.pos.y,
                z: localCar.pos.z,
                yaw: localCar.yaw + localCar.driftAngle,
                pitch: localCar.pitch,
                roll: localCar.roll,
                forwardSpeed: localCar.forwardSpeed,
                lateralVelocity: localCar.lateralVelocity,
                wheelSpinAngle: localWheelSpinAngle
            };
            transport.sendToHost(pkt);
        }
    }

    /**
     * Host-authoritative validation & sanitization of incoming Client state packets.
     * Rejects corrupted/NaN values, enforces physical speed bounds, prevents teleportation hacks,
     * and enforces active track/sandbox perimeter walls.
     */
    public function validateClientPacket(peerId:String, pkt:Dynamic, ground:Null<IGroundProvider>, dtWindow:Float = 0.05):Null<NetCarState> {
        if (role != Host || status != InMatch || pkt == null) return null;

        var peer = findPeer(peerId);
        if (peer == null || peer.isHost) return null;

        var px = readFinite(pkt.x);
        var py = readFinite(pkt.y);
        var pz = readFinite(pkt.z);
        var pyaw = readFinite(pkt.yaw);
        var ppitch = readFinite(pkt.pitch);
        var proll = readFinite(pkt.roll);
        var spd = readFinite(pkt.forwardSpeed);
        var lat = readFinite(pkt.lateralVelocity);
        var steer = readFinite(pkt.steer);
        var wheelSpin = readFinite(pkt.wheelSpinAngle);

        if (px == null || py == null || pz == null || pyaw == null || ppitch == null ||
            proll == null || spd == null || lat == null || steer == null || wheelSpin == null) {
            return null;
        }

        // Physical bounds clamping
        var clampedSteer = clamp(steer, -1.0, 1.0);
        var clampedSpeed = clamp(spd, MAX_VALID_REVERSE_SPEED, MAX_VALID_FORWARD_SPEED);
        var clampedLat = clamp(lat, -MAX_VALID_LATERAL_SPEED, MAX_VALID_LATERAL_SPEED);
        var clampedPitch = clamp(ppitch, -0.85, 0.85);
        var clampedRoll = clamp(proll, -0.85, 0.85);

        // Anti-teleport distance cap relative to previous validated state
        var prev = remoteStates.get(peerId);
        var finalX:Float = px;
        var finalY:Float = py;
        if (prev != null) {
            var dx = finalX - prev.x;
            var dy = finalY - prev.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            var safeWindow = Math.max(dtWindow, 0.20);
            var maxAllowedStep = Math.max(15.0, 100.0 * safeWindow);
            if (dist > maxAllowedStep * 3.0) {
                // Extreme warp attempt -> revert cleanly to previous valid coordinate
                finalX = prev.x;
                finalY = prev.y;
                pz = prev.z;
            } else if (dist > maxAllowedStep && dist > 0.0001) {
                var ratio = maxAllowedStep / dist;
                finalX = prev.x + dx * ratio;
                finalY = prev.y + dy * ratio;
            }
        }

        // Active map boundary & ground floor validation
        var finalZ:Float = pz;
        if (ground != null) {
            var checkPos = new Vector(finalX, finalY, finalZ);
            ground.enforceBoundaries(checkPos, clampedSpeed, clampedLat);
            finalX = checkPos.x;
            finalY = checkPos.y;
            var groundZ = ground.getGroundElevation(finalX, finalY);
            if (finalZ < groundZ - 0.35) finalZ = groundZ;
            if (finalZ > groundZ + 35.0) finalZ = groundZ + 35.0;
        }

        var validated:NetCarState = {
            peerId: peerId,
            name: peer.name,
            slotIndex: peer.slotIndex,
            colorHex: peer.colorHex,
            x: finalX,
            y: finalY,
            z: finalZ,
            yaw: pyaw,
            pitch: clampedPitch,
            roll: clampedRoll,
            forwardSpeed: clampedSpeed,
            lateralVelocity: clampedLat,
            steerAngle: -clampedSteer * 0.55,
            wheelSpinAngle: wheelSpin,
            boosting: pkt.boosting == true
        };

        remoteStates.set(peerId, validated);
        return validated;
    }

    /**
     * Computes staggered starting grid spawn slots for all connected drivers on the chosen map.
     */
    public function computeGridSpawns(mode:MapMode, roster:Array<PeerSlotInfo>):Array<SpawnSlot> {
        var sorted = roster.copy();
        sorted.sort(function(a, b) return a.slotIndex - b.slotIndex);

        var baseZ = (mode == Circuit) ? Track.ROAD_LIFT : 0.05;
        var colOffset = (mode == Circuit) ? 2.4 : 3.2;
        var rowSpacing = 7.0;

        var result:Array<SpawnSlot> = [];
        for (i in 0...sorted.length) {
            var p = sorted[i];
            var col = (i % 2 == 0) ? -colOffset : colOffset;
            var row = Math.floor(i / 2);
            // Slot 0 leads from x = -colOffset, y = 0; Slot 1 starts at +colOffset, y = -3.0; subsequent rows staggered behind
            var x = (sorted.length == 1) ? 0.0 : col;
            var y = (i == 0) ? 0.0 : -(row * rowSpacing + ((i % 2 == 1) ? 3.0 : 0.0));
            result.push({
                peerId: p.peerId,
                x: x,
                y: y,
                z: baseZ,
                yaw: 0.0
            });
        }
        return result;
    }

    private function handleHostMessage(payload:Dynamic):Void {
        var msgType:String = Std.string(payload.type);
        switch (msgType) {
            case NetworkProtocol.MSG_JOIN_ACCEPTED:
                resetJoinTimers();
                status = WaitingInLobby;
                lastError = "";
                if (payload.mapId != null) selectedMap = NetworkProtocol.mapIdToMode(Std.string(payload.mapId));
                applyPeerRoster(payload.peers);
                statusMessage = "Joined room " + roomId + " (" + NetworkProtocol.getMapDisplayName(selectedMap) + ").";
                emitLobbyChanged();

            case NetworkProtocol.MSG_JOIN_REJECTED:
                resetJoinTimers();
                var reason = payload.reason != null ? Std.string(payload.reason) : "Join rejected by Host.";
                lastError = reason;
                statusMessage = reason;
                role = None;
                status = Disconnected;
                roomId = "";
                peers = [];
                transport.leaveRoom();
                if (onJoinRejected != null) onJoinRejected(reason);
                emitLobbyChanged();

            case NetworkProtocol.MSG_LOBBY_STATE:
                if (payload.mapId != null) selectedMap = NetworkProtocol.mapIdToMode(Std.string(payload.mapId));
                applyPeerRoster(payload.peers);
                if (status != InMatch) status = WaitingInLobby;
                statusMessage = "Host selected " + NetworkProtocol.getMapDisplayName(selectedMap) + " (" + peers.length + " drivers).";
                emitLobbyChanged();

            case NetworkProtocol.MSG_START_MATCH:
                if (payload.mapId != null) selectedMap = NetworkProtocol.mapIdToMode(Std.string(payload.mapId));
                if (payload.peers != null) applyPeerRoster(payload.peers);
                status = InMatch;
                syncAccum = 0.0;
                elapsedMatchTime = 0.0;
                remoteStates.clear();

                var spawns:Array<SpawnSlot> = cast payload.spawns;
                var mySpawn:SpawnSlot = { peerId: localPeerId, x: 0.0, y: 0.0, z: (selectedMap == Circuit ? Track.ROAD_LIFT : 0.05), yaw: 0.0 };
                if (spawns != null) {
                    for (sp in spawns) {
                        if (sp.peerId == localPeerId) {
                            mySpawn = sp;
                        }
                    }
                    initRemoteStatesFromSpawns(spawns);
                }
                localSpawnSlot = mySpawn;
                emitLobbyChanged();
                if (onMatchStart != null) onMatchStart(selectedMap, mySpawn, peers);

            case NetworkProtocol.MSG_WORLD_SNAPSHOT:
                if (status != InMatch || payload.states == null) return;
                var list:Array<NetCarState> = cast payload.states;
                var activeIds = new Map<String, Bool>();
                for (st in list) {
                    if (st == null || st.peerId == localPeerId) continue;
                    activeIds.set(st.peerId, true);
                    remoteStates.set(st.peerId, st);
                }
                // Drop states of disconnected peers
                for (existingId in remoteStates.keys()) {
                    if (!activeIds.exists(existingId)) {
                        remoteStates.remove(existingId);
                    }
                }

            case NetworkProtocol.MSG_HOST_RETURN_TO_LOBBY:
                status = WaitingInLobby;
                remoteStates.clear();
                statusMessage = "Host returned lobby to staging room.";
                emitLobbyChanged();
                if (onReturnToLobby != null) onReturnToLobby();

            default:
        }
    }

    private function initRemoteStatesFromSpawns(spawns:Array<SpawnSlot>):Void {
        for (sp in spawns) {
            if (sp.peerId == localPeerId) continue;
            var p = findPeer(sp.peerId);
            remoteStates.set(sp.peerId, {
                peerId: sp.peerId,
                name: p != null ? p.name : "DRIVER",
                slotIndex: p != null ? p.slotIndex : 1,
                colorHex: p != null ? p.colorHex : NetworkProtocol.getPaletteColor(1),
                x: sp.x,
                y: sp.y,
                z: sp.z,
                yaw: sp.yaw,
                pitch: 0.0,
                roll: 0.0,
                forwardSpeed: 0.0,
                lateralVelocity: 0.0,
                steerAngle: 0.0,
                wheelSpinAngle: 0.0,
                boosting: false
            });
        }
    }

    private function broadcastLobbyState():Void {
        transport.broadcastToPeers({
            type: NetworkProtocol.MSG_LOBBY_STATE,
            roomId: roomId,
            mapId: NetworkProtocol.mapModeToId(selectedMap),
            status: (status == InMatch) ? "in_match" : "lobby",
            hostVersion: Version.NUMBER,
            peers: peers
        });
    }

    private function applyPeerRoster(rawPeers:Dynamic):Void {
        if (rawPeers == null) return;
        var arr:Array<PeerSlotInfo> = cast rawPeers;
        var next:Array<PeerSlotInfo> = [];
        for (p in arr) {
            next.push({
                peerId: Std.string(p.peerId),
                name: Std.string(p.name),
                slotIndex: Std.int(p.slotIndex),
                colorHex: Std.int(p.colorHex),
                isHost: p.isHost == true,
                ready: p.ready == true
            });
        }
        peers = next;
    }

    private function findPeer(peerId:String):Null<PeerSlotInfo> {
        for (p in peers) {
            if (p.peerId == peerId) return p;
        }
        return null;
    }

    private function removePeerById(peerId:String):Bool {
        for (i in 0...peers.length) {
            if (peers[i].peerId == peerId) {
                peers.splice(i, 1);
                return true;
            }
        }
        return false;
    }

    private function allocateLowestSlotIndex():Int {
        for (slot in 0...NetworkProtocol.MAX_PLAYERS) {
            var taken = false;
            for (p in peers) {
                if (p.slotIndex == slot) {
                    taken = true;
                    break;
                }
            }
            if (!taken) return slot;
        }
        return peers.length;
    }

    private function sanitizeCallsign(raw:String, slotIndex:Int, isHostUser:Bool):String {
        var cleaned = raw != null ? StringTools.trim(raw) : "";
        var filtered = new StringBuf();
        for (i in 0...cleaned.length) {
            var ch = cleaned.charAt(i);
            var code = cleaned.charCodeAt(i);
            var ok = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch == " " || ch == "-" || ch == "_";
            if (ok) filtered.add(ch);
            if (filtered.length >= 14) break;
        }
        var out = StringTools.trim(filtered.toString()).toUpperCase();
        if (out == "") {
            out = isHostUser ? "HOST" : ("DRIVER " + (slotIndex + 1));
        }
        return out;
    }

    private function ensureUniqueCallsign(candidate:String):String {
        var suffix = 2;
        var cur = candidate;
        while (true) {
            var dup = false;
            for (p in peers) {
                if (p.name == cur) {
                    dup = true;
                    break;
                }
            }
            if (!dup) return cur;
            cur = candidate + " " + suffix;
            suffix++;
        }
    }

    private function readFinite(v:Dynamic):Null<Float> {
        if (v == null) return null;
        var f:Float = Std.parseFloat(Std.string(v));
        if (!Math.isFinite(f) || Math.isNaN(f)) return null;
        return f;
    }

    private inline function clamp(v:Float, lo:Float, hi:Float):Float {
        return (v < lo) ? lo : ((v > hi) ? hi : v);
    }

    private function emitLobbyChanged():Void {
        if (onLobbyChanged != null) onLobbyChanged();
    }

    /**
     * Generates a shareable invite URL containing `?room=<ROOM_ID>`.
     */
    public function getInviteLink():String {
        return buildInviteLink(roomId);
    }

    /**
     * Builds a browser invite URL from a room code using current origin/pathname when running on web.
     */
    public static function buildInviteLink(targetRoomId:String):String {
        if (targetRoomId == null || StringTools.trim(targetRoomId) == "") return "";
        var code = StringTools.trim(targetRoomId).toUpperCase();
        #if js
        var hasValidLoc:Bool = js.Syntax.code("typeof window !== 'undefined' && window.location && typeof window.location.origin === 'string' && window.location.origin !== 'null' && typeof window.location.pathname === 'string'");
        if (hasValidLoc) {
            var origin:String = js.Syntax.code("window.location.origin");
            var pathname:String = js.Syntax.code("window.location.pathname");
            return origin + pathname + "?room=" + code;
        }
        #end
        return "?room=" + code;
    }

    /**
     * Reads `?room=<ROOM_ID>` from the active browser URL if present.
     */
    public static function detectInviteRoomFromUrl():Null<String> {
        #if js
        var hasSearch:Bool = js.Syntax.code("typeof window !== 'undefined' && window.location && typeof window.location.search === 'string'");
        if (hasSearch) {
            var search:String = js.Syntax.code("window.location.search");
            if (search != null && search.length > 1) {
                var query = search.substr(1);
                for (pair in query.split("&")) {
                    var eq = pair.indexOf("=");
                    if (eq > 0) {
                        var k = StringTools.urlDecode(pair.substr(0, eq));
                        if (k == "room") {
                            var val = StringTools.trim(StringTools.urlDecode(pair.substr(eq + 1))).toUpperCase();
                            if (val != "") return val;
                        }
                    }
                }
            }
        }
        #end
        return null;
    }

    /**
     * Extracts a normalized uppercase Room Code from either a raw code string (e.g. "x5vc8d")
     * or a full Invite Link URL (e.g. "http://host/?room=X5VC8D").
     */
    public static function extractRoomCode(raw:String):String {
        if (raw == null) return "";
        var trimmed = StringTools.trim(raw);
        var lower = trimmed.toLowerCase();
        var idx = lower.indexOf("room=");
        if (idx >= 0) {
            var after = trimmed.substr(idx + 5);
            var amp = after.indexOf("&");
            if (amp >= 0) after = after.substr(0, amp);
            var hash = after.indexOf("#");
            if (hash >= 0) after = after.substr(0, hash);
            trimmed = after;
        }
        var clean = new StringBuf();
        for (i in 0...trimmed.length) {
            var c = trimmed.charCodeAt(i);
            var isNum = (c >= 48 && c <= 57);
            var isUpper = (c >= 65 && c <= 90);
            var isLower = (c >= 97 && c <= 122);
            var isExtra = (c == 95 || c == 45);
            if (isNum || isUpper || isLower || isExtra) {
                clean.addChar(c);
            }
        }
        var res = clean.toString().toUpperCase();
        if (res.length > 12) res = res.substr(0, 12);
        return res;
    }

    /**
     * Copies the invite link to the system clipboard when available in the browser.
     */
    public static function copyInviteLinkToClipboard(link:String):Void {
        #if js
        try {
            var hasClip:Bool = js.Syntax.code("typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText");
            if (hasClip && link != null && link != "") {
                js.Syntax.code("navigator.clipboard.writeText({0})", link);
            }
        } catch (_e:Dynamic) {}
        #end
    }
}
