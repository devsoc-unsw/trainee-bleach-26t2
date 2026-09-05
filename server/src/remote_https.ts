import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as phone from './phone.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CERT_DIR = path.resolve(HERE, '../certs');
const REMOTE_HTML = path.resolve(HERE, '../../client/ui/phone_remote.html');
const GODOT_PHONE = (process.env['PUTT_GODOT_PHONE'] ?? '127.0.0.1:27351').trim();

export function httpsPort(httpPort: number): number {
  const forced = parseInt(process.env['HTTPS_PORT'] ?? '', 10);
  if (Number.isFinite(forced) && forced > 0) {
    return forced;
  }
  return httpPort;
}

export function remotePageUrls(port: number): string[] {
  const forced = (process.env['PUTT_PHONE_HOST'] ?? '').trim();
  if (forced) {
    const host = forced.replace(/^https?:\/\//i, '').replace(/\/.*$/, '').replace(/:\d+$/, '');
    return [`https://${host}:${port}/remote`];
  }
  const hosts = phone.discoverPhoneHosts();
  const urls = hosts.slice(0, 1).map((host) => `https://${host}:${port}/remote`);
  if (urls.length === 0) {
    urls.push(`https://127.0.0.1:${port}/remote`);
  }
  return urls;
}

export function remoteInfo(port: number): { urls: string[]; local: string } {
  return {
    urls: remotePageUrls(port),
    local: `https://127.0.0.1:${port}/remote`,
  };
}

export function createHttpsServer(): https.Server | null {
  const keyPath = path.join(CERT_DIR, 'remote-key.pem');
  const certPath = path.join(CERT_DIR, 'remote-cert.pem');
  if (!fs.existsSync(keyPath) || !fs.existsSync(certPath)) {
    return null;
  }
  return https.createServer(
    {
      key: fs.readFileSync(keyPath),
      cert: fs.readFileSync(certPath),
    },
    handleRemote
  );
}

export function tryPhoneApi(req: http.IncomingMessage, res: http.ServerResponse): boolean {
  const url = new URL(req.url ?? '/', 'https://localhost');
  const pathName = url.pathname;
  if (req.method === 'OPTIONS' && (pathName === '/pose' || pathName === '/hit' || pathName === '/swing' || pathName === '/power')) {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*' });
    res.end();
    return true;
  }
  if (req.method === 'POST' && (pathName === '/pose' || pathName === '/hit' || pathName === '/swing' || pathName === '/power')) {
    proxyGodot(req, res, pathName);
    return true;
  }
  return false;
}

function handleRemote(req: http.IncomingMessage, res: http.ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 'no-store');
  if (tryPhoneApi(req, res)) {
    return;
  }
  const url = new URL(req.url ?? '/', 'https://localhost');
  const pathName = url.pathname;
  if ((req.method === 'GET' || req.method === 'HEAD') && (pathName === '/' || pathName === '/index.html' || pathName === '/remote' || pathName === '/remote/')) {
    if (!fs.existsSync(REMOTE_HTML)) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('phone remote missing');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    fs.createReadStream(REMOTE_HTML).pipe(res);
    return;
  }
  if (req.method === 'GET' && pathName === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', remote: true }));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('not found');
}

function proxyGodot(req: http.IncomingMessage, res: http.ServerResponse, pathName: string): void {
  const chunks: Buffer[] = [];
  req.on('data', (chunk) => {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  });
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const [host, portText] = GODOT_PHONE.split(':');
    const fwd = http.request(
      {
        host: host || '127.0.0.1',
        port: parseInt(portText || '27351', 10),
        path: pathName,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': body.length,
        },
      },
      (gres) => {
        const bits: Buffer[] = [];
        gres.on('data', (chunk) => {
          bits.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        });
        gres.on('end', () => {
          res.writeHead(gres.statusCode ?? 502, {
            'Content-Type': gres.headers['content-type'] ?? 'application/json',
            'Access-Control-Allow-Origin': '*',
          });
          res.end(Buffer.concat(bits));
        });
      }
    );
    fwd.on('error', () => {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: 'game_not_running' }));
    });
    fwd.end(body);
  });
}
