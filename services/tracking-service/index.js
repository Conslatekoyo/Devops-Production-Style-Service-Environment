'use strict';
require('./tracer');

const express = require('express');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3003;
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const SERVICE_NAME = 'tracking-service';
const BOOKING_SERVICE_URL = process.env.SERVICE_A_URL || 'http://service-a.internal:3001';
const startTime = Date.now();

const HISTOGRAM_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];

const promMetrics = {
  requestsTotal: new Map(),
  errorsTotal: new Map(),
  duration: new Map()
};

// Active rides being tracked
const activeRides = new Map();

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

// Tracking-service has no downstream dependencies - always healthy
app.get('/health', (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  log({
    event: 'health_check',
    request_id: requestId,
    method: 'GET',
    path: '/health',
    status: 200,
    client_ip: clientIp(req),
    active_rides: activeRides.size,
    dependencies: {}
  });
  res.json({
    service: SERVICE_NAME,
    status: 'healthy',
    port: PORT,
    message: `${SERVICE_NAME} listening on ${PORT}`,
    active_rides: activeRides.size,
    dependencies: {}
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

  lines.push('# HELP active_rides Number of rides currently being tracked');
  lines.push('# TYPE active_rides gauge');
  lines.push(`active_rides{service="${SERVICE_NAME}"} ${activeRides.size}`);

  lines.push('# HELP service_uptime_seconds Seconds since service started');
  lines.push('# TYPE service_uptime_seconds counter');
  lines.push(`service_uptime_seconds{service="${SERVICE_NAME}"} ${Math.floor((Date.now() - startTime) / 1000)}`);

  res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  res.send(lines.join('\n') + '\n');
});

// Simulate GPS lag / slow tracking update
app.get('/slow', async (req, res) => {
  const delay = parseInt(req.query.ms) || 3000;
  log({ event: 'gps_lag_simulation', delay_ms: delay, note: 'lab-only', scenario: 'poor_gps_signal' });
  await new Promise(resolve => setTimeout(resolve, delay));
  res.json({ service: SERVICE_NAME, status: 'ok', delay_ms: delay, note: 'lab-only', scenario: 'GPS signal recovered after delay' });
});

// Simulate tracking failure (e.g. GPS hardware failure)
app.get('/fail', (req, res) => {
  log({ event: 'tracking_failure_simulation', status: 500, note: 'lab-only', reason: 'gps_hardware_failure' });
  res.status(500).json({ service: SERVICE_NAME, status: 'error', message: 'GPS tracking unavailable', note: 'lab-only' });
});

// Main endpoint: start tracking a ride and confirm back to booking-service
app.post('/start-tracking', async (req, res) => {
  const rideId = req.headers['x-request-id'] || crypto.randomUUID();
  const { driver, eta_minutes, pickup, dropoff } = req.body || {};

  // Store ride in active tracking
  activeRides.set(rideId, {
    ride_id: rideId,
    driver,
    eta_minutes,
    pickup,
    dropoff,
    started_at: new Date().toISOString()
  });

  log({
    event: 'tracking_started',
    ride_id: rideId,
    driver_name: driver?.name,
    eta_minutes,
    pickup,
    dropoff,
    active_rides: activeRides.size,
    method: 'POST',
    path: '/start-tracking',
    client_ip: clientIp(req)
  });

  // Send confirmation callback to booking-service
  try {
    const callbackResponse = await fetch(`${BOOKING_SERVICE_URL}/ride-confirmed`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Request-ID': rideId
      },
      body: JSON.stringify({
        ride_id: rideId,
        driver: driver?.name || 'Unknown',
        driver_id: driver?.id,
        driver_rating: driver?.rating,
        car: driver?.car,
        eta_minutes: eta_minutes || 5,
        source_service: SERVICE_NAME
      })
    });

    log({
      event: 'booking_confirmation_sent',
      ride_id: rideId,
      target: 'booking-service',
      endpoint: '/ride-confirmed',
      status: callbackResponse.status
    });

    // Clean up after confirming
    setTimeout(() => activeRides.delete(rideId), 30000);

    res.json({
      ride_id: rideId,
      status: 'tracking_active',
      message: 'Ride tracking started, booking confirmed',
      driver: driver?.name,
      eta_minutes
    });
  } catch (err) {
    log({
      event: 'booking_confirmation_failed',
      ride_id: rideId,
      target: 'booking-service',
      status: 502,
      error: err.message
    });
    res.status(502).json({
      ride_id: rideId,
      status: 'error',
      message: 'Failed to confirm booking — tracking started but notification failed'
    });
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
