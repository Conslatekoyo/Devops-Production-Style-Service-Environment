'use strict';
require('./tracer');

const express = require('express');
const crypto = require('crypto');
const { trace } = require('@opentelemetry/api');

const app = express();
const PORT = process.env.PORT || 3001;
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const SERVICE_NAME = 'booking-service';
const DRIVER_SERVICE_URL = process.env.SERVICE_B_URL || 'http://service-b.internal:3002';

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

function currentTraceId() {
  const span = trace.getActiveSpan();
  const context = span?.spanContext();

  if (!context || !context.traceId) {
    return null;
  }

  return context.traceId;
}

function log(entry) {
  const record = {
    timestamp: new Date().toISOString(),
    service: SERVICE_NAME,
    level: entry.level || 'info',
    trace_id: entry.trace_id || currentTraceId(),
    ...entry
  };

  process.stdout.write(JSON.stringify(record) + '\n');
}

app.use(express.json());
app.use((req, res, next) => {
  const startedAt = process.hrtime.bigint();
  const requestId =
    req.headers['x-request-id'] ||
    crypto.randomUUID();

  req.requestId = requestId;
  res.setHeader('X-Request-ID', requestId);

  res.on('finish', () => {
    const durationMs =
      Number(process.hrtime.bigint() - startedAt) / 1_000_000;

    const level =
      res.statusCode >= 500
        ? 'error'
        : res.statusCode >= 400
          ? 'warn'
          : 'info';

    log({
      level,
      event: 'request_completed',
      request_id: requestId,
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      duration_ms: Number(durationMs.toFixed(2))
    });
  });

  next();
});
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

// Advanced health check - verifies driver-service is reachable
app.get('/health', async (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  let driverServiceStatus = 'ok';

  try {
    const response = await fetch(`${DRIVER_SERVICE_URL}/health`, {
      signal: AbortSignal.timeout(2000)
    });
    if (!response.ok) driverServiceStatus = 'degraded';
  } catch {
    driverServiceStatus = 'unreachable';
  }

  const overallStatus = driverServiceStatus === 'ok' ? 'healthy' : 'degraded';
  const httpStatus = overallStatus === 'healthy' ? 200 : 207;

  log({
    event: 'health_check',
    request_id: requestId,
    method: 'GET',
    path: '/health',
    status: httpStatus,
    client_ip: clientIp(req),
    dependencies: { 'driver-service': driverServiceStatus }
  });

  res.status(httpStatus).json({
    service: SERVICE_NAME,
    status: overallStatus,
    port: PORT,
    message: `${SERVICE_NAME} listening on ${PORT}`,
    dependencies: { 'driver-service': driverServiceStatus }
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

  lines.push('# HELP http_errors_total Total HTTP requests with status >= 400');
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

  lines.push('# HELP service_up Whether the service is up (1) or not (0)');
  lines.push('# TYPE service_up gauge');
  lines.push(`service_up{service="${SERVICE_NAME}"} 1`);

  lines.push('# HELP pending_rides Number of rides awaiting driver confirmation callback');
  lines.push('# TYPE pending_rides gauge');
  lines.push(`pending_rides{service="${SERVICE_NAME}"} ${pendingCallbacks.size}`);

  lines.push('# HELP service_uptime_seconds Seconds since service started');
  lines.push('# TYPE service_uptime_seconds counter');
  lines.push(`service_uptime_seconds{service="${SERVICE_NAME}"} ${Math.floor((Date.now() - startTime) / 1000)}`);

  res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  res.send(lines.join('\n') + '\n');
});

// Simulate slow booking (e.g. surge pricing calculation taking too long)
app.get('/slow', async (req, res) => {
  const delay = parseInt(req.query.ms) || 3000;
  log({ event: 'slow_booking_simulation', delay_ms: delay, note: 'lab-only' });
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ service: SERVICE_NAME, status: 'ok', delay_ms: delay, note: 'lab-only', scenario: 'surge pricing calculation timeout' });
});

// Simulate booking failure (e.g. payment declined)
app.get('/fail', (req, res) => {
  log({ event: 'booking_failure_simulation', status: 500, note: 'lab-only', reason: 'payment_declined' });
  res.status(500).json({ service: SERVICE_NAME, status: 'error', message: 'Payment declined', note: 'lab-only' });
});

// Main endpoint: customer requests a ride
app.post('/request-ride', async (req, res) => {
  const rideId = req.headers['x-request-id'] || crypto.randomUUID();
  const ip = clientIp(req);
  const pickup = req.body?.pickup || 'Westlands';
  const dropoff = req.body?.dropoff || 'CBD';

  log({
    event: 'ride_requested',
    ride_id: rideId,
    method: 'POST',
    path: '/request-ride',
    client_ip: ip,
    pickup,
    dropoff
  });

  const callbackPromise = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pendingCallbacks.delete(rideId);
      reject(new Error('callback_timeout'));
    }, CALLBACK_TIMEOUT_MS);
    pendingCallbacks.set(rideId, { resolve, timeout });
  });

  try {
    const response = await fetch(`${DRIVER_SERVICE_URL}/assign-driver`, {
      method: 'POST',
      headers: {
        'X-Request-ID': rideId,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ ride_id: rideId, pickup, dropoff })
    });
    await response.json();
    log({ event: 'driver_assignment_requested', ride_id: rideId, target: 'driver-service', status: response.status });
  } catch (err) {
    const pending = pendingCallbacks.get(rideId);
    if (pending) { clearTimeout(pending.timeout); pendingCallbacks.delete(rideId); }
    log({ event: 'driver_assignment_failed', ride_id: rideId, status: 502, error: err.message });
    return res.status(502).json({ ride_id: rideId, status: 'error', message: 'Failed to reach driver-service' });
  }

  try {
    const callbackData = await callbackPromise;
    log({
      event: 'ride_confirmed',
      ride_id: rideId,
      driver: callbackData.driver,
      eta_minutes: callbackData.eta_minutes,
      status: 200
    });
    res.json({
      ride_id: rideId,
      status: 'confirmed',
      message: 'Driver on the way',
      driver: callbackData.driver || 'Brian',
      eta_minutes: callbackData.eta_minutes || 4,
      pickup,
      dropoff
    });
  } catch (err) {
    log({ event: 'ride_confirmation_timeout', ride_id: rideId, status: 504, error: err.message });
    res.status(504).json({ ride_id: rideId, status: 'error', message: 'No drivers available — please try again' });
  }
});

// Callback from tracking-service confirming ride is active
app.post('/ride-confirmed', (req, res) => {
  const body = req.body;
  const rideId = body.ride_id || req.headers['x-request-id'] || 'none';
  log({
    event: 'tracking_callback_received',
    ride_id: rideId,
    driver: body.driver,
    eta_minutes: body.eta_minutes,
    method: 'POST',
    path: '/ride-confirmed',
    status: 200,
    client_ip: clientIp(req)
  });
  const pending = pendingCallbacks.get(rideId);
  if (pending) {
    clearTimeout(pending.timeout);
    pendingCallbacks.delete(rideId);
    pending.resolve(body);
  }
  res.json({ status: 'received' });
});

app.use((req, res) => {
  const rideId = req.headers['x-request-id'] || 'none';
  log({ event: 'route_not_found', ride_id: rideId, method: req.method, path: req.path, status: 404, client_ip: clientIp(req) });
  res.status(404).json({ error: 'Not found', path: req.path });
});

const server = app.listen(PORT, BIND_HOST, () => {
  log({ event: 'server_started', message: `${SERVICE_NAME} listening on ${BIND_HOST}:${PORT}`, port: PORT });
});

module.exports = server;
