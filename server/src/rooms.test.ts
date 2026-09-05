import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { WebSocket } from 'ws';
import * as rooms from './rooms.js';

function fakeSocket(): { ws: WebSocket; sent: Record<string, unknown>[] } {
  const sent: Record<string, unknown>[] = [];
  const ws = {
    readyState: WebSocket.OPEN,
    OPEN: WebSocket.OPEN,
    send(data: string) {
      sent.push(JSON.parse(data) as Record<string, unknown>);
    },
  };
  return { ws: ws as unknown as WebSocket, sent };
}

afterEach(() => {
  rooms.resetForTests();
});

describe('rooms', () => {
  it('creates a public lobby with a 4-character code and host player', () => {
    const a = fakeSocket();
    const id = rooms.register(a.ws);
    const room = rooms.createRoom(a.ws, "Lou's Lobby", true, 'Lou');
    assert.equal(room.hostId, id);
    assert.equal(room.code.length, 4);
    assert.equal(room.isPublic, true);
    assert.equal(room.phase, 'lobby');
    assert.equal(room.players.size, 1);
    const list = rooms.publicRooms();
    assert.equal(list.length, 1);
    assert.equal(list[0]?.code, room.code);
    assert.equal(list[0]?.host, 'Lou');
    const state = rooms.lobbyState(room);
    assert.equal(state.hostId, id);
    assert.equal(state.players[0]?.host, true);
    assert.equal(state.players[0]?.id, id);
  });

  it('hides private lobbies from the public list', () => {
    const a = fakeSocket();
    rooms.register(a.ws);
    rooms.createRoom(a.ws, 'Secret', false, 'Host');
    assert.equal(rooms.publicRooms().length, 0);
  });

  it('lets a second player join by code and assigns a different colour', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    rooms.register(a.ws);
    rooms.register(b.ws);
    const room = rooms.createRoom(a.ws, 'Party', true, 'Host');
    const joined = rooms.joinRoom(b.ws, room.code.toLowerCase(), 'Guest');
    assert.notEqual(typeof joined, 'string');
    const live = joined as rooms.Room;
    assert.equal(live.players.size, 2);
    const state = rooms.lobbyState(live);
    const colours = new Set(state.players.map((p) => p.color));
    assert.equal(colours.size, 2);
    assert.ok(state.players[0]!.joinedAt < state.players[1]!.joinedAt);
    assert.equal(rooms.publicRooms()[0]?.players, 2);
  });

  it('rejects a missing code, a started match, and a full room', () => {
    const a = fakeSocket();
    rooms.register(a.ws);
    assert.equal(rooms.joinRoom(a.ws, 'ZZZZ', 'X'), 'No lobby with that code');

    const room = rooms.createRoom(a.ws, 'Full', true, 'Host');
    const extras = [fakeSocket(), fakeSocket(), fakeSocket(), fakeSocket()];
    for (const extra of extras.slice(0, 3)) {
      rooms.register(extra.ws);
      const result = rooms.joinRoom(extra.ws, room.code, 'P');
      assert.notEqual(typeof result, 'string');
    }
    rooms.register(extras[3]!.ws);
    assert.equal(rooms.joinRoom(extras[3]!.ws, room.code, 'Late'), 'That lobby is full');

    const started = rooms.startMatch(a.ws, 'rainbow_stairs');
    assert.notEqual(typeof started, 'string');
    const spectator = fakeSocket();
    rooms.register(spectator.ws);
    assert.equal(rooms.joinRoom(spectator.ws, room.code, 'Too late'), 'That game already started');
    assert.equal(rooms.publicRooms().length, 0);
  });

  it('only the host can start, and guests cannot', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    rooms.register(a.ws);
    rooms.register(b.ws);
    rooms.createRoom(a.ws, 'Game', true, 'Host');
    const room = rooms.roomFor(a.ws);
    assert.ok(room);
    rooms.joinRoom(b.ws, room.code, 'Guest');
    assert.equal(rooms.startMatch(b.ws, 'main_walk'), 'Only the host can start');
    const started = rooms.startMatch(a.ws, 'village_green');
    assert.notEqual(typeof started, 'string');
    assert.equal((started as rooms.Room).phase, 'playing');
    assert.equal((started as rooms.Room).mapId, 'village_green');
  });

  it('passes host to the most recently joined player', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    const c = fakeSocket();
    const hostId = rooms.register(a.ws);
    rooms.register(b.ws);
    const lateId = rooms.register(c.ws);
    const room = rooms.createRoom(a.ws, 'Handoff', true, 'Host');
    rooms.joinRoom(b.ws, room.code, 'Early');
    rooms.joinRoom(c.ws, room.code, 'Late');
    const leftover = rooms.leave(a.ws);
    assert.ok(leftover);
    assert.equal(leftover.hostId, lateId);
    assert.notEqual(leftover.hostId, hostId);
    assert.equal(leftover.players.get(lateId)?.host, true);
  });

  it('broadcasts ball snapshots to everyone except the sender', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    rooms.register(a.ws);
    rooms.register(b.ws);
    const room = rooms.createRoom(a.ws, 'Sync', true, 'Host');
    rooms.joinRoom(b.ws, room.code, 'Guest');
    rooms.startMatch(a.ws, 'rainbow_stairs');
    const host = rooms.playerFor(a.ws);
    assert.ok(host);
    host.ball = { id: host.id, x: 3, y: 0.2, z: -4, vx: 1, vy: 0, vz: 0, atRest: false };
    rooms.broadcast(room, rooms.snapshot(room), a.ws);
    assert.equal(a.sent.length, 0);
    assert.equal(b.sent.length, 1);
    const snap = b.sent[0] as { t: string; balls: Array<{ id: string; x: number }> };
    assert.equal(snap.t, 'snapshot');
    assert.equal(snap.balls.length, 2);
    assert.ok(snap.balls.some((ball) => ball.x === 3));
  });

  it('opens a 30s course vote that only the host can start or skip', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    const hostId = rooms.register(a.ws);
    rooms.register(b.ws);
    const room = rooms.createRoom(a.ws, 'Vote', true, 'Host');
    rooms.joinRoom(b.ws, room.code, 'Guest');

    assert.equal(rooms.beginSelect(b.ws), 'Only the host can start');
    const picking = rooms.beginSelect(a.ws);
    assert.notEqual(typeof picking, 'string');
    const live = picking as rooms.Room;
    assert.equal(live.phase, 'selecting');
    assert.ok(live.voteDeadline - Date.now() > 25_000);
    assert.equal(rooms.publicRooms().length, 0);
    assert.equal(rooms.quickStart(b.ws), 'Only the host can start');
    assert.equal(rooms.castVote(b.ws, 'main_walk'), live);

    const state = rooms.voteState(live);
    assert.equal(state.counts['main_walk'], 1);
    assert.equal(state.votes[hostId], undefined);

    rooms.castVote(a.ws, 'village_green');
    rooms.castVote(b.ws, 'village_green');
    const switched = rooms.voteState(live);
    assert.equal(switched.counts['main_walk'], 0);
    assert.equal(switched.counts['village_green'], 2);

    const started = rooms.quickStart(a.ws);
    assert.notEqual(typeof started, 'string');
    assert.equal((started as rooms.Room).phase, 'playing');
    assert.equal((started as rooms.Room).mapId, 'village_green');
  });

  it('breaks a vote tie with the host pick, or Rainbow Stairs if nobody voted', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    rooms.register(a.ws);
    rooms.register(b.ws);
    const room = rooms.createRoom(a.ws, 'Tie', true, 'Host');
    rooms.joinRoom(b.ws, room.code, 'Guest');
    rooms.beginSelect(a.ws);
    rooms.castVote(a.ws, 'village_green');
    rooms.castVote(b.ws, 'main_walk');
    const tied = rooms.quickStart(a.ws) as rooms.Room;
    assert.equal(tied.mapId, 'village_green');

    const c = fakeSocket();
    const d = fakeSocket();
    rooms.register(c.ws);
    rooms.register(d.ws);
    const empty = rooms.createRoom(c.ws, 'Empty', true, 'Host');
    rooms.joinRoom(d.ws, empty.code, 'Guest');
    rooms.beginSelect(c.ws);
    const fallback = rooms.quickStart(c.ws) as rooms.Room;
    assert.equal(fallback.mapId, 'rainbow_stairs');
  });

  it('relays chat and announces when a player quits mid-match', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    rooms.register(a.ws);
    rooms.register(b.ws);
    const room = rooms.createRoom(a.ws, 'Chat', true, 'Host');
    rooms.joinRoom(b.ws, room.code, 'Guest');
    rooms.startMatch(a.ws, 'rainbow_stairs');

    const posted = rooms.chatFrom(b.ws, '  hello there  ');
    assert.notEqual(typeof posted, 'string');
    const message = posted as { room: rooms.Room; payload: Record<string, unknown> };
    assert.equal(message.payload['text'], 'hello there');
    assert.equal(message.payload['kind'], 'say');

    const notice = rooms.departureNotice(b.ws);
    assert.ok(notice);
    assert.equal(notice?.payload['kind'], 'system');
    assert.match(String(notice?.payload['text']), /Guest left/);

    rooms.markHoled(a.ws);
    const host = [...room.players.values()].find((p) => p.name === 'Host');
    assert.ok(host);
    const scored = rooms.holeNotice(host as rooms.Player);
    assert.equal(scored['kind'], 'system');
    assert.match(String(scored['text']), /Host in ·/);
  });

  it('keeps the chosen round count and opens the next vote after everyone holes', () => {
    const a = fakeSocket();
    const b = fakeSocket();
    rooms.register(a.ws);
    rooms.register(b.ws);
    const room = rooms.createRoom(a.ws, 'Series', true, 'Host', 2);
    assert.equal(room.rounds, 2);
    rooms.joinRoom(b.ws, room.code, 'Guest');
    rooms.startMatch(a.ws, 'rainbow_stairs');

    const first = rooms.markHoled(a.ws) as { result: string };
    assert.equal(first.result, 'player');
    const second = rooms.markHoled(b.ws) as { room: rooms.Room; result: string };
    assert.equal(second.result, 'vote');
    assert.equal(second.room.phase, 'selecting');
    assert.equal(second.room.roundIndex, 1);

    rooms.quickStart(a.ws);
    rooms.markHoled(a.ws);
    const last = rooms.markHoled(b.ws) as { room: rooms.Room; result: string };
    assert.equal(last.result, 'over');
    assert.equal(last.room.phase, 'lobby');
  });
});
