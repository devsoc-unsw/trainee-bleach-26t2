import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { WebSocket } from 'ws';
import * as phone from './phone.js';

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
  phone.resetForTests();
  delete process.env['PUTT_PHONE_HOST'];
});

describe('phone remote', () => {
  it('pairs a phone and forwards a swing to the PC', async () => {
    const pc = fakeSocket();
    const handset = fakeSocket();
    const opened = await phone.openPair(pc.ws, 8080);
    assert.equal(opened.code.length, 4);
    assert.ok(opened.urls.some((url) => url.includes(`/remote?c=${opened.code}`)));
    assert.match(opened.qr, /^data:image\/png;base64,/);

    const linked = phone.linkPhone(handset.ws, opened.code);
    assert.notEqual(typeof linked, 'string');
    assert.equal(handset.sent.at(-1)?.['t'], 'phone_ok');
    assert.equal(pc.sent.at(-1)?.['t'], 'phone_linked');

    const swung = phone.swingFrom(handset.ws, 0.7);
    assert.notEqual(typeof swung, 'string');
    const hit = pc.sent.at(-1);
    assert.equal(hit?.['t'], 'phone_hit');
    assert.equal(hit?.['power'], 0.7);
  });

  it('rejects a bad code and a weak swing', async () => {
    const pc = fakeSocket();
    const handset = fakeSocket();
    await phone.openPair(pc.ws, 8080);
    assert.equal(typeof phone.linkPhone(handset.ws, 'NOPE'), 'string');
    assert.equal(typeof phone.swingFrom(handset.ws, 0.8), 'string');
  });

  it('prefers PUTT_PHONE_HOST for pair links', async () => {
    process.env['PUTT_PHONE_HOST'] = '10.0.0.9';
    const pc = fakeSocket();
    const opened = await phone.openPair(pc.ws, 8080);
    assert.equal(opened.urls[0], `https://10.0.0.9:8080/remote?c=${opened.code}`);
    delete process.env['PUTT_PHONE_HOST'];
  });

  it('keeps each phone on its own player ball', async () => {
    const host = fakeSocket();
    const guest = fakeSocket();
    const hostPhone = fakeSocket();
    const guestPhone = fakeSocket();
    const hostPair = await phone.openPair(host.ws, 8080);
    const guestPair = await phone.openPair(guest.ws, 8080);
    assert.notEqual(hostPair.code, guestPair.code);
    phone.linkPhone(hostPhone.ws, hostPair.code);
    phone.linkPhone(guestPhone.ws, guestPair.code);
    phone.swingFrom(hostPhone.ws, 0.8, { sx: -0.4, sy: 0.9 });
    phone.poseFrom(guestPhone.ws, { sx: 0.5, sy: 0.2, h: 1, p: 0.4 });
    const hostHit = host.sent.filter((m) => m['t'] === 'phone_hit');
    const guestHit = guest.sent.filter((m) => m['t'] === 'phone_hit');
    const guestPose = guest.sent.filter((m) => m['t'] === 'phone_pose');
    const hostPose = host.sent.filter((m) => m['t'] === 'phone_pose');
    assert.equal(hostHit.length, 1);
    assert.equal(hostHit[0]?.['sx'], -0.4);
    assert.equal(guestHit.length, 0);
    assert.equal(guestPose.length, 1);
    assert.equal(hostPose.length, 0);
  });

  it('reads Windows IPv4 addresses from ipconfig text', () => {
    const text = [
      'Wireless LAN adapter Wi-Fi:',
      '   IPv4 Address. . . . . . . . . . . : 192.168.1.42',
      '   Subnet Mask . . . . . . . . . . . : 255.255.255.0',
      '   Default Gateway . . . . . . . . . : 192.168.1.1',
    ].join('\n');
    assert.deepEqual(phone.parseIpconfig(text), ['192.168.1.42']);
  });
});
