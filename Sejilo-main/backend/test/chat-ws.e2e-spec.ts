import * as http from 'http';
import { WebSocket } from 'ws';

/**
 * End-to-end test for the real-time chat WebSocket gateway.
 *
 * This targets the running backend at BASE (the same instance used for the
 * other live verifications). The in-process Nest WS gateway does not bind a
 * usable upgrade handler under the jest harness, so we exercise the real
 * gateway here. Requires the backend to be up (`docker compose up -d`).
 */

const BASE = process.env.SEJILO_TEST_BASE_URL || 'http://localhost:8080';

function httpReq(
  method: string,
  path: string,
  body?: unknown,
  token?: string,
): Promise<{ status: number; body: any }> {
  const url = new URL(BASE + path);
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = http.request(
      { host: url.hostname, port: url.port || 80, method, path: url.pathname, headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(data ? { 'content-length': Buffer.byteLength(data) } : {}),
      } },
      (res) => {
        let buf = '';
        res.on('data', (c) => (buf += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode ?? 0, body: buf ? JSON.parse(buf) : null });
          } catch {
            resolve({ status: res.statusCode ?? 0, body: buf });
          }
        });
      },
    );
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

function waitFor(ws: WebSocket, predicate: (m: any) => boolean, ms = 5000) {
  return new Promise<any>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('ws timeout')), ms);
    ws.on('message', (d) => {
      const m = JSON.parse(d.toString());
      if (predicate(m)) {
        clearTimeout(t);
        resolve(m);
      }
    });
    ws.on('error', (e) => {
      clearTimeout(t);
      reject(e);
    });
  });
}

describe('Chat WebSocket (e2e, live backend)', () => {
  let token: string;
  const stamp = Date.now();

  beforeAll(async () => {
    const reg = await httpReq('POST', '/v1/auth/register', {
      email: `ws18a_${stamp}@test.local`,
      password: 'Str0ngPass!2026',
      username: `ws18a_${stamp}`,
      displayName: 'WS',
    });
    expect(reg.status).toBe(201);
    token = reg.body.token as string;
  });

  it('connects (ready), responds to ping (pong), rejects bad token', async () => {
    const ws = new WebSocket(`${BASE.replace('http', 'ws')}/v1/chat/ws?token=${token}`);
    await new Promise<void>((res, rej) => {
      ws.on('open', () => res());
      ws.on('error', (e) => rej(e));
    });

    const ready = await waitFor(ws, (m) => m.type === 'ready');
    expect(ready.userId).toBeDefined();

    ws.send(JSON.stringify({ type: 'ping' }));
    const pong = await waitFor(ws, (m) => m.type === 'pong');
    expect(pong).toBeDefined();

    ws.close();

    const bad = new WebSocket(`${BASE.replace('http', 'ws')}/v1/chat/ws?token=garbage`);
    const code = await new Promise<number>((resolve) => {
      bad.on('close', (c) => resolve(c));
      bad.on('error', () => resolve(-1));
    });
    expect(code).toBe(1008);
  });
});
