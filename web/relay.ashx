<%@ WebHandler Language="C#" Class="MobSocketRelayHandler" %>

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.WebSockets;

/**
 * Zero-dependency IIS ASP.NET socket/HTTP multiplayer relay on `/relay.ashx`.
 * Strictly forwards connection lifecycle events and raw JSON envelopes between Host
 * and Client peers in a room; all game/physics/version validation remains on the Host client.
 */
public class MobSocketRelayHandler : IHttpHandler {
    private const string RoomAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private const int ClientStaleSeconds = 60;
    private const int MaxHttpOutbox = 160;

    private static readonly ConcurrentDictionary<string, RelayClient> Clients = new ConcurrentDictionary<string, RelayClient>();
    private static readonly ConcurrentDictionary<string, RelayRoom> Rooms = new ConcurrentDictionary<string, RelayRoom>(StringComparer.OrdinalIgnoreCase);
    private static readonly object RoomMgmtLock = new object();
    private static readonly object RngLock = new object();
    private static readonly Random Rng = new Random();
    private static int NextConnSeq = 0;

    private class RelayClient {
        public string Id;
        public string RoomId;
        public bool IsHost;
        public bool IsWebSocket;
        public volatile bool Closed;
        public DateTime LastSeenUtc;
        public AspNetWebSocketContext WsContext;
        public readonly object SyncLock = new object();
        public readonly List<Dictionary<string, object>> HttpOutbox = new List<Dictionary<string, object>>();
        public readonly Queue<string> WsOutbox = new Queue<string>();
        public readonly SemaphoreSlim WsSignal = new SemaphoreSlim(0);
    }

    private class RelayRoom {
        public string Id;
        public RelayClient Host;
        public readonly ConcurrentDictionary<string, RelayClient> Peers = new ConcurrentDictionary<string, RelayClient>();
    }

    public bool IsReusable {
        get { return true; }
    }

    public void ProcessRequest(HttpContext context) {
        context.Response.Cache.SetCacheability(HttpCacheability.NoCache);
        context.Response.Cache.SetNoStore();
        context.Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate";
        context.Response.Headers["Pragma"] = "no-cache";
        context.Response.Headers["Access-Control-Allow-Origin"] = "*";
        context.Response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
        context.Response.Headers["Access-Control-Allow-Headers"] = "Content-Type";

        if (string.Equals(context.Request.HttpMethod, "OPTIONS", StringComparison.OrdinalIgnoreCase)) {
            context.Response.StatusCode = 204;
            return;
        }

        if (context.IsWebSocketRequest) {
            try {
                context.AcceptWebSocketRequest(HandleWebSocketAsync);
                return;
            } catch {
                // Fall back to HTTP relay error/response if WebSocketModule cannot accept upgrade
            }
        }

        HandleHttpRelay(context);
    }

    private static JavaScriptSerializer CreateSerializer() {
        var ser = new JavaScriptSerializer();
        ser.MaxJsonLength = 8 * 1024 * 1024;
        return ser;
    }

    private void HandleHttpRelay(HttpContext context) {
        context.Response.ContentType = "application/json; charset=utf-8";
        var ser = CreateSerializer();

        SweepStaleClients();

        if (string.Equals(context.Request.HttpMethod, "GET", StringComparison.OrdinalIgnoreCase) &&
            context.Request.QueryString["ping"] == "1") {
            var pingRes = new Dictionary<string, object>();
            pingRes["ok"] = true;
            pingRes["relay"] = "ashx";
            pingRes["rooms"] = Rooms.Count;
            context.Response.Write(ser.Serialize(pingRes));
            return;
        }

        string bodyText = "";
        if (context.Request.InputStream != null && context.Request.InputStream.CanRead) {
            using (var reader = new StreamReader(context.Request.InputStream, Encoding.UTF8)) {
                bodyText = reader.ReadToEnd();
            }
        }

        Dictionary<string, object> reqObj = null;
        if (!string.IsNullOrWhiteSpace(bodyText)) {
            try {
                reqObj = AsDict(ser.DeserializeObject(bodyText));
            } catch {
                reqObj = null;
            }
        }

        string connId = reqObj != null ? GetStr(reqObj, "connId") : GetStrQuery(context, "connId");
        RelayClient client = null;
        if (!string.IsNullOrEmpty(connId)) {
            Clients.TryGetValue(connId, out client);
            if (client != null && client.Closed) {
                client = null;
            }
        }

        bool isNewSession = false;
        if (client == null) {
            client = AllocateClient(false);
            isNewSession = true;
            var welcome = new Dictionary<string, object>();
            welcome["type"] = "welcome";
            welcome["connId"] = client.Id;
            SendJson(client, welcome, ser);
        } else {
            client.LastSeenUtc = DateTime.UtcNow;
        }

        bool processedAction = false;
        if (reqObj != null) {
            object msgsObj;
            if (reqObj.TryGetValue("messages", out msgsObj)) {
                var arr = AsList(msgsObj);
                if (arr != null) {
                    foreach (object item in arr) {
                        var msgDict = AsDict(item);
                        if (msgDict != null) {
                            processedAction = true;
                            HandleRelayEnvelope(client, msgDict, ser);
                        }
                    }
                }
            } else if (reqObj.ContainsKey("type")) {
                processedAction = true;
                HandleRelayEnvelope(client, reqObj, ser);
            }
        }

        if (isNewSession && !string.IsNullOrEmpty(connId) && !processedAction) {
            // Inform recycled HTTP client cleanly only if it wasn't starting fresh via host_room/join_room
        }

        List<Dictionary<string, object>> drained;
        lock (client.SyncLock) {
            drained = new List<Dictionary<string, object>>(client.HttpOutbox);
            client.HttpOutbox.Clear();
        }

        var responsePayload = new Dictionary<string, object>();
        responsePayload["ok"] = true;
        responsePayload["connId"] = client.Id;
        responsePayload["events"] = drained;
        context.Response.Write(ser.Serialize(responsePayload));
    }

    private async Task HandleWebSocketAsync(AspNetWebSocketContext wsContext) {
        var ser = CreateSerializer();
        RelayClient client = AllocateClient(true);
        client.WsContext = wsContext;

        var cts = new CancellationTokenSource();
        var sendLoopTask = Task.Run(() => RunWsSendLoop(client, cts.Token));

        var welcome = new Dictionary<string, object>();
        welcome["type"] = "welcome";
        welcome["connId"] = client.Id;
        SendJson(client, welcome, ser);

        byte[] recvBuf = new byte[64 * 1024];
        try {
            while (wsContext.WebSocket.State == WebSocketState.Open) {
                var ms = new MemoryStream();
                WebSocketReceiveResult result;
                do {
                    result = await wsContext.WebSocket.ReceiveAsync(new ArraySegment<byte>(recvBuf), cts.Token);
                    if (result.MessageType == WebSocketMessageType.Close) {
                        client.Closed = true;
                        break;
                    }
                    if (result.Count > 0) {
                        ms.Write(recvBuf, 0, result.Count);
                    }
                } while (!result.EndOfMessage && ms.Length < 4 * 1024 * 1024);

                client.LastSeenUtc = DateTime.UtcNow;

                if (client.Closed || result.MessageType == WebSocketMessageType.Close) {
                    break;
                }

                if (result.MessageType == WebSocketMessageType.Text && ms.Length > 0) {
                    string jsonText = Encoding.UTF8.GetString(ms.ToArray());
                    try {
                        var msgDict = AsDict(ser.DeserializeObject(jsonText));
                        if (msgDict != null) {
                            HandleRelayEnvelope(client, msgDict, ser);
                        }
                    } catch {
                        // Ignore malformed JSON frames
                    }
                }
            }
        } catch {
            // Socket dropped
        } finally {
            client.Closed = true;
            cts.Cancel();
            try { client.WsSignal.Release(); } catch { }
            DetachClientFromRoom(client, ser);
            RelayClient removed;
            Clients.TryRemove(client.Id, out removed);
        }
        try {
            if (wsContext.WebSocket.State == WebSocketState.Open || wsContext.WebSocket.State == WebSocketState.CloseReceived) {
                await wsContext.WebSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closed", CancellationToken.None);
            }
        } catch { }
        try { await sendLoopTask; } catch { }
    }

    private static async Task RunWsSendLoop(RelayClient client, CancellationToken token) {
        while (!token.IsCancellationRequested && !client.Closed) {
            try {
                await client.WsSignal.WaitAsync(token);
            } catch {
                break;
            }
            while (!client.Closed && client.WsContext != null && client.WsContext.WebSocket.State == WebSocketState.Open) {
                string nextJson = null;
                lock (client.SyncLock) {
                    if (client.WsOutbox.Count > 0) {
                        nextJson = client.WsOutbox.Dequeue();
                    }
                }
                if (nextJson == null) break;
                try {
                    byte[] bytes = Encoding.UTF8.GetBytes(nextJson);
                    await client.WsContext.WebSocket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, token);
                } catch {
                    client.Closed = true;
                    break;
                }
            }
        }
    }

    private static RelayClient AllocateClient(bool isWebSocket) {
        int seq = Interlocked.Increment(ref NextConnSeq);
        var client = new RelayClient {
            Id = "p_" + seq,
            RoomId = null,
            IsHost = false,
            IsWebSocket = isWebSocket,
            Closed = false,
            LastSeenUtc = DateTime.UtcNow
        };
        Clients[client.Id] = client;
        return client;
    }

    private static void SweepStaleClients() {
        DateTime cutoff = DateTime.UtcNow.AddSeconds(-ClientStaleSeconds);
        JavaScriptSerializer ser = null;
        foreach (var kvp in Clients) {
            var c = kvp.Value;
            if (!c.IsWebSocket && !c.Closed && c.LastSeenUtc < cutoff) {
                if (ser == null) ser = CreateSerializer();
                c.Closed = true;
                DetachClientFromRoom(c, ser);
                RelayClient removed;
                Clients.TryRemove(kvp.Key, out removed);
            }
        }
    }

    private static void SendJson(RelayClient target, Dictionary<string, object> obj, JavaScriptSerializer ser) {
        if (target == null || target.Closed || obj == null) return;
        if (target.IsWebSocket) {
            string json = ser.Serialize(obj);
            lock (target.SyncLock) {
                if (target.Closed) return;
                target.WsOutbox.Enqueue(json);
            }
            try { target.WsSignal.Release(); } catch { }
            return;
        }

        lock (target.SyncLock) {
            if (target.Closed) return;
            if (target.HttpOutbox.Count >= MaxHttpOutbox) {
                // Evict oldest snapshot frames first so control messages are never dropped
                int dropIdx = -1;
                for (int i = 0; i < target.HttpOutbox.Count; i++) {
                    if (GetStr(target.HttpOutbox[i], "type") == "relayed_from_host") {
                        dropIdx = i;
                        break;
                    }
                }
                if (dropIdx >= 0) target.HttpOutbox.RemoveAt(dropIdx);
                else target.HttpOutbox.RemoveAt(0);
            }
            target.HttpOutbox.Add(obj);
        }
    }

    private static string MakeRoomCode() {
        lock (RngLock) {
            for (int attempt = 0; attempt < 32; attempt++) {
                char[] buf = new char[6];
                for (int i = 0; i < 6; i++) {
                    buf[i] = RoomAlphabet[Rng.Next(RoomAlphabet.Length)];
                }
                string candidate = new string(buf);
                if (!Rooms.ContainsKey(candidate)) {
                    return candidate;
                }
            }
        }
        return Guid.NewGuid().ToString("N").Substring(0, 6).ToUpperInvariant();
    }

    private static void DetachClientFromRoom(RelayClient client, JavaScriptSerializer ser) {
        if (client == null) return;
        lock (RoomMgmtLock) {
            if (string.IsNullOrEmpty(client.RoomId)) {
                client.IsHost = false;
                return;
            }
            string rid = client.RoomId;
            bool wasHost = client.IsHost;
            client.RoomId = null;
            client.IsHost = false;

            RelayRoom room;
            if (!Rooms.TryGetValue(rid, out room) || room == null) {
                return;
            }

            if (wasHost && room.Host == client) {
                foreach (var peer in room.Peers.Values) {
                    peer.RoomId = null;
                    peer.IsHost = false;
                    var note = new Dictionary<string, object>();
                    note["type"] = "host_disconnected";
                    note["roomId"] = rid;
                    SendJson(peer, note, ser);
                }
                room.Peers.Clear();
                RelayRoom removedRoom;
                Rooms.TryRemove(rid, out removedRoom);
            } else {
                RelayClient removedPeer;
                if (room.Peers.TryRemove(client.Id, out removedPeer)) {
                    if (room.Host != null && !room.Host.Closed) {
                        var note = new Dictionary<string, object>();
                        note["type"] = "peer_socket_disconnected";
                        note["peerId"] = client.Id;
                        SendJson(room.Host, note, ser);
                    }
                }
            }
        }
    }

    private static void HandleRelayEnvelope(RelayClient client, Dictionary<string, object> msg, JavaScriptSerializer ser) {
        string msgType = GetStr(msg, "type");
        if (string.IsNullOrEmpty(msgType)) return;

        switch (msgType) {
            case "host_room": {
                DetachClientFromRoom(client, ser);
                string requested = GetStr(msg, "roomId").Trim().ToUpperInvariant();
                requested = Regex.Replace(requested, "[^A-Z0-9_-]", "");
                RelayRoom newRoom;
                lock (RoomMgmtLock) {
                    if (string.IsNullOrEmpty(requested) || Rooms.ContainsKey(requested)) {
                        requested = MakeRoomCode();
                    }
                    client.RoomId = requested;
                    client.IsHost = true;
                    newRoom = new RelayRoom { Id = requested, Host = client };
                    Rooms[requested] = newRoom;
                }
                var reply = new Dictionary<string, object>();
                reply["type"] = "room_hosted";
                reply["roomId"] = requested;
                reply["connId"] = client.Id;
                SendJson(client, reply, ser);
                break;
            }

            case "join_room": {
                DetachClientFromRoom(client, ser);
                string rid = GetStr(msg, "roomId").Trim().ToUpperInvariant();
                RelayRoom room = null;
                bool joined = false;
                lock (RoomMgmtLock) {
                    if (!string.IsNullOrEmpty(rid) && Rooms.TryGetValue(rid, out room) &&
                        room != null && room.Host != null && !room.Host.Closed) {
                        client.RoomId = rid;
                        client.IsHost = false;
                        room.Peers[client.Id] = client;
                        joined = true;
                    }
                }

                if (!joined) {
                    var errReply = new Dictionary<string, object>();
                    errReply["type"] = "relay_error";
                    errReply["message"] = "Room \"" + rid + "\" was not found or host went offline.";
                    SendJson(client, errReply, ser);
                    return;
                }

                var joinReply = new Dictionary<string, object>();
                joinReply["type"] = "room_joined";
                joinReply["roomId"] = rid;
                joinReply["connId"] = client.Id;
                SendJson(client, joinReply, ser);

                var peerNotice = new Dictionary<string, object>();
                peerNotice["type"] = "peer_socket_connected";
                peerNotice["peerId"] = client.Id;
                SendJson(room.Host, peerNotice, ser);
                break;
            }

            case "relay_to_host": {
                if (string.IsNullOrEmpty(client.RoomId) || client.IsHost) return;
                RelayRoom room;
                if (Rooms.TryGetValue(client.RoomId, out room) && room != null && room.Host != null && !room.Host.Closed) {
                    object payloadObj = null;
                    msg.TryGetValue("payload", out payloadObj);
                    var fwd = new Dictionary<string, object>();
                    fwd["type"] = "relayed_from_peer";
                    fwd["fromId"] = client.Id;
                    fwd["payload"] = payloadObj;
                    SendJson(room.Host, fwd, ser);
                }
                break;
            }

            case "relay_to_peer": {
                if (string.IsNullOrEmpty(client.RoomId) || !client.IsHost) return;
                RelayRoom room;
                if (!Rooms.TryGetValue(client.RoomId, out room) || room == null) return;
                string targetId = GetStr(msg, "targetId");
                RelayClient peer;
                if (!string.IsNullOrEmpty(targetId) && room.Peers.TryGetValue(targetId, out peer) && peer != null && !peer.Closed) {
                    object payloadObj = null;
                    msg.TryGetValue("payload", out payloadObj);
                    var fwd = new Dictionary<string, object>();
                    fwd["type"] = "relayed_from_host";
                    fwd["payload"] = payloadObj;
                    SendJson(peer, fwd, ser);
                }
                break;
            }

            case "relay_broadcast": {
                if (string.IsNullOrEmpty(client.RoomId) || !client.IsHost) return;
                RelayRoom room;
                if (!Rooms.TryGetValue(client.RoomId, out room) || room == null) return;
                object payloadObj = null;
                msg.TryGetValue("payload", out payloadObj);
                foreach (var peer in room.Peers.Values) {
                    if (peer != null && !peer.Closed) {
                        var fwd = new Dictionary<string, object>();
                        fwd["type"] = "relayed_from_host";
                        fwd["payload"] = payloadObj;
                        SendJson(peer, fwd, ser);
                    }
                }
                break;
            }

            case "leave_room": {
                DetachClientFromRoom(client, ser);
                break;
            }

            case "poll":
            case "ping": {
                break;
            }
        }
    }

    private static Dictionary<string, object> AsDict(object obj) {
        return obj as Dictionary<string, object>;
    }

    private static IEnumerable<object> AsList(object obj) {
        return obj as IEnumerable<object>;
    }

    private static string GetStr(Dictionary<string, object> dict, string key) {
        if (dict == null || key == null) return "";
        object val;
        if (dict.TryGetValue(key, out val) && val != null) {
            return Convert.ToString(val) ?? "";
        }
        return "";
    }

    private static string GetStrQuery(HttpContext ctx, string key) {
        if (ctx == null || ctx.Request == null || ctx.Request.QueryString == null) return "";
        string val = ctx.Request.QueryString[key];
        return val ?? "";
    }
}
