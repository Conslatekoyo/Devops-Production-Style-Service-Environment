import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.PORT = '13002';
process.env.BIND_HOST = '127.0.0.1';
process.env.SERVICE_C_URL = 'http://127.0.0.1:19999';

const { default: app } = await import('./index.js');
const BASE = 'http://127.0.0.1:13002';

describe('service-b', () => {
  after(() => app.close?.() ?? process.exit(0));

  it('GET /health returns degraded when service-c is unreachable', async () => {
  const res = await fetch(`${BASE}/health`);

  assert.equal(res.status, 207);

  const body = await res.json();

  assert.equal(body.service, 'service-b');
  assert.equal(body.status, 'degraded');
  assert.equal(body.dependencies['service-c'], 'unreachable');
});

  it('GET /metrics returns Prometheus exposition format', async () => {
    const res = await fetch(`${BASE}/metrics`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /text\/plain/);
    const body = await res.text();
    assert.match(body, /# TYPE http_requests_total counter/);
    assert.match(body, /service_up\{service="service-b"\} 1/);
  });

  it('POST /greet returns 502 when service-c is unreachable', async () => {
    const res = await fetch(`${BASE}/greet`, {
      method: 'POST',
      headers: { 'X-Request-ID': 'test-b-001' }
    });
    assert.equal(res.status, 502);
  });

  it('Unknown route returns 404', async () => {
    const res = await fetch(`${BASE}/nothing`);
    assert.equal(res.status, 404);
  });
});
