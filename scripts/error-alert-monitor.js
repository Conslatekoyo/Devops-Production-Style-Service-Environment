// Polls each service's /metrics endpoint on an interval, computes the error
// rate over that interval (not cumulative since boot), and posts to Slack
// when it crosses ERROR_THRESHOLD_PERCENT. Sends a recovery message once the
// rate drops back down. A cooldown prevents re-alerting every interval while
// a breach persists.
//
// /metrics is served in Prometheus text exposition format (http_requests_total,
// http_errors_total counters with method/route/status_code labels), not JSON.

const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL;
if (!SLACK_WEBHOOK_URL) {
  console.error('SLACK_WEBHOOK_URL is required');
  process.exit(1);
}

const ERROR_THRESHOLD_PERCENT = Number(process.env.ERROR_THRESHOLD_PERCENT || 20);
const CHECK_INTERVAL_SECONDS = Number(process.env.CHECK_INTERVAL_SECONDS || 60);
const MIN_REQUESTS_SAMPLE = Number(process.env.MIN_REQUESTS_SAMPLE || 5);
const ALERT_COOLDOWN_SECONDS = Number(process.env.ALERT_COOLDOWN_SECONDS || 900);
const METRICS_TIMEOUT_MS = Number(process.env.METRICS_TIMEOUT_MS || 3000);

// Defaults match the VM/systemd deployment, which still resolves peers via the
// old .internal hostnames (see each service's SERVICE_*_URL default). Docker
// Compose overrides SERVICES to use the current compose service DNS names.
const DEFAULT_SERVICES =
  'booking-service=http://service-a.internal:3001/metrics,' +
  'driver-service=http://service-b.internal:3002/metrics,' +
  'tracking-service=http://service-c.internal:3003/metrics';

const services = (process.env.SERVICES || DEFAULT_SERVICES)
  .split(',')
  .map((entry) => entry.trim())
  .filter(Boolean)
  .map((entry) => {
    const [name, url] = entry.split('=');
    return { name, url };
  });

// name -> { prevTotal, prevFailed, breaching, lastAlertAt }
const state = new Map(services.map((s) => [s.name, {}]));

function log(entry) {
  process.stdout.write(JSON.stringify({ timestamp: new Date().toISOString(), service: 'error-alert-monitor', ...entry }) + '\n');
}

// Parses Prometheus text exposition format, summing counters across all label
// combinations (route/method/status) since we want the service's total, not
// a per-route breakdown.
function parsePromMetrics(text) {
  let total = 0;
  let failed = 0;
  for (const line of text.split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^(\w+)\{[^}]*\}\s+([0-9.eE+-]+)/);
    if (!match) continue;
    const [, metric, valueStr] = match;
    const value = Number(valueStr);
    if (metric === 'http_requests_total') total += value;
    else if (metric === 'http_errors_total') failed += value;
  }
  return { total, failed };
}

async function fetchMetrics(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), METRICS_TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = await res.text();
    return parsePromMetrics(text);
  } finally {
    clearTimeout(timeout);
  }
}

async function postToSlack(text) {
  try {
    const res = await fetch(SLACK_WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text })
    });
    if (!res.ok) log({ event: 'slack_post_failed', status: res.status });
  } catch (err) {
    log({ event: 'slack_post_failed', error: err.message });
  }
}

async function checkService(svc) {
  const st = state.get(svc.name);

  let metrics;
  try {
    metrics = await fetchMetrics(svc.url);
  } catch (err) {
    log({ event: 'metrics_unreachable', target: svc.name, error: err.message });
    const now = Date.now();
    const cooledDown = !st.lastAlertAt || now - st.lastAlertAt >= ALERT_COOLDOWN_SECONDS * 1000;
    if (!st.breaching || cooledDown) {
      await postToSlack(`:x: *${svc.name} metrics unreachable* — possible outage (${err.message})`);
      st.lastAlertAt = now;
      st.breaching = true;
    }
    return;
  }

  const { total, failed } = metrics;

  if (st.prevTotal === undefined) {
    st.prevTotal = total;
    st.prevFailed = failed;
    return;
  }

  const deltaTotal = total - st.prevTotal;
  const deltaFailed = failed - st.prevFailed;
  st.prevTotal = total;
  st.prevFailed = failed;

  if (deltaTotal < 0) {
    // Counter reset (service restarted) — current values become the new baseline.
    return;
  }

  if (deltaTotal < MIN_REQUESTS_SAMPLE) {
    log({ event: 'sample_too_small', target: svc.name, delta_total: deltaTotal });
    return;
  }

  const errorRatePercent = Math.round((deltaFailed / deltaTotal) * 1000) / 10;
  log({ event: 'error_rate_check', target: svc.name, delta_total: deltaTotal, delta_failed: deltaFailed, error_rate_percent: errorRatePercent });

  const now = Date.now();
  if (errorRatePercent >= ERROR_THRESHOLD_PERCENT) {
    const cooledDown = !st.lastAlertAt || now - st.lastAlertAt >= ALERT_COOLDOWN_SECONDS * 1000;
    if (!st.breaching || cooledDown) {
      await postToSlack(
        `:rotating_light: *High error rate* — \`${svc.name}\`\n` +
        `Error rate: *${errorRatePercent}%* (${deltaFailed}/${deltaTotal} requests) over the last ${CHECK_INTERVAL_SECONDS}s\n` +
        `Threshold: ${ERROR_THRESHOLD_PERCENT}%`
      );
      st.lastAlertAt = now;
      st.breaching = true;
    }
  } else if (st.breaching) {
    await postToSlack(`:white_check_mark: *Recovered* — \`${svc.name}\` error rate back to ${errorRatePercent}% (below ${ERROR_THRESHOLD_PERCENT}% threshold)`);
    st.breaching = false;
  }
}

async function runCycle() {
  await Promise.all(services.map((svc) => checkService(svc)));
}

async function main() {
  log({ event: 'monitor_started', services: services.map((s) => s.name), threshold_percent: ERROR_THRESHOLD_PERCENT, interval_seconds: CHECK_INTERVAL_SECONDS });
  for (;;) {
    await runCycle();
    await new Promise((resolve) => setTimeout(resolve, CHECK_INTERVAL_SECONDS * 1000));
  }
}

process.on('SIGTERM', () => { log({ event: 'monitor_stopping' }); process.exit(0); });

main();
