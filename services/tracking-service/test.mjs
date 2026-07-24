import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.PORT = '13003';
process.env.BIND_HOST = '127.0.0.1';
process.env.SERVICE_A_URL = 'http://127.0.0.1:19999';

const { default: app } = await import('./index.js');
const BASE = 'http://127.0.0.1:13003';

describe('tracking-service', () => {
  after(() => app.close?.() ?? process.exit(0));

 it('GET /health returns 200 with correct body', async () => {
   const res = await fetch(`${BASE}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.service, 'tracking-service');
    assert.equal(body.status, 'healthy');
  });

  it('GET /metrics returns Prometheus exposition format', async () => {
    const res = await fetch(`${BASE}/metrics`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.ok(text.includes('http_requests_total'));
    assert.ok(text.includes('service_up'));
  });

  it('Unknown route returns 404', async () => {
    const res = await fetch(`${BASE}/nothing`);
    assert.equal(res.status, 404);
  });
});
