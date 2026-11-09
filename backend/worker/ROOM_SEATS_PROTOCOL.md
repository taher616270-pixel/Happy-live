# Happy Live — Realtime microphone seats

## Runtime model

- One Durable Object is selected per room with `ROOM_SEATS.idFromName(roomId)`.
- The Durable Object owns the authoritative 8-seat map and serializes mutations through one queue.
- Seat moves over the authenticated WebSocket do not query or write D1. D1 is used at connection setup for authentication, room status and moderation checks, and for unrelated room/profile metadata.
- The DO keeps the active seat map in memory and persists snapshots to its own durable storage so a restart does not erase the room.
- A seat lease lasts 45 seconds. Clients send `seat_heartbeat` every 15 seconds.
- The legacy authenticated `POST /rooms/:id/seats` endpoint is retained for compatibility and routes its seat mutation to the same DO.

## WebSocket endpoint

`GET /api/v1/rooms/{roomId}/seat-stream`

The client requests subprotocols `happy-live-seats` and the existing access token. The Worker validates the token once, checks the room and moderation state, then proxies the socket to the room DO. The DO never trusts a user ID supplied in a message; it uses the identity attached by the authenticated Worker handshake.

## Client → server

Move into seat 5:

```json
{
  "type": "move_seat",
  "from": 2,
  "to": 5,
  "version": 1845000000000001
}
```

Move from a seat to the audience:

```json
{
  "type": "move_seat",
  "from": 5,
  "to": null,
  "version": 1845000000000002
}
```

Keep the seat lease alive:

```json
{ "type": "seat_heartbeat" }
```

The DO treats `from` as the client's last-known seat for diagnostics. It derives the actual source seat from the authenticated user in the authoritative map, so a rejected earlier tap does not make a later rapid tap unusable.

## Server → client

Initial connection or reconnect:

```json
{
  "type": "seat_snapshot",
  "revision": 21,
  "mySeat": 5,
  "seats": [
    {
      "seatNumber": 5,
      "userId": "user-id",
      "name": "User",
      "userCode": "12345678",
      "uid": 12345678,
      "avatarUrl": "https://...",
      "isMuted": false,
      "isRoomOwner": false,
      "isRoomModerator": false,
      "expiresAt": 1845000045000
    }
  ]
}
```

Requester acknowledgement:

```json
{
  "type": "ack",
  "ok": true,
  "code": "moved",
  "version": 1845000000000001,
  "from": 2,
  "mySeat": 5,
  "revision": 22,
  "seats": []
}
```

Rejected move (the acknowledgement includes the authoritative state for rollback):

```json
{
  "type": "ack",
  "ok": false,
  "code": "seat_occupied",
  "version": 1845000000000001,
  "mySeat": 2,
  "revision": 22,
  "seats": []
}
```

Other room members receive:

```json
{ "type": "seat_updated", "revision": 22, "seats": [] }
```

Heartbeat response:

```json
{ "type": "heartbeat_ack", "serverTime": 1845000000000 }
```

## Agora behaviour

Agora is joined once as broadcaster. The initial token contains join privilege only. When the DO confirms that the user owns a seat, the app requests a publisher token, renews the current Agora token and toggles microphone publication using `updateChannelMediaOptions(publishMicrophoneTrack: true)` on native or `publish()` on Web. Leaving the last seat renews a join-only token and disables publication. Moving between two occupied-by-self positions does not call leave or join and does not toggle the microphone.

The stable Agora UID is the authenticated numeric user code (`gabo_id`), not the seat number. UI speaking indicators resolve that UID through the current seat snapshot, so the gold speaking ring follows the user's current seat.

## Latency test

Flutter logs these measurements in the debug console:

- `optimistic_avatar_frame_ms`: tap → first Flutter frame after the local avatar move. This is the 300 ms UI target.
- `server_ack_ms`: tap → authoritative DO acknowledgement.
- `http_fallback_ack_ms`: tap → acknowledgement when the socket is disconnected and the compatibility endpoint is used.

Test with two or more devices in the same room:
1. Keep the seat WebSocket connected and open the debug console.
2. Move between seats 1–8 repeatedly, including sequences such as 2 → 5 → 3 → 8.
3. Confirm the avatar changes locally in the first frame and the frame metric remains below 300 ms.
4. Have another device claim the destination seat at the same time; the losing client must animate back to the authoritative seat.
5. Disconnect Wi-Fi briefly and reconnect. The next `seat_snapshot` must reconcile any pending optimistic state.
6. Compare p50/p95 of `optimistic_avatar_frame_ms` separately from `server_ack_ms`; network/server latency must not be confused with local render latency.

The UI target is local rendering under 300 ms. A remote acknowledgement cannot be guaranteed under 300 ms on every mobile network.
