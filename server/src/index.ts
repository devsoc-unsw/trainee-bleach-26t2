import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { clientMessageSchema, envelopeSchema, joinSchema } from './schema.js';
import type { ClientMessage, ErrorResponse, JoinMessage, ReadyMessage } from './schema.js';
import { addPlayer, broadcast, checkLobbyReady, createRoom, getRoom, lobbySnapshot, removePlayer, sendTo, updatePlayerReady } from './rooms.js';
import { Player, Room, Vec3 } from './interface.js';
import { COURSE, COURSE_ID } from './course.js';
import { updateBallState } from './player.js';

const PORT = parseInt(process.env['PORT'] ?? '8080', 10);
const IS_PRODUCTION = process.env['NODE_ENV'] === 'production';
const HOST = IS_PRODUCTION ? '0.0.0.0' : '127.0.0.1';

interface LogEntry {
  ts: string;
  event: string;
  [key: string]: unknown;
}

function log(entry: LogEntry): void {
  process.stdout.write(JSON.stringify(entry) + '\n');
}

const startTime = Date.now();

const server = http.createServer((_req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');

  if (_req.method === 'GET' && _req.url === '/health') {
    const body = JSON.stringify({
      status: 'ok',
      uptime: Math.floor((Date.now() - startTime) / 1000),
    });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(body);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
});

// TODO(security): restrict verifyClient to known client origins before production
const wss = new WebSocketServer({
  server,
  verifyClient: (info, callback) => {
    log({
      ts: new Date().toISOString(),
      event: 'ws_upgrade_request',
      origin: info.origin ?? 'none',
    });
    callback(true);
  },
});

// IN_PROGRESS: room management
//   - rooms: Map<string, Room> stored in memory
//   - generate 4-letter room codes (no vowels, no ambiguous chars)
//   - destroy room when last player disconnects
//   - idle room timeout
//
// TODO: Room type needs:
//   - players map, host tracking [done]
//   - game state machine: LOBBY -> COUNTDOWN -> HOLE_ACTIVE -> HOLE_SUMMARY -> MATCH_END [done]
//   - per-hole timer (90s)
//   - stroke counts (server-authoritative) [done; per player]
//   - hole config (par, spawn position, cup position) [done]

let connectionCounter = 0;

wss.on('connection', (ws: WebSocket) => {
  const connectionId = ++connectionCounter;
  let currentPlayer: Player | null = null;
  let currentRoom: Room | null = null;

  log({
    ts: new Date().toISOString(),
    event: 'ws_open',
    connectionId,
  });

  ws.on('message', (raw: Buffer | ArrayBuffer | Buffer[]) => {
    let text: string;
    try {
      if (Buffer.isBuffer(raw)) {
        text = raw.toString('utf-8');
      } else if (raw instanceof ArrayBuffer) {
        text = Buffer.from(raw).toString('utf-8');
      } else {
        text = Buffer.concat(raw).toString('utf-8');
      }
    } catch {
      sendError(ws, 'PARSE_ERROR', 'Could not decode message as UTF-8');
      log({
        ts: new Date().toISOString(),
        event: 'ws_decode_error',
        connectionId,
      });
      return;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      sendError(ws, 'PARSE_ERROR', 'Invalid JSON');
      log({
        ts: new Date().toISOString(),
        event: 'ws_json_error',
        connectionId,
        raw: text.slice(0, 200),
      });
      return;
    }

    const result = clientMessageSchema.safeParse(parsed);

    if (!result.success) {
      const issues = result.error.issues.map((i) => i.message).join('; ');
      sendError(ws, 'INVALID_MESSAGE', issues);
      log({
        ts: new Date().toISOString(),
        event: 'ws_validation_failure',
        connectionId,
        issues,
      });
      return;
    }

    log({
      ts: new Date().toISOString(),
      event: 'ws_message',
      connectionId,
      type: result.data.t,
    });

    // TODO: replace echo with message routing by result.data.t:
    //   DONE 'join'        -> create/join room, assign player id + colour, broadcast lobby_state
    //   DONE 'ready'       -> toggle ready, broadcast lobby_state
    //   DONE 'start_match' -> host only, transition LOBBY -> COUNTDOWN
    //   'shot'        -> validate (rate limit 250ms, atRest gate, HOLE_ACTIVE only),
    //                    increment stroke count, broadcast stroke_update
    //   DONE 'ball_state'  -> rebroadcast as part of snapshot (15Hz while balls moving)
    //   'holed'       -> validate position against cup, lock score, check if hole done
    //   'oob'         -> add penalty stroke, broadcast stroke_update
    //   'ping'        -> reply with pong
    //
    // TODO: server validation:
    //   - shot rate limit (min 250ms between shots per player)
    //   - shot only accepted if client reported atRest and during HOLE_ACTIVE
    //   - holed position must be within tolerance of cup position
    //   - positions outside per-hole bounding box get ignored
    //   - par+3 cap: end hole for player at par+3 strokes

    // result is an envelopeSchema
    switch (result.data.t) {
      case 'join': {
        const joinResult = doJoin(ws, result.data);
        if (joinResult) {
          currentPlayer = joinResult.player;
          currentRoom = joinResult.room;
        }
        break;
      }

      case 'ready': {
        const joined = requireJoined(ws, currentPlayer, currentRoom);
        if (!joined) break;
        doReady(joined.player, joined.room);
        break;
      }

      case 'start_match': {
        const joined = requireJoined(ws, currentPlayer, currentRoom);
        if (!joined) break;
        doStartMatch(joined.player, joined.room);
        break;
      }
      
      case 'ball_state': {
        const joined = requireJoined(ws, currentPlayer, currentRoom);
        if (!joined) break;
        //update the velocity, pos and atRest
        const res = result.data;
        doUpdateBallState(joined.player, res.pos, res.vel, res.atRest);
        break;
      }

    }
  });

  ws.on('close', (code: number, reason: Buffer) => {
    if (currentPlayer && currentRoom) {
      removePlayer(currentRoom, currentPlayer.id);
      broadcast(currentRoom, {
        t: 'player_left',
        playerId: currentPlayer.id
      });
    }
    
    log({
      ts: new Date().toISOString(),
      event: 'ws_close',
      connectionId,
      code,
      reason: reason.toString('utf-8'),
    });
  });

  ws.on('error', (err: Error) => {
    log({
      ts: new Date().toISOString(),
      event: 'ws_error',
      connectionId,
      error: err.message,
    });
  });
});

function sendError(ws: WebSocket, code: string, message: string): void {
  const response: ErrorResponse = { t: 'error', code, message };
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(response));
  }
}

server.listen(PORT, HOST, () => {
  log({
    ts: new Date().toISOString(),
    event: 'server_start',
    host: HOST,
    port: PORT,
    env: IS_PRODUCTION ? 'production' : 'development',
  });
});

function requireJoined(
  ws: WebSocket,
  player: Player | null,
  room: Room | null
): { player: Player; room: Room } | null {
  if (!player || !room) {
    sendError(ws, 'NOT_JOINED', 'Must join a room before sending this message');
    return null;
  }
  return { player, room };
}

function doJoin(ws: WebSocket, data: JoinMessage): { player: Player, room: Room } | null {
  const room = data.code ? getRoom(data.code) : createRoom();
  if (!room) {
    sendError(ws, 'ROOM_NOT_FOUND', "No room with that code");
    return null;
  }
  const player = addPlayer(room, ws, data.name);
  if (!player) {
    sendError(ws, 'ROOM_FULL', 'This room already has the maximum number of players');
    return null;
  }
  sendTo(player, {
      t: 'joined',
      playerId: player.id,
      code: room.code,
      players: lobbySnapshot(room)
  });
  broadcast(room, {
    t: 'lobby_state',
    players: lobbySnapshot(room)
  });

  return {
    player,
    room
  };
}

function doReady(player: Player, room: Room): void {
  updatePlayerReady(room, player.id, true);
  broadcast(room, {
    t: 'lobby_state',
    players: lobbySnapshot(room)
  });
  
}

function doStartMatch(player: Player, room: Room): void {
  if (player.id !== room.hostId) {
    sendError(player.ws, 'NOT_HOST', 'Only the host can start the match');
    return;
  }

  if (!checkLobbyReady(room)) {
    sendError(player.ws, 'NOT_READY', 'All players must be ready');
    return;
  }

  broadcast(room, {
    t: 'match_start',
    courseId: COURSE_ID,
    holes: COURSE.map((h) => ({ index: h.index, par: h.par, name: h.name }))
  });

}

function doUpdateBallState(player: Player, pos: Vec3, vel: Vec3, atRest: boolean): void {
  updateBallState(player, pos, vel, atRest);
}