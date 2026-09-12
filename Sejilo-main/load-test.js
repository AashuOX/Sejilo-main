#!/usr/bin/env node

/**
 * SejiloChat Performance & Load Testing
 * Tests WebSocket connections, HTTP throughput, and system performance
 *
 * Usage: node load-test.js [--clients=50] [--messages=100] [--url=http://localhost:8080]
 */

const http = require('http');
const WebSocket = require('ws');

// Configuration
const CONFIG = {
  API_URL: process.env.API_URL || 'http://localhost:8080',
  WS_URL: process.env.WS_URL || 'ws://localhost:8080',
  NUM_CLIENTS: parseInt(process.env.NUM_CLIENTS || process.argv.find(a => a.startsWith('--clients='))?.split('=')[1] || '50'),
  MESSAGES_PER_CLIENT: parseInt(process.env.MESSAGES_PER_CLIENT || process.argv.find(a => a.startsWith('--messages='))?.split('=')[1] || '100'),
  MESSAGE_INTERVAL_MS: 100
};

class PerformanceTestClient {
  constructor(clientId, onComplete) {
    this.clientId = clientId;
    this.onComplete = onComplete;
    this.token = null;
    this.ws = null;
    this.userId = null;

    this.metrics = {
      clientId,
      signupTime: 0,
      loginTime: 0,
      wsConnectTime: 0,
      messagesSent: 0,
      messagesReceived: 0,
      avgMessageLatency: 0,
      p95MessageLatency: 0,
      p99MessageLatency: 0,
      errors: [],
      startTime: Date.now(),
      endTime: 0,
      totalTime: 0
    };
  }

  async signup() {
    const email = `perf-${this.clientId}-${Date.now()}@loadtest.local`;
    const password = 'TestPassword123!@';
    const username = `perftest${this.clientId}${Date.now()}`;

    const start = Date.now();

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify({
        email,
        password,
        username
      });

      const options = {
        hostname: 'localhost',
        port: 8080,
        path: '/auth/register',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData)
        },
        timeout: 5000
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          this.metrics.signupTime = Date.now() - start;
          try {
            const response = JSON.parse(data);
            if (response.id) {
              this.userId = response.id;
              resolve(response);
            } else {
              reject(new Error(`Signup failed with status ${res.statusCode}`));
            }
          } catch (e) {
            reject(new Error(`Signup JSON parse error: ${e.message}`));
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Signup request timeout'));
      });
      req.write(postData);
      req.end();
    });
  }

  async login(email, password) {
    const start = Date.now();

    return new Promise((resolve, reject) => {
      const postData = JSON.stringify({ email, password });

      const options = {
        hostname: 'localhost',
        port: 8080,
        path: '/auth/login',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData)
        },
        timeout: 5000
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          this.metrics.loginTime = Date.now() - start;
          try {
            const response = JSON.parse(data);
            if (response.accessToken) {
              this.token = response.accessToken;
              resolve(response);
            } else {
              reject(new Error(`Login failed with status ${res.statusCode}`));
            }
          } catch (e) {
            reject(new Error(`Login JSON parse error: ${e.message}`));
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Login request timeout'));
      });
      req.write(postData);
      req.end();
    });
  }

  connectWebSocket() {
    return new Promise((resolve, reject) => {
      const start = Date.now();

      try {
        this.ws = new WebSocket(`${CONFIG.WS_URL}/chat`, {
          headers: {
            Authorization: `Bearer ${this.token}`
          },
          handshakeTimeout: 5000
        });

        this.ws.on('open', () => {
          this.metrics.wsConnectTime = Date.now() - start;
          resolve();
        });

        this.ws.on('message', (data) => {
          this.metrics.messagesReceived++;
        });

        this.ws.on('error', (error) => {
          this.metrics.errors.push(`WebSocket error: ${error.message}`);
          reject(error);
        });

        this.ws.on('close', () => {
          // Normal close during cleanup
        });

        setTimeout(() => {
          reject(new Error('WebSocket connection timeout'));
        }, 5000);
      } catch (error) {
        reject(error);
      }
    });
  }

  async sendMessages() {
    const latencies = [];

    for (let i = 0; i < CONFIG.MESSAGES_PER_CLIENT; i++) {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        const start = Date.now();
        const message = {
          type: 'message',
          content: `Perf test msg ${i} from client ${this.clientId}`,
          timestamp: start
        };

        try {
          this.ws.send(JSON.stringify(message));
          this.metrics.messagesSent++;
          const latency = Date.now() - start;
          latencies.push(latency);
        } catch (error) {
          this.metrics.errors.push(`Send error: ${error.message}`);
        }

        // Throttle messages
        await new Promise(resolve => setTimeout(resolve, CONFIG.MESSAGE_INTERVAL_MS));
      }
    }

    if (latencies.length > 0) {
      this.metrics.avgMessageLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;
      latencies.sort((a, b) => a - b);
      this.metrics.p95MessageLatency = latencies[Math.floor(latencies.length * 0.95)];
      this.metrics.p99MessageLatency = latencies[Math.floor(latencies.length * 0.99)];
    }
  }

  async run() {
    try {
      // Sign up
      const signupResponse = await this.signup();

      // Login
      await this.login(signupResponse.email, 'TestPassword123!@');

      // Connect WebSocket
      await this.connectWebSocket();

      // Send messages
      await this.sendMessages();

      // Cleanup
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.close();
      }

      this.metrics.endTime = Date.now();
      this.metrics.totalTime = this.metrics.endTime - this.metrics.startTime;
    } catch (error) {
      this.metrics.errors.push(`Client error: ${error.message}`);
      if (this.ws) {
        try {
          this.ws.close();
        } catch (e) {
          // Ignore close errors
        }
      }
    }

    this.onComplete(this.metrics);
  }
}

async function runLoadTest() {
  console.log(`
╔════════════════════════════════════════════════════════╗
║        SejiloChat Performance & Load Test              ║
╚════════════════════════════════════════════════════════╝

Configuration:
  • API URL: ${CONFIG.API_URL}
  • WS URL: ${CONFIG.WS_URL}
  • Concurrent clients: ${CONFIG.NUM_CLIENTS}
  • Messages per client: ${CONFIG.MESSAGES_PER_CLIENT}
  • Message interval: ${CONFIG.MESSAGE_INTERVAL_MS}ms
  • Total messages: ${CONFIG.NUM_CLIENTS * CONFIG.MESSAGES_PER_CLIENT}

Starting load test at ${new Date().toISOString()}...
  `);

  const allMetrics = [];
  let completed = 0;
  const startTime = Date.now();

  // Create and run all test clients
  const testPromises = Array.from({ length: CONFIG.NUM_CLIENTS }, (_, i) => {
    return new Promise((resolve) => {
      const client = new PerformanceTestClient(i + 1, (metrics) => {
        allMetrics.push(metrics);
        completed++;

        // Show progress every 10 clients
        if (completed % 10 === 0) {
          process.stdout.write(`[Progress] ${completed}/${CONFIG.NUM_CLIENTS} clients completed\r`);
        }
        resolve();
      });

      // Stagger client starts to avoid thundering herd
      setTimeout(() => client.run(), i * 10);
    });
  });

  await Promise.all(testPromises);

  const totalTestTime = Date.now() - startTime;

  // Calculate aggregate metrics
  const successfulClients = allMetrics.filter(m => m.errors.length === 0).length;
  const avgSignupTime = allMetrics.reduce((sum, m) => sum + m.signupTime, 0) / CONFIG.NUM_CLIENTS;
  const avgLoginTime = allMetrics.reduce((sum, m) => sum + m.loginTime, 0) / CONFIG.NUM_CLIENTS;
  const avgWsTime = allMetrics.reduce((sum, m) => sum + m.wsConnectTime, 0) / CONFIG.NUM_CLIENTS;
  const totalMessagesSent = allMetrics.reduce((sum, m) => sum + m.messagesSent, 0);
  const totalMessagesReceived = allMetrics.reduce((sum, m) => sum + m.messagesReceived, 0);
  const avgLatency = allMetrics.reduce((sum, m) => sum + m.avgMessageLatency, 0) / CONFIG.NUM_CLIENTS;
  const avgP95Latency = allMetrics.reduce((sum, m) => sum + m.p95MessageLatency, 0) / CONFIG.NUM_CLIENTS;
  const avgP99Latency = allMetrics.reduce((sum, m) => sum + m.p99MessageLatency, 0) / CONFIG.NUM_CLIENTS;

  const totalErrors = allMetrics.reduce((sum, m) => sum + m.errors.length, 0);
  const maxClientTime = Math.max(...allMetrics.map(m => m.totalTime));
  const minClientTime = Math.min(...allMetrics.map(m => m.totalTime));

  const throughput = totalMessagesSent > 0 ? (totalMessagesSent / (totalTestTime / 1000)).toFixed(2) : 0;
  const deliveryRate = totalMessagesSent > 0 ? ((totalMessagesReceived / totalMessagesSent) * 100).toFixed(2) : 0;

  console.log(`
╔════════════════════════════════════════════════════════╗
║              Test Results & Performance                ║
╚════════════════════════════════════════════════════════╝

Client Success Rate:
  • Successful clients: ${successfulClients}/${CONFIG.NUM_CLIENTS}
  • Success rate: ${((successfulClients / CONFIG.NUM_CLIENTS) * 100).toFixed(2)}%

Authentication Performance:
  • Avg signup time: ${avgSignupTime.toFixed(2)}ms
  • Avg login time: ${avgLoginTime.toFixed(2)}ms
  • Avg WebSocket connect time: ${avgWsTime.toFixed(2)}ms

Message Performance:
  • Total messages sent: ${totalMessagesSent}
  • Total messages received: ${totalMessagesReceived}
  • Message delivery rate: ${deliveryRate}%
  • Throughput: ${throughput} messages/sec

Latency Analysis:
  • Avg message latency: ${avgLatency.toFixed(2)}ms
  • P95 message latency: ${avgP95Latency.toFixed(2)}ms
  • P99 message latency: ${avgP99Latency.toFixed(2)}ms

System Performance:
  • Total errors: ${totalErrors}
  • Fastest client: ${minClientTime}ms
  • Slowest client: ${maxClientTime}ms
  • Total test duration: ${totalTestTime}ms

Performance Assessment:
  ${avgLatency < 50 ? '  ✅ Message latency excellent (<50ms)' : avgLatency < 100 ? '  ✅ Message latency good (<100ms)' : '  ⚠️  Message latency high (>100ms)'}
  ${deliveryRate >= 99 ? '  ✅ Message delivery excellent (≥99%)' : deliveryRate >= 95 ? '  ✅ Message delivery acceptable (≥95%)' : '  ⚠️  Message delivery degraded (<95%)'}
  ${totalErrors < CONFIG.NUM_CLIENTS * 0.01 ? '  ✅ Error rate excellent (<1%)' : totalErrors < CONFIG.NUM_CLIENTS * 0.05 ? '  ✅ Error rate acceptable (<5%)' : '  ⚠️  Error rate high (≥5%)'}
  ${avgWsTime < 100 ? '  ✅ WebSocket connections fast (<100ms)' : '  ⚠️  WebSocket connections slow (≥100ms)'}

Recommendations:
${avgLatency > 100 ? '  → Message latency is high. Check database queries and network latency.\n    Run: docker-compose logs -f backend' : ''}
${totalErrors > CONFIG.NUM_CLIENTS * 0.05 ? '  → Error rate exceeds 5%. Review backend logs for connection failures.\n    Run: docker-compose logs backend | grep -i error' : ''}
${deliveryRate < 0.95 ? '  → Message delivery rate < 95%. Check WebSocket stability and Redis connectivity.\n    Run: docker-compose logs redis' : ''}
${avgWsTime > 200 ? '  → WebSocket connection time is slow. Check system resources and firewall.\n    Run: docker stats' : ''}

Load Test Duration: ${(totalTestTime / 1000).toFixed(2)} seconds
Test completed at: ${new Date().toISOString()}
════════════════════════════════════════════════════════

`);

  // Print first few error details if any
  if (totalErrors > 0) {
    console.log('Recent Error Samples:');
    const errorSamples = [];
    for (const metric of allMetrics) {
      if (metric.errors.length > 0) {
        errorSamples.push(...metric.errors.slice(0, 2));
      }
      if (errorSamples.length >= 5) break;
    }
    errorSamples.slice(0, 5).forEach(err => console.log(`  • ${err}`));
    console.log('');
  }

  // Exit with error code if critical metrics are bad
  const criticalFailure =
    successfulClients < CONFIG.NUM_CLIENTS * 0.5 ||
    deliveryRate < 0.90 ||
    totalErrors > CONFIG.NUM_CLIENTS * 0.1;

  if (criticalFailure) {
    console.log('❌ Load test detected critical performance issues. See recommendations above.');
    process.exit(1);
  } else {
    console.log('✅ Load test completed successfully!');
    process.exit(0);
  }
}

// Handle process errors
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

// Run the test
runLoadTest().catch(error => {
  console.error('Fatal error:', error.message);
  process.exit(1);
});
