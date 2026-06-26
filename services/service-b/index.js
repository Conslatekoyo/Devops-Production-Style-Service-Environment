const express = require('express');

const app = express();
const PORT = process.env.PORT || 3002;
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const SERVICE_NAME = 'service-b';
const SERVICE_C_URL = process.env.SERVICE_C_URL || 'http://service-c.internal:3003';
const startTime = Date.now();

const metrics = {
  requests_total: 0,
  requests_success: 0,
  requests_failed: 0,
  forwards_to_c: 0,
  status_codes: {},
  avg_response_time_ms: 0,
  _response_times: []
};

function trackResponseTime(ms) {
  metrics._response_times.push(ms);
  if (metrics._response_times.length > 1000) metrics._response_times.shift();
  metrics.avg_response_time_ms = Math.round(
    metrics._response_times.reduce((a, b) => a + b, 0) / metrics._response_times.length
  );
}

function trackStatus(code) {
  metrics.status_codes[code] = (metrics.status_codes[code] || 0) + 1;
}

function clientIp(req) {
  return req.headers['x-real-ip'] || req.headers['x-forwarded-for'] || req.ip || req.socket.remoteAddress;
}

function log(entry) {
  const record = { timestamp: new Date().toISOString(), service: SERVICE_NAME, ...entry };
  process.stdout.write(JSON.stringify(record) + '\n');
}

app.use(express.json());

app.get('/health', (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  log({ event: 'health_check', request_id: requestId, method: 'GET', path: '/health', status: 200, client_ip: clientIp(req) });
  res.json({
    service: SERVICE_NAME,
    status: 'healthy',
    port: PORT,
    message: `Hello ${SERVICE_NAME} listening on ${PORT}`
  });
});

app.get('/metrics', (req, res) => {
  res.json({
    service: SERVICE_NAME,
    uptime_seconds: Math.floor((Date.now() - startTime) / 1000),
    requests_total: metrics.requests_total,
    requests_success: metrics.requests_success,
    requests_failed: metrics.requests_failed,
    forwards_to_c: metrics.forwards_to_c,
    status_codes: metrics.status_codes,
    avg_response_time_ms: metrics.avg_response_time_ms
  });
});

// POST: mirrors service-a's /greet-service-b contract — this call forwards to
// service-c and causes a downstream callback, so it is not a side-effect-free GET.
app.post('/greet', async (req, res) => {
  const reqStart = Date.now();
  const requestId = req.headers['x-request-id'] || 'none';
  metrics.requests_total++;
  log({ event: 'request_received', request_id: requestId, method: 'POST', path: '/greet', source: 'service-a', client_ip: clientIp(req) });

  try {
    const response = await fetch(`${SERVICE_C_URL}/greet-c`, {
      method: 'POST',
      headers: { 'X-Request-ID': requestId }
    });
    await response.json();
    metrics.requests_success++;
    metrics.forwards_to_c++;
    trackStatus(response.status);
    trackResponseTime(Date.now() - reqStart);
    log({ event: 'request_forwarded', request_id: requestId, target: 'service-c', status: response.status });
    res.json({ request_id: requestId, status: 'forwarded', target: 'service-c' });
  } catch (err) {
    metrics.requests_failed++;
    trackStatus(502);
    trackResponseTime(Date.now() - reqStart);
    log({ event: 'request_failed', request_id: requestId, path: '/greet', status: 502, error: err.message });
    res.status(502).json({ request_id: requestId, status: 'error', message: 'Failed to reach service-c' });
  }
});

app.use((req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  metrics.requests_total++;
  metrics.requests_failed++;
  trackStatus(404);
  log({ event: 'route_not_found', request_id: requestId, method: req.method, path: req.path, status: 404, client_ip: clientIp(req) });
  res.status(404).json({ error: 'Not found', path: req.path });
});

app.listen(PORT, BIND_HOST, () => {
  log({ event: 'server_started', message: `${SERVICE_NAME} listening on ${BIND_HOST}:${PORT}`, port: PORT, bind_host: BIND_HOST });
});
