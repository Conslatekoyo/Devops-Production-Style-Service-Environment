import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

const successfulFlows = new Counter('successful_flows');
const applicationFailures = new Rate('application_failures');
const flowDuration = new Trend('flow_duration_ms', true);

export const options = {
  scenarios: {
    normal: {
      executor: 'constant-vus',
      exec: 'normalTraffic',
      vus: 3,
      duration: '30s',
      tags: {
        test_type: 'normal'
      }
    },

    stress: {
      executor: 'ramping-vus',
      exec: 'stressTraffic',
      startTime: '35s',
      stages: [
        { duration: '15s', target: 10 },
        { duration: '30s', target: 25 },
        { duration: '15s', target: 0 }
      ],
      tags: {
        test_type: 'stress'
      }
    },

    controlled_failure: {
      executor: 'constant-arrival-rate',
      exec: 'failureTraffic',
      startTime: '100s',
      rate: 2,
      timeUnit: '1s',
      duration: '20s',
      preAllocatedVUs: 2,
      maxVUs: 5,
      tags: {
        test_type: 'failure'
      }
    }
  },

  thresholds: {
    'http_req_failed{test_type:normal}': ['rate<0.01'],
    'http_req_duration{test_type:normal}': ['p(95)<1000'],

    'http_req_failed{test_type:stress}': ['rate<0.05'],
    'http_req_duration{test_type:stress}': ['p(95)<2000'],

    successful_flows: ['count>0']
  }
};

function requestHeaders() {
  return {
    headers: {
      'X-Request-ID': `k6-${__VU}-${__ITER}-${Date.now()}`
    }
  };
}

export function normalTraffic() {
  const response = http.post(
    `${BASE_URL}/service-a/greet-service-b`,
    null,
    {
      ...requestHeaders(),
      tags: {
        endpoint: 'greet-service-b',
        test_type: 'normal'
      }
    }
  );

  const passed = check(response, {
    'normal flow returned 200': (r) => r.status === 200,
    'normal response reports success': (r) => {
      try {
        return r.json('status') === 'success';
      } catch {
        return false;
      }
    }
  });

  applicationFailures.add(!passed);
  flowDuration.add(response.timings.duration);

  if (passed) {
    successfulFlows.add(1);
  }

  sleep(1);
}

export function stressTraffic() {
  const response = http.post(
    `${BASE_URL}/service-a/greet-service-b`,
    null,
    {
      ...requestHeaders(),
      tags: {
        endpoint: 'greet-service-b',
        test_type: 'stress'
      }
    }
  );

  const passed = check(response, {
    'stress request returned 200': (r) => r.status === 200
  });

  applicationFailures.add(!passed);
  flowDuration.add(response.timings.duration);

  if (passed) {
    successfulFlows.add(1);
  }

  sleep(0.2);
}

export function failureTraffic() {
  const response = http.get(
    `${BASE_URL}/service-a/fail`,
    {
      ...requestHeaders(),
      tags: {
        endpoint: 'fail',
        test_type: 'failure'
      }
    }
  );

  check(response, {
    'controlled failure returned expected 500': (r) =>
      r.status === 500
  });

  sleep(0.5);
}
