import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { spawn, type ChildProcess } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { WebSocket } from 'ws';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PORT = 18080 + Math.floor(Math.random() * 400);
const URL = `ws://127.0.0.1:${PORT}`;

class Client {
  ws: WebSocket;
  inbox: Record<string, unknown>[] = [];

  constructor() {
    this.ws = new WebSocket(URL);
    this.ws.on('message', (raw) => {
      this.inbox.push(JSON.parse(String(raw)) as Record<string, unknown>);
    });
  }

  async open(): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) {
      return;
    }
    await new Promise<void>((resolve, reject) => {
      this.ws.once('open', () => resolve());
      this.ws.once('error', reject);
    });
  }

  send(payload: Record<string, unknown>): void {
    this.ws.send(JSON.stringify(payload));
  }

  async wait(type: string, timeoutMs = 2500): Promise<Record<string, unknown>> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const idx = this.inbox.findIndex((msg) => msg['t'] === type);
      if (idx >= 0) {
        return this.inbox.splice(idx, 1)[0]!;
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error(`Timed out waiting for ${type}. Inbox: ${JSON.stringify(this.inbox)}`);
  }

  close(): void {
    this.ws.close();
  }
}

let child: ChildProcess;

before(async () => {
  child = spawn(process.execPath, ['--import', 'tsx', path.join(HERE, 'index.ts')], {
    cwd: path.join(HERE, '..'),
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let ready = false;
  const onOut = (buf: Buffer) => {
    if (String(buf).includes('"event":"server_start"')) {
      ready = true;
    }
  };
  child.stdout?.on('data', onOut);
  child.stderr?.on('data', onOut);
  const start = Date.now();
  while (!ready && Date.now() - start < 8000) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (!ready) {
    throw new Error('Server did not start');
  }
});

after(() => {
  child?.kill('SIGTERM');
});

describe('websocket protocol', () => {
  it('serves /health', async () => {
    const res = await fetch(`http://127.0.0.1:${PORT}/health`);
    assert.equal(res.status, 200);
    const body = (await res.json()) as { status: string };
    assert.equal(body.status, 'ok');
  });

  it('welcomes a client and runs create, join, course vote, and ball sync', async () => {
    const host = new Client();
    const guest = new Client();
    await host.open();
    await guest.open();

    const welcome = await host.wait('welcome');
    assert.equal(typeof welcome['playerId'], 'string');
    await host.wait('lobby_list');
    await guest.wait('welcome');
    await guest.wait('lobby_list');

    host.send({ t: 'create', name: 'Test Lobby', isPublic: true, playerName: 'Host' });
    const created = await host.wait('lobby_state');
    assert.equal(created['hostId'], welcome['playerId']);
    assert.equal((created['players'] as unknown[]).length, 1);
    const code = String(created['code']);
    assert.equal(code.length, 4);

    const listed = await guest.wait('lobby_list');
    const publicRooms = listed['rooms'] as Array<{ code: string }>;
    assert.ok(publicRooms.some((room) => room.code === code));

    guest.send({ t: 'join', code, playerName: 'Guest' });
    const hostState = await host.wait('lobby_state');
    const guestState = await guest.wait('lobby_state');
    assert.equal((hostState['players'] as unknown[]).length, 2);
    assert.equal((guestState['players'] as unknown[]).length, 2);

    guest.send({ t: 'start', mapId: 'rainbow_stairs' });
    const denied = await guest.wait('error');
    assert.equal(denied['code'], 'START_FAILED');

    guest.send({ t: 'select' });
    const guestSelectDenied = await guest.wait('error');
    assert.equal(guestSelectDenied['code'], 'START_FAILED');

    host.send({ t: 'select' });
    const hostVote = await host.wait('vote_state');
    const guestVote = await guest.wait('vote_state');
    assert.equal(typeof hostVote['deadline'], 'number');
    assert.ok((hostVote['deadline'] as number) > Date.now());
    assert.deepEqual(guestVote['counts'], {
      rainbow_stairs: 0,
      main_walk: 0,
      village_green: 0,
    });

    guest.send({ t: 'vote', mapId: 'main_walk' });
    await host.wait('vote_state');
    const afterGuest = await guest.wait('vote_state');
    assert.equal((afterGuest['counts'] as Record<string, number>)['main_walk'], 1);

    host.send({ t: 'vote', mapId: 'village_green' });
    await host.wait('vote_state');
    await guest.wait('vote_state');

    guest.send({ t: 'quick_start' });
    const guestQuickDenied = await guest.wait('error');
    assert.equal(guestQuickDenied['code'], 'START_FAILED');

    host.send({ t: 'quick_start' });
    const hostStart = await host.wait('match_start');
    const guestStart = await guest.wait('match_start');
    assert.equal(hostStart['mapId'], 'village_green');
    assert.equal(guestStart['mapId'], 'village_green');

    host.send({ t: 'ball_state', x: 2.5, y: 0.2, z: -6, vx: 0, vy: 0, vz: 0, atRest: true });
    const snap = await guest.wait('snapshot');
    const balls = snap['balls'] as Array<{ id: string; x: number }>;
    assert.ok(balls.some((ball) => ball.x === 2.5));

    host.send({ t: 'shot' });
    const stroke = await guest.wait('stroke_update');
    assert.equal(stroke['strokes'], 1);

    guest.send({ t: 'chat', text: 'nice putt' });
    const hostChat = await host.wait('chat');
    const guestChat = await guest.wait('chat');
    assert.equal(hostChat['text'], 'nice putt');
    assert.equal(guestChat['kind'], 'say');

    guest.send({ t: 'leave' });
    const leftChat = await host.wait('chat');
    assert.equal(leftChat['kind'], 'system');
    assert.match(String(leftChat['text']), /left/);

    host.close();
    guest.close();
  });

  it('rejects a bad join code', async () => {
    const client = new Client();
    await client.open();
    await client.wait('welcome');
    await client.wait('lobby_list');
    client.send({ t: 'join', code: 'NOPE', playerName: 'Ghost' });
    const err = await client.wait('error');
    assert.equal(err['code'], 'JOIN_FAILED');
    client.close();
  });
});
