import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.PORT = '13001';
process.env.BIND_HOST = '127.0.0.1';
process.env.SERVICE_B_URL = 'http://127.0.0.1:19999';

const { default: app } = await import('./index.js');
const BASE = 'http://127.0.0.1:13001';

describe('booking-service', () => {
  after(() => app.close?.() ?? process.exit(0));

  it('GET /health returns 200 or 207 with correct body', async () => {
    const res = await fetch(`${BASE}/health`);
    assert.ok(res.status === 200 || res.status === 207);
    const body = await res.json();
    assert.equal(body.service, 'booking-service');
    assert.ok(body.status === 'healthy' || body.status === 'degraded');
    assert.ok(body.dependencies);
  });

  it('GET /metrics returns Prometheus exposition format', async () => {
    const res = await fetch(`${BASE}/metrics`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.ok(text.includes('http_requests_total'));
    assert.ok(text.includes('service_up'));
  });

  it('POST /request-ride returns an error status when a dependency is unreachable', async () => {
    const res = await fetch(`${BASE}/request-ride`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Request-ID': 'test-fail-001' },
      body: JSON.stringify({ pickup: 'Westlands', dropoff: 'CBD' })
    });
    assert.ok(res.status === 502 || res.status === 500);
    const body = await res.json();
    assert.equal(body.status, 'error');
  });

  it('POST /ride-confirmed returns 200', async () => {
    const res = await fetch(`${BASE}/ride-confirmed`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ride_id: 'test-cb-001', driver: 'Brian', eta_minutes: 4, source_service: 'tracking-service' })
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.status, 'received');
  });

  it('Unknown route returns 404', async () => {
    const res = await fetch(`${BASE}/does-not-exist`);
    assert.equal(res.status, 404);
  });
});
