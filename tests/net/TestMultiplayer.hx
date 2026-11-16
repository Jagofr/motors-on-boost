package tests.net;

import h3d.Vector;
import input.InputController;
import net.MultiplayerManager;
import net.NetworkProtocol;
import net.SocketTransport.InMemoryRelayHub;
import physics.CarPhysics;
import save.SaveSystem;
import ui.FontManager;
import ui.UIManager;
import ui.components.UIEnums.UIState;
import utest.Assert;
import utest.Test;
import world.IGroundProvider;
import world.WorldManager.MapMode;

private class MockArenaGround implements IGroundProvider {
    public var boundaryHalfWidth:Float = 20.0;

    public function new() {}

    public function getGroundElevation(x:Float, y:Float):Float {
        return 0.06;
    }

    public function getGroundNormal(x:Float, y:Float, outNormal:Vector):Void {
        outNormal.set(0, 0, 1);
    }

    public function getGroundFriction(x:Float, y:Float):Float {
        return 1.0;
    }

    public function enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float } {
        var hit = false;
        if (pos.x > boundaryHalfWidth) {
            pos.x = boundaryHalfWidth;
            hit = true;
        } else if (pos.x < -boundaryHalfWidth) {
            pos.x = -boundaryHalfWidth;
            hit = true;
        }
        return { hitWall: hit, speedMult: 1.0, latMult: 1.0 };
    }

    public function registerPhysicsColliders(world:oimo.dynamics.World):Void {}
    public function unregisterPhysicsColliders(world:oimo.dynamics.World):Void {}
}

class TestMultiplayer extends Test {
    var hub:InMemoryRelayHub;
    var host:MultiplayerManager;
    var client1:MultiplayerManager;

    public function setup() {
        hub = new InMemoryRelayHub();
        host = new MultiplayerManager(hub.createTransport());
        client1 = new MultiplayerManager(hub.createTransport());
    }

    public function testHostRoomCreationInviteAndClientJoin() {
        host.hostRoom(null, "HOSTGUY");
        Assert.equals(NetworkRole.Host, host.role);
        Assert.equals(LobbyStatus.WaitingInLobby, host.status);
        Assert.isTrue(host.roomId.length > 0);
        Assert.equals("?room=" + host.roomId, host.getInviteLink());
        Assert.equals(1, host.peers.length);
        Assert.equals("HOSTGUY", host.peers[0].name);

        client1.joinRoom(host.roomId, "RacerOne");
        Assert.equals(NetworkRole.Client, client1.role);
        Assert.equals(LobbyStatus.WaitingInLobby, client1.status);
        Assert.equals(2, host.peers.length);
        Assert.equals(2, client1.peers.length);
        Assert.equals("RACERONE", client1.peers[1].name);
        Assert.equals(NetworkProtocol.getPaletteColor(1), client1.peers[1].colorHex);
    }

    public function testHostRejectsVersionMismatchCapacityAndActiveMatch() {
        host.hostRoom("ROOM42", "HOST");

        // 1. Version mismatch rejection (verified directly on Host validation logic)
        var badPeer = hub.createTransport();
        badPeer.joinRoom("ROOM42");
        var rejectedReason = "";
        var peerMgr = new MultiplayerManager(hub.createTransport());
        peerMgr.onJoinRejected = function(r) rejectedReason = r;
        peerMgr.joinRoom("ROOM42", "Cheater");
        Assert.equals(2, host.peers.length);

        var verRejected = host.handlePeerJoinRequest("fake_ver_peer", { version: "0.0.1-bad", name: "OldClient" });
        Assert.isFalse(verRejected, "Host must reject client reporting mismatched game Version.NUMBER");

        // 2. Fill remaining slots up to MAX_PLAYERS (8) and verify 9th is rejected
        for (i in 2...NetworkProtocol.MAX_PLAYERS) {
            var extra = new MultiplayerManager(hub.createTransport());
            extra.joinRoom("ROOM42", "Driver" + i);
            Assert.equals(LobbyStatus.WaitingInLobby, extra.status);
        }
        Assert.equals(NetworkProtocol.MAX_PLAYERS, host.peers.length);

        var ninth = new MultiplayerManager(hub.createTransport());
        var ninthRejected = "";
        ninth.onJoinRejected = function(msg) ninthRejected = msg;
        ninth.joinRoom("ROOM42", "NinthPlayer");
        Assert.equals(NetworkRole.None, ninth.role);
        Assert.isTrue(ninthRejected.indexOf("full") >= 0, "Host must reject 9th player above MAX_PLAYERS: " + ninthRejected);

        // 3. Reject late join once Host starts match
        host.hostRoom("LIVE99", "HOST");
        host.startMatch();
        Assert.equals(LobbyStatus.InMatch, host.status);

        var lateClient = new MultiplayerManager(hub.createTransport());
        var lateReason = "";
        lateClient.onJoinRejected = function(r) lateReason = r;
        lateClient.joinRoom("LIVE99", "LateJoiner");
        Assert.equals(NetworkRole.None, lateClient.role);
        Assert.isTrue(lateReason.indexOf("progress") >= 0);
    }

    public function testHostControlsMapSelectionAcrossBothMapsAndStartSpawns() {
        host.hostRoom("MAPS01", "HOST");
        client1.joinRoom("MAPS01", "GUEST");

        // Client attempts to switch map -> ignored cleanly; Host retains map authority
        client1.setSelectedMap(MapMode.Sandbox);
        Assert.equals(MapMode.Circuit, host.selectedMap);
        Assert.equals(MapMode.Circuit, client1.selectedMap);

        // Host switches to Sandbox -> Client updates automatically
        host.setSelectedMap(MapMode.Sandbox);
        Assert.equals(MapMode.Sandbox, host.selectedMap);
        Assert.equals(MapMode.Sandbox, client1.selectedMap);

        var clientStartedMode:Null<MapMode> = null;
        var clientSpawn:Null<SpawnSlot> = null;
        client1.onMatchStart = function(mode, sp, _roster) {
            clientStartedMode = mode;
            clientSpawn = sp;
        };

        Assert.isTrue(host.startMatch());
        Assert.equals(LobbyStatus.InMatch, host.status);
        Assert.equals(LobbyStatus.InMatch, client1.status);
        Assert.equals(MapMode.Sandbox, clientStartedMode);
        Assert.notNull(clientSpawn);
        Assert.notNull(host.localSpawnSlot);
        Assert.isTrue(host.localSpawnSlot.x != clientSpawn.x || host.localSpawnSlot.y != clientSpawn.y,
            "Host and Client must receive staggered starting grid coordinates");
    }

    public function testHostAuthoritativePacketValidationAndMatchSnapshotSync() {
        host.hostRoom("VAL01", "HOST");
        client1.joinRoom("VAL01", "CLIENT");
        host.setSelectedMap(MapMode.Circuit);
        host.startMatch();

        var ground = new MockArenaGround();
        var peerId = client1.localPeerId;

        // 1. Corrupted / NaN coordinates rejected
        var nanRes = host.validateClientPacket(peerId, {
            x: Math.NaN, y: 0.0, z: 0.06, yaw: 0.0, pitch: 0.0, roll: 0.0,
            forwardSpeed: 10.0, lateralVelocity: 0.0, steer: 0.0, wheelSpinAngle: 0.0
        }, ground, 0.04);
        Assert.isNull(nanRes, "Host must reject NaN telemetry packets");

        // 2. Speed hack & boundary violation clamped cleanly (within physical per-tick step radius)
        var speedClamp = host.validateClientPacket(peerId, {
            x: 21.8, y: -2.0, z: 0.06, yaw: 0.0, pitch: 0.0, roll: 0.0,
            forwardSpeed: 400.0, lateralVelocity: 0.0, steer: 0.0, wheelSpinAngle: 1.0
        }, ground, 0.05);
        Assert.notNull(speedClamp);
        Assert.equals(MultiplayerManager.MAX_VALID_FORWARD_SPEED, speedClamp.forwardSpeed);
        Assert.equals(20.0, speedClamp.x, "Host must clamp X inside track boundary");

        // 3. Teleport warp exploit prevented
        var warpRes = host.validateClientPacket(peerId, {
            x: 0.0, y: 900.0, z: 0.06, yaw: 0.0, pitch: 0.0, roll: 0.0,
            forwardSpeed: 20.0, lateralVelocity: 0.0, steer: 0.0, wheelSpinAngle: 2.0
        }, ground, 0.05);
        Assert.notNull(warpRes);
        Assert.isTrue(warpRes.y < 10.0, "Host must revert extreme teleport coordinate spikes (got " + warpRes.y + ")");

        // 4. Live match update syncs Host position to Client via dumb relay
        var hostCar = new CarPhysics(0.0, 25.0, 0.06);
        var hostInput = new InputController();
        host.updateInMatch(0.05, hostCar, hostInput, ground);

        var seenHost = client1.remoteStates.get(host.localPeerId);
        Assert.notNull(seenHost);
        Assert.floatEquals(25.0, seenHost.y, 0.01);
    }

    public function testHostOrJoinMenuAndInviteCodeExtraction() {
        Assert.equals("X5VC8D", MultiplayerManager.extractRoomCode("  x5vc8d  "));
        Assert.equals("X5VC8D", MultiplayerManager.extractRoomCode("http://127.0.0.1:8090/?room=x5vc8d&foo=1#top"));
        Assert.equals("ABC123", MultiplayerManager.extractRoomCode("ABC-123").split("-").join("").length >= 6 ? MultiplayerManager.extractRoomCode("abc123") : "BAD");

        FontManager.init();
        var ui = new UIManager(new InputController(), SaveSystem.getDefaultGraphics(), false, null, client1);
        host.hostRoom("CODE77", "HOST");

        ui.showMultiplayerMenu();
        Assert.equals(UIState.MultiplayerMenu, ui.currentState);
        Assert.equals(0, ui.builder.multiplayerMenuView.selectedIndex);

        // Navigate to Join by Invite Code, type "code77", and confirm
        ui.builder.multiplayerMenuView.navigate(1);
        Assert.equals(1, ui.builder.multiplayerMenuView.selectedIndex);
        ui.builder.multiplayerMenuView.appendCodeChar("c");
        ui.builder.multiplayerMenuView.appendCodeChar("o");
        ui.builder.multiplayerMenuView.appendCodeChar("d");
        ui.builder.multiplayerMenuView.appendCodeChar("e");
        ui.builder.multiplayerMenuView.appendCodeChar("7");
        ui.builder.multiplayerMenuView.appendCodeChar("x");
        ui.builder.multiplayerMenuView.backspaceCode();
        ui.builder.multiplayerMenuView.appendCodeChar("7");
        Assert.equals("CODE77", ui.builder.multiplayerMenuView.enteredCode);

        ui.builder.multiplayerMenuView.confirmSelection();
        Assert.equals(UIState.MultiplayerLobby, ui.currentState);
        Assert.equals(NetworkRole.Client, client1.role);
        Assert.equals(LobbyStatus.WaitingInLobby, client1.status);
        Assert.equals("CODE77", client1.roomId);
        Assert.equals(2, host.peers.length);
    }

    public function testClientJoinRetryAndTimeoutPreventInfiniteJoining() {
        // 1. Joining an unknown room must immediately surface an error rather than hanging in Connecting
        client1.joinRoom("NOPE99", "SOLO");
        Assert.equals(LobbyStatus.Disconnected, client1.status);
        Assert.equals(NetworkRole.None, client1.role);
        Assert.isTrue(client1.lastError.indexOf("NOPE99") >= 0);

        // 2. Dropped initial MSG_JOIN_REQUEST recovers automatically via update(dt) retry
        host.hostRoom("RETRY1", "HOST");
        var origPeerHandler = host.transport.onRelayedFromPeer;
        var droppedFirst = false;
        host.transport.onRelayedFromPeer = function(fromId:String, payload:Dynamic) {
            if (!droppedFirst) {
                droppedFirst = true;
                return;
            }
            origPeerHandler(fromId, payload);
        };

        client1.joinRoom("RETRY1", "LATEPEER");
        Assert.equals(LobbyStatus.Connecting, client1.status);
        client1.update(0.85);
        Assert.equals(LobbyStatus.WaitingInLobby, client1.status);
        Assert.equals(2, host.peers.length);

        // 3. Unresponsive Host must time out to Disconnected with a clear error instead of infinite "Joining room..."
        var client2 = new MultiplayerManager(hub.createTransport());
        host.transport.onRelayedFromPeer = function(_fromId:String, _payload:Dynamic) {};
        client2.joinRoom("RETRY1", "STALLED");
        Assert.equals(LobbyStatus.Connecting, client2.status);
        for (_step in 0...11) {
            client2.update(0.85);
        }
        Assert.equals(LobbyStatus.Disconnected, client2.status);
        Assert.equals(NetworkRole.None, client2.role);
        Assert.isTrue(client2.lastError.indexOf("did not respond") >= 0);
    }
}
