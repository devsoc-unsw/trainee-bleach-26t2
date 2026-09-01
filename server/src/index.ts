import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import { clientMessageSchema } from './schema.js';
import type { ErrorResponse, JoinMessage } from './schema.js';
import { addPlayer, broadcast, checkLobbyReady, createRoom, getRoom, lobbySnapshot, removePlayer, sendTo, togglePlayerReady, updateRoomLastModified } from './rooms.js';
import { GameState, Player, Room, Vec3 } from './interface.js';
import { COURSE, COURSE_ID, getHole } from './course.js';
import { canShoot, markHoled, recordStroke, updateBallState } from './player.js';
import { checkAllHoled, distance, handleHoleTransition, startCountdown } from './hole.js';

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


    // TODO: server validation:
    //   - shot rate limit (min 250ms between shots per player)
    //   - shot only accepted if client reported atRest and during HOLE_ACTIVE
    //   - holed position must be within tolerance of cup position
    //   - positions outside per-hole bounding box get ignored
    //   - par+3 cap: end hole for player at par+3 strokes

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
        const res = result.data;
        doUpdateBallState(joined.room, joined.player, res.pos, res.vel, res.atRest);
        break;
      }
      
      case 'shot': {
        const joined = requireJoined(ws, currentPlayer, currentRoom);
        if (!joined) break;
        // shot and direction are unused
        doShot(ws, joined.player, joined.room);
        break;
      }

      case 'holed': {
        const joined = requireJoined(ws, currentPlayer, currentRoom);
        if (!joined) break;
        const res = result.data;
        doHoled(ws, joined.player, joined.room, res.pos);
        break;
      }

      case 'ping': {
        sendRaw(ws, {
          t: 'pong',
          ts: result.data.ts
        });
        break;
      }

    }
  });

  ws.on('close', (code: number, reason: Buffer) => {
    if (currentPlayer && currentRoom) {
      removePlayer(currentRoom, currentPlayer.id);
      if (currentRoom.state == GameState.HOLE_ACTIVE) checkAllHoled(currentRoom);
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

export function sendError(ws: WebSocket, code: string, message: string): void {
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

// Helper functions:

function sendRaw(ws: WebSocket, msg: unknown): void {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

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

// Wrapper functions:

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
  togglePlayerReady(room, player.id);
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
  
  startCountdown(room, 0);

}

function doUpdateBallState(room: Room, player: Player, pos: Vec3, vel: Vec3, atRest: boolean): void {
  if (room.state === GameState.HOLE_ACTIVE) {
    updateBallState(player, pos, vel, atRest);
    updateRoomLastModified(room);
  };
}

function doShot(ws: WebSocket, player: Player, room: Room): void {
  // check shot rate limit
  const check = canShoot(player, room);
    if (!check.ok) {
      sendError(ws, check.code, check.message);
      return;
    }

  const strokes = recordStroke(player);
  updateRoomLastModified(room);
  broadcast(room, {
    t: 'stroke_update',
    playerId: player.id,
    holeIndex: room.currentHoleIndex,
    strokes: strokes,
  });
}

function doHoled(ws: WebSocket, player: Player, room: Room, position: Vec3): void {
  if (room.state !== GameState.HOLE_ACTIVE) {
    sendError(ws, 'NOT_ACTIVE', 'Hole is not active');
    return;
  }
  
  const hole = getHole(room.currentHoleIndex);
  if (!hole) {
    sendError(ws, 'NO_HOLE', 'No active hole config');
    return;
  }

  const dist = distance(position, hole.cup);
  if (dist > hole.cupTolerance) {
    sendError(ws, 'NOT_IN_CUP', 'Reported position is outside cup tolerance; Ball is at' + position + ' while cup is at ' + hole.cup + '. Distance is ' +
      dist + ' while tolerance is ' + hole.cupTolerance
    );
    return;
  }

  markHoled(player);
  updateRoomLastModified(room);
  broadcast(room, {
    t: 'stroke_update',
    playerId: player.id,
    holeIndex: room.currentHoleIndex,
    strokes: player.strokes,
  });

  checkAllHoled(room); // bug: if the last player to hole it leaves, stuck on this state; have to check if everybody holed the current hole intermittently
}
