import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';
import { envelopeSchema } from './schema.js';
import type { ErrorResponse } from './schema.js';
import * as rooms from './rooms.js';
import * as phone from './phone.js';
import * as remoteHttps from './remote_https.js';

const PORT = parseInt(process.env['PORT'] ?? '8080', 10);
const IS_PRODUCTION = process.env['NODE_ENV'] === 'production';
const HOST = IS_PRODUCTION ? '0.0.0.0' : '0.0.0.0';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = process.env['WEB_ROOT'] ?? path.resolve(HERE, '../../client/build');
const PUBLIC_DIR = path.resolve(HERE, '../public');
const PHONE_PAGE = path.join(PUBLIC_DIR, 'phone.html');
const REMOTE_PAGE = path.resolve(HERE, '../../client/ui/phone_remote.html');

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
  '.css': 'text/css; charset=utf-8',
  '.ico': 'image/x-icon',
  '.wasm.map': 'application/json',
};

interface LogEntry {
  ts: string;
  event: string;
  [key: string]: unknown;
}

function log(entry: LogEntry): void {
  process.stdout.write(JSON.stringify(entry) + '\n');
}

const startTime = Date.now();

function setSecurityHeaders(res: http.ServerResponse, embed = true): void {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  if (embed) {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  }
}

function servePhone(req: http.IncomingMessage, res: http.ServerResponse): boolean {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return false;
  }
  const remote = url.pathname === '/remote' || url.pathname === '/remote/';
  if (url.pathname !== '/phone' && url.pathname !== '/phone/' && !remote) {
    return false;
  }
  setSecurityHeaders(res, false);
  const page = remote ? REMOTE_PAGE : PHONE_PAGE;
  if (!fs.existsSync(page)) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Phone remote page missing');
    return true;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  if (req.method === 'HEAD') {
    res.end();
    return true;
  }
  fs.createReadStream(page).pipe(res);
  return true;
}

function tryServePhoneRemote(req: http.IncomingMessage, res: http.ServerResponse): boolean {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (url.pathname !== '/phone/remote') {
    return false;
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('method not allowed');
    return true;
  }
  setSecurityHeaders(res, false);
  const body = JSON.stringify(remoteHttps.remoteInfo(remoteHttps.httpsPort(PORT)));
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  if (req.method === 'HEAD') {
    res.end();
    return true;
  }
  res.end(body);
  return true;
}

function tryServePhoneQr(req: http.IncomingMessage, res: http.ServerResponse): boolean {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (url.pathname !== '/phone/qr') {
    return false;
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('method not allowed');
    return true;
  }
  setSecurityHeaders(res, false);
  const target = phone.qrTarget(url.searchParams.get('u'));
  if (!target) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('missing url');
    return true;
  }
  void phone
    .pngForUrl(target)
    .then((png) => {
      if (res.writableEnded) {
        return;
      }
      res.writeHead(200, {
        'Content-Type': 'image/png',
        'Cache-Control': 'no-store',
      });
      if (req.method === 'HEAD') {
        res.end();
        return;
      }
      res.end(png);
    })
    .catch(() => {
      if (!res.writableEnded) {
        res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('qr failed');
      }
    });
  return true;
}

function serveFile(req: http.IncomingMessage, res: http.ServerResponse): void {
  if (remoteHttps.tryPhoneApi(req, res)) {
    return;
  }
  if (tryServePhoneRemote(req, res)) {
    return;
  }
  if (tryServePhoneQr(req, res)) {
    return;
  }
  if (servePhone(req, res)) {
    return;
  }
  setSecurityHeaders(res);
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (req.method === 'GET' && url.pathname === '/health') {
    const body = JSON.stringify({
      status: 'ok',
      uptime: Math.floor((Date.now() - startTime) / 1000),
    });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(body);
    return;
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'method_not_allowed' }));
    return;
  }

  let rel = decodeURIComponent(url.pathname);
  if (rel === '/') {
    rel = '/index.html';
  }
  const target = path.normalize(path.join(WEB_ROOT, rel));
  if (!target.startsWith(WEB_ROOT)) {
    res.writeHead(403, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'forbidden' }));
    return;
  }
  if (!fs.existsSync(target) || fs.statSync(target).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'not_found', hint: 'Export the Godot Web build to client/build' }));
    return;
  }
  const ext = path.extname(target);
  res.writeHead(200, { 'Content-Type': MIME[ext] ?? 'application/octet-stream' });
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  fs.createReadStream(target).pipe(res);
}

const server = http.createServer(serveFile);

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

let connectionCounter = 0;

wss.on('connection', (ws: WebSocket) => {
  const connectionId = ++connectionCounter;
  log({ ts: new Date().toISOString(), event: 'ws_open', connectionId });
  rooms.send(ws, { t: 'welcome', playerId: rooms.register(ws) });
  rooms.send(ws, rooms.lobbyList());

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
      return;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      sendError(ws, 'PARSE_ERROR', 'Invalid JSON');
      return;
    }

    const result = envelopeSchema.safeParse(parsed);
    if (!result.success) {
      sendError(ws, 'INVALID_MESSAGE', result.error.issues.map((i) => i.message).join('; '));
      return;
    }

    const msg = result.data as Record<string, unknown>;
    const type = String(msg['t']);
    log({ ts: new Date().toISOString(), event: 'ws_message', connectionId, type });
    void route(ws, type, msg);
  });

  ws.on('close', () => {
    phone.detach(ws);
    const notice = rooms.departureNotice(ws);
    if (notice) {
      rooms.broadcast(notice.room, notice.payload, ws);
    }
    const room = rooms.leave(ws);
    if (room) {
      rooms.broadcast(room, rooms.lobbyState(room));
      if (room.phase === 'selecting') {
        rooms.broadcast(room, rooms.voteState(room));
      }
      const finished = rooms.tryFinishHole(room);
      if (finished === 'summary') {
        rooms.broadcast(room, rooms.holeEndPayload(room));
        rooms.scheduleHoleAdvance(room, onHoleAdvance);
      }
    }
    broadcastLobbyList();
    log({ ts: new Date().toISOString(), event: 'ws_close', connectionId });
  });

  ws.on('error', (err: Error) => {
    log({ ts: new Date().toISOString(), event: 'ws_error', connectionId, error: err.message });
  });
});

async function route(ws: WebSocket, type: string, msg: Record<string, unknown>): Promise<void> {
  if (phone.isPhoneSocket(ws) && type !== 'swing' && type !== 'pose' && type !== 'ping' && type !== 'phone_link' && type !== 'power') {
    return;
  }
  switch (type) {
    case 'phone_open': {
      try {
        const pair = await phone.openPair(ws, PORT);
        rooms.send(ws, { t: 'phone_ready', code: pair.code, urls: pair.urls, qr: pair.qr });
      } catch (err) {
        log({
          ts: new Date().toISOString(),
          event: 'phone_open_failed',
          error: err instanceof Error ? err.message : String(err),
        });
        sendError(ws, 'PHONE_FAILED', 'Could not start phone remote');
      }
      break;
    }
    case 'phone_link': {
      const linked = phone.linkPhone(ws, String(msg['code'] ?? ''));
      if (typeof linked === 'string') {
        sendError(ws, 'PHONE_FAILED', linked);
      }
      break;
    }
    case 'swing': {
      const swung = phone.swingFrom(ws, msg['power'], msg);
      if (typeof swung === 'string') {
        sendError(ws, 'PHONE_FAILED', swung);
      }
      break;
    }
    case 'pose': {
      const posed = phone.poseFrom(ws, msg);
      if (typeof posed === 'string') {
        sendError(ws, 'PHONE_FAILED', posed);
      }
      break;
    }
    case 'power': {
      const used = phone.powerFrom(ws, msg['kind']);
      if (typeof used === 'string') {
        sendError(ws, 'PHONE_FAILED', used);
      }
      break;
    }
    case 'phone_powers': {
      phone.forwardPowers(ws, msg);
      break;
    }
    case 'list':
      rooms.send(ws, rooms.lobbyList());
      break;
    case 'create': {
      const room = rooms.createRoom(
        ws,
        String(msg['name'] ?? 'Putt Party'),
        Boolean(msg['isPublic'] ?? true),
        String(msg['playerName'] ?? 'Player'),
        Number(msg['rounds'] ?? 1),
        String(msg['gameMode'] ?? 'turn_by_turn')
      );
      rooms.send(ws, rooms.lobbyState(room));
      broadcastLobbyList();
      break;
    }
    case 'join': {
      const joined = rooms.joinRoom(ws, String(msg['code'] ?? ''), String(msg['playerName'] ?? 'Player'));
      if (typeof joined === 'string') {
        sendError(ws, 'JOIN_FAILED', joined);
        return;
      }
      rooms.broadcast(joined, rooms.lobbyState(joined));
      broadcastLobbyList();
      break;
    }
    case 'leave': {
      const notice = rooms.departureNotice(ws);
      if (notice) {
        rooms.broadcast(notice.room, notice.payload, ws);
      }
      const left = rooms.leave(ws);
      if (left) {
        rooms.broadcast(left, rooms.lobbyState(left));
        if (left.phase === 'selecting') {
          rooms.broadcast(left, rooms.voteState(left));
        }
        const finished = rooms.tryFinishHole(left);
        if (finished === 'summary') {
          rooms.broadcast(left, rooms.holeEndPayload(left));
          rooms.scheduleHoleAdvance(left, onHoleAdvance);
        }
      }
      rooms.send(ws, rooms.lobbyList());
      broadcastLobbyList();
      break;
    }
    case 'chat': {
      const posted = rooms.chatFrom(ws, String(msg['text'] ?? ''));
      if (typeof posted === 'string') {
        sendError(ws, 'CHAT_FAILED', posted);
        return;
      }
      rooms.broadcast(posted.room, posted.payload);
      break;
    }
    case 'select': {
      const picking = rooms.beginSelect(ws);
      if (typeof picking === 'string') {
        sendError(ws, 'START_FAILED', picking);
        return;
      }
      rooms.broadcast(picking, rooms.voteState(picking));
      broadcastLobbyList();
      break;
    }
    case 'vote': {
      const voted = rooms.castVote(ws, String(msg['mapId'] ?? ''));
      if (typeof voted === 'string') {
        sendError(ws, 'VOTE_FAILED', voted);
        return;
      }
      rooms.broadcast(voted, rooms.voteState(voted));
      break;
    }
    case 'quick_start': {
      const started = rooms.quickStart(ws);
      if (typeof started === 'string') {
        sendError(ws, 'START_FAILED', started);
        return;
      }
      rooms.broadcast(started, { t: 'match_start', mapId: started.mapId });
      broadcastLobbyList();
      break;
    }
    case 'start': {
      const started = rooms.startMatch(ws, String(msg['mapId'] ?? 'rainbow_stairs'));
      if (typeof started === 'string') {
        sendError(ws, 'START_FAILED', started);
        return;
      }
      rooms.broadcast(started, { t: 'match_start', mapId: started.mapId });
      broadcastLobbyList();
      break;
    }
    case 'shot': {
      const player = rooms.playerFor(ws);
      const room = rooms.roomFor(ws);
      if (!player || !room || room.phase !== 'playing') {
        return;
      }
      player.strokes += 1;
      rooms.broadcast(room, { t: 'stroke_update', playerId: player.id, strokes: player.strokes });
      break;
    }
    case 'power_use': {
      const used = rooms.usePower(ws, String(msg['kind'] ?? ''));
      if (typeof used === 'string') {
        return;
      }
      break;
    }
    case 'pickup': {
      const claimed = rooms.claimPickup(ws, String(msg['pickupId'] ?? ''), String(msg['kind'] ?? ''));
      if (typeof claimed === 'string') {
        sendError(ws, 'PICKUP_TAKEN', claimed);
        return;
      }
      break;
    }
    case 'bump': {
      const bumped = rooms.forwardBump(
        ws,
        String(msg['targetId'] ?? ''),
        num(msg['vx']),
        num(msg['vy']),
        num(msg['vz'])
      );
      if (typeof bumped === 'string') {
        return;
      }
      break;
    }
    case 'ball_state': {
      const player = rooms.playerFor(ws);
      const room = rooms.roomFor(ws);
      if (!player || !room || room.phase !== 'playing') {
        return;
      }
      player.ball = {
        id: player.id,
        x: num(msg['x']),
        y: num(msg['y']),
        z: num(msg['z']),
        vx: num(msg['vx']),
        vy: num(msg['vy']),
        vz: num(msg['vz']),
        atRest: Boolean(msg['atRest']),
      };
      rooms.broadcast(room, rooms.snapshot(room), ws);
      break;
    }
    case 'holed': {
      const player = rooms.playerFor(ws);
      const marked = rooms.markHoled(ws);
      if (typeof marked === 'string' || !player) {
        return;
      }
      rooms.broadcast(marked.room, { t: 'player_holed', playerId: player.id, strokes: player.strokes });
      rooms.broadcast(marked.room, rooms.holeNotice(player));
      if (marked.result === 'summary') {
        rooms.broadcast(marked.room, rooms.holeEndPayload(marked.room));
        rooms.scheduleHoleAdvance(marked.room, onHoleAdvance);
      }
      break;
    }
    case 'set_mode': {
      const changed = rooms.setGameMode(ws, String(msg['mode'] ?? ''));
      if (typeof changed === 'string') {
        sendError(ws, 'MODE_FAILED', changed);
        return;
      }
      rooms.broadcast(changed, rooms.lobbyState(changed));
      break;
    }
    case 'set_profile': {
      const name = typeof msg['name'] === 'string' ? String(msg['name']) : undefined;
      const color = typeof msg['color'] === 'string' ? String(msg['color']) : undefined;
      const updated = rooms.setProfile(ws, name, color);
      if (typeof updated === 'string') {
        sendError(ws, 'PROFILE_FAILED', updated);
        return;
      }
      rooms.broadcast(updated, rooms.lobbyState(updated));
      break;
    }
    case 'oob': {
      const player = rooms.playerFor(ws);
      const room = rooms.roomFor(ws);
      if (!player || !room) {
        return;
      }
      player.strokes += 1;
      rooms.broadcast(room, { t: 'stroke_update', playerId: player.id, strokes: player.strokes });
      break;
    }
    case 'cursor': {
      const player = rooms.playerFor(ws);
      const room = rooms.roomFor(ws);
      if (!player || !room) {
        return;
      }
      rooms.broadcast(
        room,
        {
          t: 'cursor',
          playerId: player.id,
          x: Math.min(1, Math.max(0, num(msg['x']))),
          y: Math.min(1, Math.max(0, num(msg['y']))),
          on: Boolean(msg['on']),
        },
        ws
      );
      break;
    }
    case 'ping':
      rooms.send(ws, { t: 'pong' });
      break;
    default:
      break;
  }
}

function num(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function broadcastLobbyList(): void {
  const list = rooms.lobbyList();
  for (const client of wss.clients) {
    if (rooms.roomFor(client)) {
      continue;
    }
    rooms.send(client, list);
  }
}

function sendError(ws: WebSocket, code: string, message: string): void {
  const response: ErrorResponse = { t: 'error', code, message };
  rooms.send(ws, response);
}

function onHoleAdvance(room: rooms.Room, result: 'vote' | 'over'): void {
  if (result === 'vote') {
    rooms.broadcast(room, rooms.voteState(room));
    broadcastLobbyList();
    return;
  }
  rooms.broadcast(room, { t: 'match_over', placings: rooms.matchPlacings(room) });
  rooms.broadcast(room, rooms.lobbyState(room));
  broadcastLobbyList();
}

rooms.setVoteEndedHandler((room) => {
  rooms.broadcast(room, { t: 'match_start', mapId: room.mapId });
  broadcastLobbyList();
});

const secureServer = remoteHttps.createHttpsServer();
const mux = net.createServer((socket) => {
  socket.once('data', (data) => {
    socket.pause();
    socket.unshift(data);
    if (data[0] === 0x16 && secureServer) {
      secureServer.emit('connection', socket);
    } else {
      server.emit('connection', socket);
    }
    process.nextTick(() => {
      socket.resume();
    });
  });
});

mux.listen(PORT, HOST, () => {
  const securePort = remoteHttps.httpsPort(PORT);
  log({
    ts: new Date().toISOString(),
    event: 'server_start',
    phone: phone.phonePageUrls(PORT),
    remote: remoteHttps.remotePageUrls(securePort),
    httpsPort: securePort,
    https: secureServer != null,
    host: HOST,
    port: PORT,
    env: IS_PRODUCTION ? 'production' : 'development',
    webRoot: WEB_ROOT,
  });
  if (process.env['PUTT_SKIP_HOST_PROBE'] === '1') {
    return;
  }
  setImmediate(() => {
    const hosts = phone.discoverPhoneHosts();
    phone.setPreferredHosts(hosts);
    const shared = phone.trySharePortOnWindows(PORT);
    log({
      ts: new Date().toISOString(),
      event: 'phone_lan',
      hosts,
      phone: phone.phonePageUrls(PORT),
      remote: remoteHttps.remotePageUrls(remoteHttps.httpsPort(PORT)),
      lanShare: shared || 'none',
    });
  });
});
