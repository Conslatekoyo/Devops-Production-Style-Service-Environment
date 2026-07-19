'use strict';
require('./tracer');

const express = require('express');
const crypto = require('crypto');
const { trace } = require('@opentelemetry/api');
const app = express();
const PORT = process.env.PORT || 3002;
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const SERVICE_NAME = 'driver-service';
const TRACKING_SERVICE_URL = process.env.SERVICE_C_URL || 'http://service-c.internal:3003';
const startTime = Date.now();

const HISTOGRAM_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];

const promMetrics = {
  requestsTotal: new Map(),
  errorsTotal: new Map(),
  duration: new Map()
};

// Simulated driver pool
const AVAILABLE_DRIVERS = [
  { id: 'drv-001', name: 'Brian Otieno', rating: 4.8, car: 'Toyota Prius' },
  { id: 'drv-002', name: 'Mary Wanjiru', rating: 4.9, car: 'Nissan Note' },
  { id: 'drv-003', name: 'James Kamau', rating: 4.7, car: 'Suzuki Alto' },
  { id: 'drv-004', name: 'Faith Achieng', rating: 5.0, car: 'Toyota Axio' },
];

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

// Advanced health check - verifies tracking-service is reachable
app.get('/health', async (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  let trackingServiceStatus = 'ok';

  try {
    const response = await fetch(`${TRACKING_SERVICE_URL}/health`, {
      signal: AbortSignal.timeout(2000)
    });
    if (!response.ok) trackingServiceStatus = 'degraded';
  } catch {
    trackingServiceStatus = 'unreachable';
  }

  const overallStatus = trackingServiceStatus === 'ok' ? 'healthy' : 'degraded';
  const httpStatus = overallStatus === 'healthy' ? 200 : 207;

  log({
    event: 'health_check',
    request_id: requestId,
    method: 'GET',
    path: '/health',
    status: httpStatus,
    client_ip: clientIp(req),
    dependencies: { 'tracking-service': trackingServiceStatus }
  });

  res.status(httpStatus).json({
    service: SERVICE_NAME,
    status: overallStatus,
    port: PORT,
    message: `${SERVICE_NAME} listening on ${PORT}`,
    available_drivers: AVAILABLE_DRIVERS.length,
    dependencies: { 'tracking-service': trackingServiceStatus }
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

  lines.push('# HELP available_drivers Number of drivers currently available');
  lines.push('# TYPE available_drivers gauge');
  lines.push(`available_drivers{service="${SERVICE_NAME}"} ${AVAILABLE_DRIVERS.length}`);

  lines.push('# HELP service_uptime_seconds Seconds since service started');
  lines.push('# TYPE service_uptime_seconds counter');
  lines.push(`service_uptime_seconds{service="${SERVICE_NAME}"} ${Math.floor((Date.now() - startTime) / 1000)}`);

  res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  res.send(lines.join('\n') + '\n');
});

// Simulate slow driver assignment (e.g. no drivers nearby, searching wider area)
app.get('/slow', async (req, res) => {
  const delay = parseInt(req.query.ms) || 3000;
  log({ event: 'slow_assignment_simulation', delay_ms: delay, note: 'lab-only', scenario: 'no_drivers_nearby' });
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ service: SERVICE_NAME, status: 'ok', delay_ms: delay, note: 'lab-only', scenario: 'searching for drivers in wider area' });
});

// Simulate no drivers available
app.get('/fail', (req, res) => {
  log({ event: 'no_drivers_available', status: 500, note: 'lab-only' });
  res.status(500).json({ service: SERVICE_NAME, status: 'error', message: 'No drivers available in your area', note: 'lab-only' });
});

// Main endpoint: assign a driver to the ride
app.post('/assign-driver', async (req, res) => {
  const rideId = req.headers['x-request-id'] || crypto.randomUUID();
  const pickup = req.body?.pickup || 'Westlands';
  const dropoff = req.body?.dropoff || 'CBD';

  // Pick a random available driver
  const driver = AVAILABLE_DRIVERS[Math.floor(Math.random() * AVAILABLE_DRIVERS.length)];
  const etaMinutes = Math.floor(Math.random() * 8) + 2; // 2-10 mins

  log({
    event: 'driver_assignment_started',
    ride_id: rideId,
    method: 'POST',
    path: '/assign-driver',
    pickup,
    dropoff,
    driver_id: driver.id,
    driver_name: driver.name,
    client_ip: clientIp(req)
  });

  try {
    const response = await fetch(`${TRACKING_SERVICE_URL}/start-tracking`, {
      method: 'POST',
      headers: {
        'X-Request-ID': rideId,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        ride_id: rideId,
        driver,
        eta_minutes: etaMinutes,
        pickup,
        dropoff
      })
    });

    const data = await response.json();
    log({
      event: 'tracking_started',
      ride_id: rideId,
      driver_name: driver.name,
      eta_minutes: etaMinutes,
      status: response.status
    });

    res.json({
      ride_id: rideId,
      status: 'driver_assigned',
      driver: driver.name,
      driver_rating: driver.rating,
      car: driver.car,
      eta_minutes: etaMinutes
    });
  } catch (err) {
    log({ event: 'tracking_start_failed', ride_id: rideId, status: 502, error: err.message });
    res.status(502).json({ ride_id: rideId, status: 'error', message: 'Failed to reach tracking-service' });
  }
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
