import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';

// Set env before importing app
process.env.PORT = '13001';
process.env.BIND_HOST = '127.0.0.1';
process.env.SERVICE_B_URL = 'http://127.0.0.1:19999'; // nothing listening = fast fail

const { default: app } = await import('./index.js');

const BASE = 'http://127.0.0.1:13001';

describe('service-a', () => {
  after(() => app.close?.() ?? process.exit(0));

  it('GET /health returns 200 with correct body', async () => {
    const res = await fetch(`${BASE}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.service, 'service-a');
    assert.equal(body.status, 'healthy');
    assert.ok(body.port);
  });

  it('GET /metrics returns Prometheus exposition format', async () => {
    const res = await fetch(`${BASE}/metrics`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /text\/plain/);
    const body = await res.text();
    assert.match(body, /# TYPE http_requests_total counter/);
    assert.match(body, /# TYPE http_errors_total counter/);
    assert.match(body, /# TYPE http_request_duration_seconds histogram/);
    assert.match(body, /service_up\{service="service-a"\} 1/);
  });

  it('POST /greet-service-b returns 502 when service-b is unreachable', async () => {
    const res = await fetch(`${BASE}/greet-service-b`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Request-ID': 'test-fail-001' }
    });
    assert.equal(res.status, 502);
    const body = await res.json();
    assert.equal(body.status, 'error');
    assert.ok(body.message.includes('service-b'));
  });

  it('POST /greeting-rcvd returns 200', async () => {
    const res = await fetch(`${BASE}/greeting-rcvd`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ request_id: 'test-cb-001', source_service: 'service-c' })
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
