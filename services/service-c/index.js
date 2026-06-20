const express = require('express');

const app = express();
const PORT = 3003;
const SERVICE_NAME = 'service-c';
const SERVICE_A_URL = process.env.SERVICE_A_URL || 'http://service-a.internal:3001';
const startTime = Date.now();

const metrics = {
  requests_total: 0,
  requests_success: 0,
  requests_failed: 0,
  callbacks_sent: 0,
  callbacks_failed: 0,
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

function log(entry) {
  const record = { timestamp: new Date().toISOString(), service: SERVICE_NAME, ...entry };
  process.stdout.write(JSON.stringify(record) + '\n');
}

app.use(express.json());

app.get('/health', (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  log({ event: 'health_check', request_id: requestId, method: 'GET', path: '/health', status: 200 });
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
    callbacks_sent: metrics.callbacks_sent,
    callbacks_failed: metrics.callbacks_failed,
    status_codes: metrics.status_codes,
    avg_response_time_ms: metrics.avg_response_time_ms
  });
});

app.get('/greet-c', async (req, res) => {
  const reqStart = Date.now();
  const requestId = req.headers['x-request-id'] || 'none';
  metrics.requests_total++;
  log({ event: 'request_received', request_id: requestId, method: 'GET', path: '/greet-c', source: 'service-b' });

  let callbackSent = false;
  try {
    const callbackPayload = {
      request_id: requestId,
      source_service: SERVICE_NAME,
      message: 'Greeting processed',
      timestamp: new Date().toISOString()
    };

    const cbResponse = await fetch(`${SERVICE_A_URL}/greeting-rcvd`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Request-ID': requestId },
      body: JSON.stringify(callbackPayload)
    });

    callbackSent = cbResponse.ok;
    metrics.callbacks_sent++;
    metrics.requests_success++;
    trackStatus(200);
    trackResponseTime(Date.now() - reqStart);
    log({
      event: 'callback_sent',
      request_id: requestId,
      target: 'service-a',
      endpoint: '/greeting-rcvd',
      status: cbResponse.status
    });
  } catch (err) {
    metrics.callbacks_failed++;
    metrics.requests_failed++;
    trackStatus(502);
    trackResponseTime(Date.now() - reqStart);
    log({ event: 'callback_failed', request_id: requestId, target: 'service-a', error: err.message, status: 502 });
  }

  res.json({ request_id: requestId, status: 'processed', callback_sent: callbackSent });
});

app.use((req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  metrics.requests_total++;
  metrics.requests_failed++;
  trackStatus(404);
  log({ event: 'route_not_found', request_id: requestId, method: req.method, path: req.path, status: 404 });
  res.status(404).json({ error: 'Not found', path: req.path });
});

app.listen(PORT, '0.0.0.0', () => {
  log({ event: 'server_started', message: `${SERVICE_NAME} listening on port ${PORT}`, port: PORT });
});
