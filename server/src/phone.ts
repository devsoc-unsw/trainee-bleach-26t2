import { execFileSync } from 'node:child_process';
import os from 'node:os';
import QRCode from 'qrcode';
import type { WebSocket } from 'ws';

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
let preferredHosts: string[] = [];

interface Pair {
  code: string;
  playerWs: WebSocket;
  phoneWs?: WebSocket;
}

const pairs = new Map<string, Pair>();
const pairByPlayer = new Map<WebSocket, Pair>();
const pairByPhone = new Map<WebSocket, Pair>();

export function resetForTests(): void {
  pairs.clear();
  pairByPlayer.clear();
  pairByPhone.clear();
  preferredHosts = [];
}

export function isPhoneSocket(ws: WebSocket): boolean {
  return pairByPhone.has(ws);
}

export function setPreferredHosts(hosts: string[]): void {
  preferredHosts = unique(hosts.filter((host) => isLanIpv4(host)));
}

export function discoverPhoneHosts(): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  const add = (ip: string) => {
    if (!isLanIpv4(ip) || seen.has(ip)) {
      return;
    }
    seen.add(ip);
    out.push(ip);
  };
  for (const ip of windowsLanIps()) {
    add(ip);
  }
  for (const ip of nodeLanIps()) {
    add(ip);
  }
  out.sort((a, b) => rankIp(a) - rankIp(b));
  return out;
}

export function trySharePortOnWindows(port: number): string {
  try {
    execFileSync(
      'netsh.exe',
      [
        'interface',
        'portproxy',
        'add',
        'v4tov4',
        `listenport=${port}`,
        'listenaddress=0.0.0.0',
        `connectport=${port}`,
        'connectaddress=127.0.0.1',
      ],
      { encoding: 'utf8', timeout: 2500, windowsHide: true }
    );
    return 'portproxy';
  } catch {
    return '';
  }
}

export function phonePageUrls(port: number): string[] {
  const forced = (process.env['PUTT_PHONE_HOST'] ?? '').trim();
  if (forced) {
    return [`http://${hostWithPort(forced, port)}/phone`];
  }
  const hosts = preferredHosts.length > 0 ? preferredHosts : nodeLanIps();
  const urls = hosts.map((host) => `http://${host}:${port}/phone`);
  if (urls.length === 0) {
    urls.push(`http://127.0.0.1:${port}/phone`);
  }
  return unique(urls);
}

export function pairLinks(port: number, code: string): string[] {
  const query = `?c=${encodeURIComponent(code)}`;
  const urls: string[] = [];
  for (const page of phonePageUrls(port)) {
    const remote = page.replace(/\/phone\/?$/, '/remote');
    urls.push(`${remote.replace(/^http:/, 'https:')}${query}`);
    urls.push(`${remote}${query}`);
  }
  return unique(urls);
}

export async function openPair(
  playerWs: WebSocket,
  port: number
): Promise<{ code: string; urls: string[]; qr: string }> {
  const existing = pairByPlayer.get(playerWs);
  const code = existing?.code ?? freshCode();
  if (!existing) {
    const pair: Pair = { code, playerWs };
    pairs.set(code, pair);
    pairByPlayer.set(playerWs, pair);
  }
  const urls = pairLinks(port, code);
  const target = urls[0] ?? `http://127.0.0.1:${port}/phone?c=${code}`;
  let qr = '';
  try {
    qr = await QRCode.toDataURL(target, {
      margin: 1,
      width: 280,
      color: { dark: '#3a322c', light: '#f6f1e6' },
    });
  } catch {
    qr = '';
  }
  return { code, urls, qr };
}

export function qrTarget(raw: string | null): string | null {
  if (!raw || raw.length > 400) {
    return null;
  }
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}

export async function pngForUrl(target: string): Promise<Buffer> {
  return QRCode.toBuffer(target, {
    type: 'png',
    margin: 1,
    width: 280,
    color: { dark: '#3a322c', light: '#f6f1e6' },
  });
}

export function linkPhone(phoneWs: WebSocket, raw: string): Pair | string {
  const code = raw.replace(/\s+/g, '').toUpperCase();
  const pair = pairs.get(code);
  if (!pair) {
    return 'That code is not waiting for a phone';
  }
  if (pair.playerWs === phoneWs) {
    return 'Open this page on your phone, not the game PC';
  }
  if (pair.phoneWs && pair.phoneWs !== phoneWs) {
    pairByPhone.delete(pair.phoneWs);
    send(pair.phoneWs, { t: 'phone_gone' });
  }
  const old = pairByPhone.get(phoneWs);
  if (old && old !== pair) {
    old.phoneWs = undefined;
    pairByPhone.delete(phoneWs);
  }
  pair.phoneWs = phoneWs;
  pairByPhone.set(phoneWs, pair);
  send(phoneWs, { t: 'phone_ok', code: pair.code });
  send(pair.playerWs, { t: 'phone_linked' });
  return pair;
}

export function swingFrom(phoneWs: WebSocket, raw: unknown, extra: Record<string, unknown> = {}): Pair | string {
  const pair = pairByPhone.get(phoneWs);
  if (!pair) {
    return 'Link a code first';
  }
  const power = clampPower(raw);
  if (power < 0.05) {
    return 'Swing a bit harder';
  }
  send(pair.playerWs, {
    t: 'phone_hit',
    power,
    sx: clampAxis(extra['sx']),
    sy: clampAxis(extra['sy']),
  });
  return pair;
}

export function poseFrom(phoneWs: WebSocket, data: Record<string, unknown>): Pair | string {
  const pair = pairByPhone.get(phoneWs);
  if (!pair) {
    return 'Link a code first';
  }
  send(pair.playerWs, {
    t: 'phone_pose',
    b: Number(data['b'] ?? 75),
    g: Number(data['g'] ?? 0),
    h: Number(data['h'] ?? 0),
    sx: clampAxis(data['sx']),
    sy: clampAxis(data['sy']),
    p: clampPower(data['p'] ?? data['power'] ?? 0),
    u: Number(data['u'] ?? 0),
    a: Number(data['a'] ?? 0),
    al: Number(data['al'] ?? 0),
    c: Number(data['c'] ?? 0),
    lx: clampAxis(data['lx']),
    ly: clampAxis(data['ly']),
  });
  return pair;
}

export function powerFrom(phoneWs: WebSocket, raw: unknown): Pair | string {
  const pair = pairByPhone.get(phoneWs);
  if (!pair) {
    return 'Link a code first';
  }
  const kind = String(raw ?? '');
  if (kind !== 'shield' && kind !== 'shrink') {
    return 'Unknown power';
  }
  send(pair.playerWs, { t: 'phone_power', kind });
  return pair;
}

export function typeFrom(phoneWs: WebSocket, data: Record<string, unknown>): Pair | string {
  const pair = pairByPhone.get(phoneWs);
  if (!pair) {
    return 'Link a code first';
  }
  send(pair.playerWs, {
    t: 'phone_type',
    text: String(data['text'] ?? ''),
    done: Boolean(data['done']),
    close: Boolean(data['close']),
  });
  return pair;
}

export function forwardType(playerWs: WebSocket, data: Record<string, unknown>): Pair | string {
  const pair = pairByPlayer.get(playerWs);
  if (!pair) {
    return 'No phone pair';
  }
  if (pair.phoneWs) {
    send(pair.phoneWs, {
      t: 'phone_type',
      typeOn: Boolean(data['typeOn']),
      typeText: String(data['typeText'] ?? ''),
      typeHint: String(data['typeHint'] ?? ''),
      typeMax: Number(data['typeMax'] ?? 32),
    });
  }
  return pair;
}

export function forwardPowers(playerWs: WebSocket, data: Record<string, unknown>): Pair | string {
  const pair = pairByPlayer.get(playerWs);
  if (!pair) {
    return 'No phone pair';
  }
  if (pair.phoneWs) {
    send(pair.phoneWs, {
      t: 'phone_powers',
      leftKind: String(data['leftKind'] ?? ''),
      leftLeft: Number(data['leftLeft'] ?? 0),
      rightKind: String(data['rightKind'] ?? ''),
      rightLeft: Number(data['rightLeft'] ?? 0),
      rank: Number(data['rank'] ?? 0),
      rankText: String(data['rankText'] ?? ''),
    });
  }
  return pair;
}

export function detach(ws: WebSocket): void {
  const asPhone = pairByPhone.get(ws);
  if (asPhone) {
    pairByPhone.delete(ws);
    if (asPhone.phoneWs === ws) {
      asPhone.phoneWs = undefined;
    }
    send(asPhone.playerWs, { t: 'phone_gone' });
  }
  const asPlayer = pairByPlayer.get(ws);
  if (asPlayer) {
    pairByPlayer.delete(ws);
    pairs.delete(asPlayer.code);
    if (asPlayer.phoneWs) {
      pairByPhone.delete(asPlayer.phoneWs);
      send(asPlayer.phoneWs, { t: 'phone_gone' });
    }
  }
}

function clampPower(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    return 0;
  }
  return Math.min(1, Math.max(0, n));
}

function clampAxis(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    return 0;
  }
  return Math.min(1, Math.max(-1, n));
}

function freshCode(): string {
  for (let attempt = 0; attempt < 24; attempt++) {
    let code = '';
    for (let i = 0; i < 4; i++) {
      code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    }
    if (!pairs.has(code)) {
      return code;
    }
  }
  return `P${Date.now().toString(36).slice(-3).toUpperCase()}`;
}

function send(ws: WebSocket, payload: unknown): void {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}

function nodeLanIps(): string[] {
  const ips: string[] = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const entry of list ?? []) {
      const family = String(entry.family);
      if ((family === 'IPv4' || family === '4') && !entry.internal) {
        ips.push(entry.address);
      }
    }
  }
  return ips;
}

function windowsLanIps(): string[] {
  try {
    const out = execFileSync('ipconfig.exe', [], {
      encoding: 'utf8',
      timeout: 2000,
      windowsHide: true,
    });
    return parseIpconfig(out);
  } catch {
    return [];
  }
}

export function parseIpconfig(text: string): string[] {
  const ips: string[] = [];
  for (const line of text.split(/\r?\n/)) {
    if (!/IPv4 Address/i.test(line) && !/(^|[\s.])IP Address/i.test(line)) {
      continue;
    }
    if (/Gateway|DNS Servers|Subnet/i.test(line)) {
      continue;
    }
    const match = line.match(/\b(\d{1,3}(?:\.\d{1,3}){3})\b/);
    if (match && isLanIpv4(match[1])) {
      ips.push(match[1]);
    }
  }
  return unique(ips);
}

function isLanIpv4(ip: string): boolean {
  if (!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(ip)) {
    return false;
  }
  if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
    return false;
  }
  return ip.split('.').every((part) => Number(part) <= 255);
}

function rankIp(ip: string): number {
  if (ip.startsWith('192.168.')) {
    return 0;
  }
  if (ip.startsWith('10.')) {
    return 1;
  }
  return 2;
}

function hostWithPort(host: string, port: number): string {
  const trimmed = host.replace(/^https?:\/\//i, '').replace(/\/.*$/, '');
  if (/^\d+\.\d+\.\d+\.\d+:\d+$/.test(trimmed) || (/:\d+$/.test(trimmed) && trimmed.split(':').length === 2)) {
    return trimmed;
  }
  return `${trimmed}:${port}`;
}

function unique(items: string[]): string[] {
  return [...new Set(items)];
}
