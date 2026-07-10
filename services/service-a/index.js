'use strict';
require('./tracer');

const express = require('express');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3001;
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const SERVICE_NAME = 'service-a';
const SERVICE_B_URL = process.env.SERVICE_B_URL || 'http://service-b.internal:3002';

const pendingCallbacks = new Map();
const CALLBACK_TIMEOUT_MS = 10000;
const startTime = Date.now();

const metrics = {
  requests_total: 0,
  requests_success: 0,
  requests_failed: 0,
  callbacks_received: 0,
  callbacks_timeout: 0,
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

// Advanced health check with dependency checking
app.get('/health', async (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  let serviceBStatus = 'ok';

  try {
    const response = await fetch(`${SERVICE_B_URL}/health`, {
      signal: AbortSignal.timeout(2000)
    });
    if (!response.ok) serviceBStatus = 'degraded';
  } catch {
    serviceBStatus = 'unreachable';
  }

  const overallStatus = serviceBStatus === 'ok' ? 'healthy' : 'degraded';
  const httpStatus = overallStatus === 'healthy' ? 200 : 207;

  log({
    event: 'health_check',
    request_id: requestId,
    method: 'GET',
    path: '/health',
    status: httpStatus,
    client_ip: clientIp(req),
    dependencies: { 'service-b': serviceBStatus }
  });

  res.status(httpStatus).json({
    service: SERVICE_NAME,
    status: overallStatus,
    port: PORT,
    message: `Hello ${SERVICE_NAME} listening on ${PORT}`,
    dependencies: {
      'service-b': serviceBStatus
    }
  });
});

app.get('/metrics', (req, res) => {
  res.json({
    service: SERVICE_NAME,
    uptime_seconds: Math.floor((Date.now() - startTime) / 1000),
    requests_total: metrics.requests_total,
    requests_success: metrics.requests_success,
    requests_failed: metrics.requests_failed,
    callbacks_received: metrics.callbacks_received,
    callbacks_timeout: metrics.callbacks_timeout,
    status_codes: metrics.status_codes,
    avg_response_time_ms: metrics.avg_response_time_ms,
    pending_callbacks: pendingCallbacks.size
  });
});

// Controlled failure endpoints for observability testing
app.get('/slow', async (req, res) => {
  const delay = parseInt(req.query.ms) || 3000;
  log({ event: 'slow_endpoint', delay_ms: delay, note: 'lab-only test endpoint' });
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ service: SERVICE_NAME, status: 'ok', delay_ms: delay, note: 'lab-only' });
});

app.get('/fail', (req, res) => {
  log({ event: 'fail_endpoint', status: 500, note: 'lab-only test endpoint' });
  res.status(500).json({ service: SERVICE_NAME, status: 'error', message: 'Simulated failure', note: 'lab-only' });
});

app.post('/greet-service-b', async (req, res) => {
  const reqStart = Date.now();
  const requestId = req.headers['x-request-id'] || crypto.randomUUID();
  const ip = clientIp(req);
  metrics.requests_total++;
  log({ event: 'request_received', request_id: requestId, method: 'POST', path: '/greet-service-b', client_ip: ip });

  const callbackPromise = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pendingCallbacks.delete(requestId);
      reject(new Error('callback_timeout'));
    }, CALLBACK_TIMEOUT_MS);
    pendingCallbacks.set(requestId, { resolve, timeout });
  });

  try {
    const response = await fetch(`${SERVICE_B_URL}/greet`, {
      method: 'POST',
      headers: { 'X-Request-ID': requestId }
    });
    await response.json();
    log({ event: 'request_forwarded', request_id: requestId, target: 'service-b', status: response.status });
  } catch (err) {
    const pending = pendingCallbacks.get(requestId);
    if (pending) { clearTimeout(pending.timeout); pendingCallbacks.delete(requestId); }
    metrics.requests_failed++;
    trackStatus(502);
    trackResponseTime(Date.now() - reqStart);
    log({ event: 'request_failed', request_id: requestId, path: '/greet-service-b', status: 502, error: err.message });
    return res.status(502).json({ request_id: requestId, status: 'error', message: 'Failed to reach service-b' });
  }

  try {
    const callbackData = await callbackPromise;
    metrics.requests_success++;
    metrics.callbacks_received++;
    trackStatus(200);
    trackResponseTime(Date.now() - reqStart);
    log({ event: 'callback_received', request_id: requestId, source_service: callbackData.source_service, status: 200 });
    res.json({ request_id: requestId, status: 'success', message: 'Request completed successfully' });
  } catch (err) {
    metrics.requests_failed++;
    metrics.callbacks_timeout++;
    trackStatus(504);
    trackResponseTime(Date.now() - reqStart);
    log({ event: 'callback_timeout', request_id: requestId, status: 504, error: err.message });
    res.status(504).json({ request_id: requestId, status: 'error', message: 'Callback timeout from service-c' });
  }
});

app.post('/greeting-rcvd', (req, res) => {
  const body = req.body;
  const requestId = body.request_id || req.headers['x-request-id'] || 'none';
  log({ event: 'callback_received', request_id: requestId, source_service: body.source_service, method: 'POST', path: '/greeting-rcvd', status: 200, client_ip: clientIp(req) });
  const pending = pendingCallbacks.get(requestId);
  if (pending) { clearTimeout(pending.timeout); pendingCallbacks.delete(requestId); pending.resolve(body); }
  res.json({ status: 'received' });
});

app.use((req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  metrics.requests_total++;
  metrics.requests_failed++;
  trackStatus(404);
  log({ event: 'route_not_found', request_id: requestId, method: req.method, path: req.path, status: 404, client_ip: clientIp(req) });
  res.status(404).json({ error: 'Not found', path: req.path });
});

const server = app.listen(PORT, BIND_HOST, () => {
  log({ event: 'server_started', message: `${SERVICE_NAME} listening on ${BIND_HOST}:${PORT}`, port: PORT, bind_host: BIND_HOST });
});

module.exports = server;
