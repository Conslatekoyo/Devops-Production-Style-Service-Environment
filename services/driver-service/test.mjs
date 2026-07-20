import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.PORT = '13002';
process.env.BIND_HOST = '127.0.0.1';
process.env.SERVICE_C_URL = 'http://127.0.0.1:19999';

const { default: app } = await import('./index.js');
const BASE = 'http://127.0.0.1:13002';

describe('driver-service', () => {
  after(() => app.close?.() ?? process.exit(0));

  it('GET /health returns 200 with correct body', async () => {
    const res = await fetch(`${BASE}/health`);
    assert.ok(res.status === 200 || res.status === 207);
    const body = await res.json();
    assert.equal(body.service, 'driver-service');
    assert.ok(body.status === 'healthy' || body.status === 'degraded');
  });

  it('GET /metrics returns Prometheus exposition format', async () => {
    const res = await fetch(`${BASE}/metrics`);
    assert.ok(res.status === 200 || res.status === 207);
    const text = await res.text();
    assert.ok(text.includes('http_requests_total'));
    assert.ok(text.includes('service_up'));
  });

  it('POST /assign-driver returns 502 when tracking-service is unreachable', async () => {
    const res = await fetch(`${BASE}/assign-driver`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Request-ID': 'test-b-001' },
      body: JSON.stringify({ pickup: 'Westlands', dropoff: 'CBD' })
    });
    assert.equal(res.status, 502);
  });

  it('Unknown route returns 404', async () => {
    const res = await fetch(`${BASE}/nothing`);
    assert.equal(res.status, 404);
  });
});
