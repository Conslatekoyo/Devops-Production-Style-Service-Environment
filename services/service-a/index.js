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

const HISTOGRAM_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];

const promMetrics = {
  requestsTotal: new Map(),
  errorsTotal: new Map(),
  duration: new Map()
};

function labelKey(method, route, status) {
  return `${method}|${route}|${status}`;
}

function incCounter(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

function observeDuration(method, route, seconds) {
  const key = `${method}|${route}`;
  let entry = promMetrics.duration.get(key);
  if (!entry) {
    entry = { buckets: new Map(HISTOGRAM_BUCKETS.map((b) => [b, 0])), sum: 0, count: 0 };
    promMetrics.duration.set(key, entry);
  }
  entry.sum += seconds;
  entry.count += 1;
  for (const b of HISTOGRAM_BUCKETS) {
    if (seconds <= b) entry.buckets.set(b, entry.buckets.get(b) + 1);
  }
}

function clientIp(req) {
  return req.headers['x-real-ip'] || req.headers['x-forwarded-for'] || req.ip || req.socket.remoteAddress;
}

function log(entry) {
  const record = { timestamp: new Date().toISOString(), service: SERVICE_NAME, ...entry };
  process.stdout.write(JSON.stringify(record) + '\n');
}

app.use(express.json());

// Prometheus metrics middleware
app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    const route = (req.route && req.route.path) || 'unmatched';
    const status = res.statusCode;
    incCounter(promMetrics.requestsTotal, labelKey(req.method, route, status));
    if (status >= 400) incCounter(promMetrics.errorsTotal, labelKey(req.method, route, status));
    observeDuration(req.method, route, seconds);
  });
  next();
});

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
    dependencies: { 'service-b': serviceBStatus }
  });
});

app.get('/metrics', (req, res) => {
  const lines = [];

  lines.push('# HELP http_requests_total Total number of HTTP requests');
  lines.push('# TYPE http_requests_total counter');
  for (const [key, count] of promMetrics.requestsTotal) {
    const [method, route, status] = key.split('|');
    lines.push(`http_requests_total{service="${SERVICE_NAME}",method="${method}",route="${route}",status_code="${status}"} ${count}`);
  }

  lines.push('# HELP http_errors_total Total number of HTTP requests with status >= 400');
  lines.push('# TYPE http_errors_total counter');
  for (const [key, count] of promMetrics.errorsTotal) {
    const [method, route, status] = key.split('|');
    lines.push(`http_errors_total{service="${SERVICE_NAME}",method="${method}",route="${route}",status_code="${status}"} ${count}`);
  }

  lines.push('# HELP http_request_duration_seconds HTTP request duration in seconds');
  lines.push('# TYPE http_request_duration_seconds histogram');
  for (const [key, entry] of promMetrics.duration) {
    const [method, route] = key.split('|');
    for (const b of HISTOGRAM_BUCKETS) {
      lines.push(`http_request_duration_seconds_bucket{service="${SERVICE_NAME}",method="${method}",route="${route}",le="${b}"} ${entry.buckets.get(b)}`);
    }
    lines.push(`http_request_duration_seconds_bucket{service="${SERVICE_NAME}",method="${method}",route="${route}",le="+Inf"} ${entry.count}`);
    lines.push(`http_request_duration_seconds_sum{service="${SERVICE_NAME}",method="${method}",route="${route}"} ${entry.sum.toFixed(6)}`);
    lines.push(`http_request_duration_seconds_count{service="${SERVICE_NAME}",method="${method}",route="${route}"} ${entry.count}`);
  }

  lines.push('# HELP service_up Whether the service process is up (1) or not (0)');
  lines.push('# TYPE service_up gauge');
  lines.push(`service_up{service="${SERVICE_NAME}"} 1`);

  lines.push('# HELP service_pending_callbacks Number of in-flight requests awaiting a downstream callback');
  lines.push('# TYPE service_pending_callbacks gauge');
  lines.push(`service_pending_callbacks{service="${SERVICE_NAME}"} ${pendingCallbacks.size}`);

  lines.push('# HELP service_uptime_seconds Seconds since the service process started');
  lines.push('# TYPE service_uptime_seconds counter');
  lines.push(`service_uptime_seconds{service="${SERVICE_NAME}"} ${Math.floor((Date.now() - startTime) / 1000)}`);

  res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  res.send(lines.join('\n') + '\n');
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
  const requestId = req.headers['x-request-id'] || crypto.randomUUID();
  const ip = clientIp(req);
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
    if (pending) {
      clearTimeout(pending.timeout);
      pendingCallbacks.delete(requestId);
    }
    log({ event: 'request_failed', request_id: requestId, path: '/greet-service-b', status: 502, error: err.message });
    return res.status(502).json({ request_id: requestId, status: 'error', message: 'Failed to reach service-b' });
  }

  try {
    const callbackData = await callbackPromise;
    log({
      event: 'callback_received',
      request_id: requestId,
      source_service: callbackData.source_service,
      status: 200
    });
    res.json({ request_id: requestId, status: 'success', message: 'Request completed successfully' });
  } catch (err) {
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
  log({ event: 'route_not_found', request_id: requestId, method: req.method, path: req.path, status: 404, client_ip: clientIp(req) });
  res.status(404).json({ error: 'Not found', path: req.path });
});

const server = app.listen(PORT, BIND_HOST, () => {
  log({ event: 'server_started', message: `${SERVICE_NAME} listening on ${BIND_HOST}:${PORT}`, port: PORT, bind_host: BIND_HOST });
});

module.exports = server;
