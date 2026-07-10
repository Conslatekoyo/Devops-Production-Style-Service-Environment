const express = require('express');

const app = express();
const PORT = process.env.PORT || 3003;
const BIND_HOST = process.env.BIND_HOST || '127.0.0.1';
const SERVICE_NAME = 'service-c';
const SERVICE_A_URL = process.env.SERVICE_A_URL || 'http://service-a.internal:3001';
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

  lines.push('# HELP service_uptime_seconds Seconds since the service process started');
  lines.push('# TYPE service_uptime_seconds counter');
  lines.push(`service_uptime_seconds{service="${SERVICE_NAME}"} ${Math.floor((Date.now() - startTime) / 1000)}`);

  res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
  res.send(lines.join('\n') + '\n');
});

// POST: receives the forwarded request from service-b and sends the callback
// to service-a. Kept consistent with the POST-based chain end to end.
app.post('/greet-c', async (req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  log({ event: 'request_received', request_id: requestId, method: 'POST', path: '/greet-c', source: 'service-b', client_ip: clientIp(req) });

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
    log({
      event: 'callback_sent',
      request_id: requestId,
      target: 'service-a',
      endpoint: '/greeting-rcvd',
      status: cbResponse.status
    });
  } catch (err) {
    log({ event: 'callback_failed', request_id: requestId, target: 'service-a', error: err.message, status: 502 });
  }

  res.json({ request_id: requestId, status: 'processed', callback_sent: callbackSent });
});

app.use((req, res) => {
  const requestId = req.headers['x-request-id'] || 'none';
  log({ event: 'route_not_found', request_id: requestId, method: req.method, path: req.path, status: 404, client_ip: clientIp(req) });
  res.status(404).json({ error: 'Not found', path: req.path });
});

app.listen(PORT, BIND_HOST, () => {
  log({ event: 'server_started', message: `${SERVICE_NAME} listening on ${BIND_HOST}:${PORT}`, port: PORT, bind_host: BIND_HOST });
});
