# Operator Runbook

Deployment, operations, monitoring, and incident response for SejiloChat relay server and mesh deployments.

## Table of Contents

1. [Overview](#overview)
2. [Deployment](#deployment)
3. [Configuration](#configuration)
4. [Monitoring & Alerting](#monitoring--alerting)
5. [Maintenance](#maintenance)
6. [Incident Response](#incident-response)
7. [Disaster Recovery](#disaster-recovery)

---

## Overview

This runbook covers operational procedures for SejiloChat deployments at organizational or community scale.

### Deployment Models

#### Model 1: Standalone (Default)

- Each device operates independently
- No relay server required
- Users communicate over local Bluetooth mesh
- Suitable for: Small groups, emergencies, field operations

#### Model 2: Relay Extended

- Optional Internet Relay Server bridges offline devices
- Relay queues messages for offline recipients
- Users can exchange data through internet connectivity
- Suitable for: Organizations with multiple sites, bridging disconnected networks

#### Model 3: Hybrid Mesh + Relay

- Devices in proximity use Bluetooth mesh
- Devices at distant sites use relay server
- Combined for resilience and extended range
- Suitable for: Large organizations, multi-site operations

---

## Deployment

### Prerequisites

**Relay Server Hardware**:
- CPU: 4 cores (minimum), 8 cores (recommended)
- RAM: 8 GB (minimum), 16 GB (recommended)
- Storage: 100 GB SSD (for message queue and logs)
- Network: 100 Mbps uplink (minimum), 1 Gbps (recommended)

**OS & Software**:
- Linux (Ubuntu 20.04 LTS or CentOS 8+)
- Docker (optional, for containerized deployment)
- PostgreSQL 12+ (for message persistence)
- TLS 1.3 certificate (for secure connections)

### Step 1: Install Relay Server

**Option A: Binary Installation**

```bash
# Download latest release
wget https://github.com/sejilo/relay-server/releases/download/v1.0/sejilo-relay-1.0-linux-x64.tar.gz
tar xzf sejilo-relay-1.0-linux-x64.tar.gz
sudo mv sejilo-relay /opt/

# Create service user
sudo useradd -r -s /bin/false sejilo-relay

# Set permissions
sudo chown -R sejilo-relay:sejilo-relay /opt/sejilo-relay

# Create systemd service
sudo tee /etc/systemd/system/sejilo-relay.service > /dev/null <<EOF
[Unit]
Description=SejiloChat Relay Server
After=network.target postgresql.service

[Service]
Type=simple
User=sejilo-relay
WorkingDirectory=/opt/sejilo-relay
ExecStart=/opt/sejilo-relay/sejilo-relay --config /etc/sejilo/relay.conf
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sejilo-relay
```

**Option B: Docker Installation**

```bash
docker run -d \
  --name sejilo-relay \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /etc/sejilo:/etc/sejilo:ro \
  -v /var/log/sejilo:/var/log/sejilo \
  -e DATABASE_URL=postgresql://relay:password@db:5432/sejilo \
  sejilo/relay:latest
```

### Step 2: Configure PostgreSQL

```bash
# Install PostgreSQL
sudo apt install postgresql postgresql-contrib

# Create database and user
sudo -u postgres psql <<EOF
CREATE USER relay WITH PASSWORD 'secure_password_here';
CREATE DATABASE sejilo OWNER relay;
GRANT ALL PRIVILEGES ON DATABASE sejilo TO relay;
EOF

# Initialize schema
sudo -u relay psql sejilo < /opt/sejilo-relay/schema.sql
```

### Step 3: Configure Relay Server

**File**: `/etc/sejilo/relay.conf`

```yaml
# SejiloChat Relay Server Configuration

server:
  port: 9000
  bind_address: 0.0.0.0
  max_connections: 10000
  
tls:
  enabled: true
  certificate: /etc/sejilo/certs/relay.crt
  private_key: /etc/sejilo/certs/relay.key
  
relay:
  max_message_size: 150000  # 150 KB
  message_retention: 86400  # 24 hours
  max_pending_messages: 1000  # Per device
  ttl_max: 10
  deduplication_window: 3600
  
database:
  connection_string: postgresql://relay:password@localhost:5432/sejilo
  max_connections: 50
  connection_timeout: 30
  
logging:
  level: info
  format: json
  file: /var/log/sejilo/relay.log
  rotation: daily
  retention_days: 30
  
# Log only non-content metadata
logging.fields:
  - timestamp
  - device_id_hash
  - event_type
  - payload_size
  - status
  - latency_ms
```

### Step 4: Install TLS Certificate

```bash
# Create cert directory
sudo mkdir -p /etc/sejilo/certs

# Option A: Self-signed (development only)
sudo openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout /etc/sejilo/certs/relay.key \
  -out /etc/sejilo/certs/relay.crt \
  -days 365

# Option B: Let's Encrypt (production)
sudo certbot certonly --standalone \
  -d relay.example.com \
  -o /etc/letsencrypt/live/relay.example.com/

sudo ln -s /etc/letsencrypt/live/relay.example.com/privkey.pem \
  /etc/sejilo/certs/relay.key
sudo ln -s /etc/letsencrypt/live/relay.example.com/fullchain.pem \
  /etc/sejilo/certs/relay.crt

# Set permissions
sudo chmod 600 /etc/sejilo/certs/relay.key
sudo chmod 644 /etc/sejilo/certs/relay.crt
```

### Step 5: Start Relay Server

```bash
sudo systemctl start sejilo-relay
sudo systemctl status sejilo-relay
sudo journalctl -u sejilo-relay -f
```

---

## Configuration

### Environment Variables

```bash
# Relay server configuration
export RELAY_PORT=9000
export RELAY_BIND=0.0.0.0
export DATABASE_URL=postgresql://relay:password@localhost/sejilo
export LOG_LEVEL=info
export TLS_CERT=/etc/sejilo/certs/relay.crt
export TLS_KEY=/etc/sejilo/certs/relay.key

# Performance tuning
export MAX_CONNECTIONS=10000
export MESSAGE_BUFFER_SIZE=1000000  # 1 MB
export WORKER_THREADS=8
```

### DNS Configuration

```
relay.example.com.  3600  IN  A     192.0.2.1
relay.example.com.  3600  IN  AAAA  2001:db8::1
```

### Firewall Rules

```bash
# Allow relay connections
sudo ufw allow 9000/tcp
sudo ufw allow 9000/udp

# Allow SSH (admin access)
sudo ufw allow 22/tcp

# Block all other incoming
sudo ufw default deny incoming
sudo ufw enable
```

---

## Monitoring & Alerting

### Key Metrics

```
Core Performance:
  - Uptime: Relay availability (target: 99.9%)
  - Active connections: Current connected devices
  - Message throughput: Messages/minute
  - Latency: Avg round-trip time

Resource Usage:
  - CPU: User % (target: <80%)
  - Memory: Usage % (target: <85%)
  - Disk: Free space % (alert if <10%)
  - Database: Connection pool utilization

Reliability:
  - Message delivery rate: % successfully delivered
  - Failed messages: Count of undeliverable
  - Connection drops: Count per day
  - Auth failures: Count of invalid tokens
```

### Prometheus Monitoring

**Configuration**: `/etc/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'sejilo-relay'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: '/metrics'
```

**Query Examples**:

```promql
# Request rate
rate(sejilo_relay_requests_total[5m])

# Error rate
rate(sejilo_relay_errors_total[5m])

# Message queue depth
sejilo_relay_pending_messages

# Active connections
sejilo_relay_active_connections

# Latency percentile (p95)
histogram_quantile(0.95, sejilo_relay_message_latency_ms)
```

### Alerting Rules

**File**: `/etc/prometheus/rules/sejilo.yml`

```yaml
groups:
  - name: sejilo_relay
    rules:
      - alert: RelayServerDown
        expr: up{job="sejilo-relay"} == 0
        for: 2m
        annotations:
          summary: "Relay server down"

      - alert: HighCPUUsage
        expr: process_cpu_seconds_total{job="sejilo-relay"} > 0.8
        for: 5m
        annotations:
          summary: "Relay CPU usage >80%"

      - alert: DiskSpaceLow
        expr: node_filesystem_avail_bytes{mountpoint="/var"} / node_filesystem_size_bytes < 0.1
        for: 10m
        annotations:
          summary: "Relay disk space <10%"

      - alert: DatabaseConnectionPoolFull
        expr: sejilo_relay_db_connections_used / sejilo_relay_db_connections_limit > 0.9
        for: 5m
        annotations:
          summary: "Database connection pool >90% utilized"

      - alert: HighMessageQueueDepth
        expr: sejilo_relay_pending_messages > 10000
        for: 5m
        annotations:
          summary: "Relay message queue depth >10,000"
```

### Dashboard

Use Grafana to visualize metrics:

1. Add Prometheus data source: `http://localhost:9090`
2. Import dashboard ID: 12345 (community Sejilo dashboard)
3. Configure alerts to send to Slack/PagerDuty

### Log Aggregation

**Centralizes logs from relay server**:

```bash
# Install Filebeat
sudo apt install filebeat

# Configure /etc/filebeat/filebeat.yml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/sejilo/relay.log

output.elasticsearch:
  hosts: ["elasticsearch.example.com:9200"]
```

---

## Maintenance

### Daily Checklist

```
[ ] Check relay status: systemctl status sejilo-relay
[ ] Review error logs: tail -f /var/log/sejilo/relay.log
[ ] Monitor disk usage: df -h /var
[ ] Verify database connectivity: psql $DATABASE_URL
[ ] Confirm TLS cert validity: openssl x509 -in /etc/sejilo/certs/relay.crt -noout -dates
```

### Weekly Tasks

```
[ ] Generate metrics report
[ ] Review and archive logs
[ ] Backup database
[ ] Check for security updates
[ ] Test failover procedure
```

### Monthly Tasks

```
[ ] Run performance benchmark
[ ] Review relay configuration
[ ] Capacity planning analysis
[ ] Security audit
[ ] Disaster recovery drill
```

### Backup & Recovery

**Automated Backup**:

```bash
#!/bin/bash
# /usr/local/bin/backup-sejilo-relay.sh

BACKUP_DIR=/backups/sejilo
RETENTION_DAYS=30

# Backup database
pg_dump -U relay sejilo | gzip > $BACKUP_DIR/db-$(date +%Y%m%d).sql.gz

# Backup configuration
tar czf $BACKUP_DIR/config-$(date +%Y%m%d).tar.gz /etc/sejilo

# Backup TLS certs
tar czf $BACKUP_DIR/certs-$(date +%Y%m%d).tar.gz /etc/sejilo/certs

# Remove old backups
find $BACKUP_DIR -mtime +$RETENTION_DAYS -delete

# Sync to remote storage
aws s3 sync $BACKUP_DIR s3://backup-bucket/sejilo/
```

**Cron Job**:

```bash
0 2 * * * /usr/local/bin/backup-sejilo-relay.sh
```

**Recovery**:

```bash
# Restore from backup
gunzip < /backups/sejilo/db-20240824.sql.gz | \
  psql -U relay sejilo

# Verify restored data
psql -U relay sejilo -c "SELECT COUNT(*) FROM messages;"
```

### Upgrades

**Pre-Upgrade**:
1. Backup database and configuration
2. Test on staging environment first
3. Notify users of planned downtime
4. Prepare rollback procedure

**Upgrade Steps**:

```bash
# Download new version
wget https://github.com/sejilo/relay-server/releases/download/v1.1/sejilo-relay-1.1-linux-x64.tar.gz

# Stop relay
sudo systemctl stop sejilo-relay

# Backup current installation
sudo cp -r /opt/sejilo-relay /opt/sejilo-relay-backup

# Extract new version
tar xzf sejilo-relay-1.1-linux-x64.tar.gz
sudo mv sejilo-relay /opt/sejilo-relay-new

# Run migration (if needed)
/opt/sejilo-relay-new/migrate.sh

# Start new version
sudo systemctl start sejilo-relay

# Verify
sudo systemctl status sejilo-relay
```

**Rollback** (if issues):

```bash
sudo systemctl stop sejilo-relay
sudo rm -rf /opt/sejilo-relay
sudo mv /opt/sejilo-relay-backup /opt/sejilo-relay
sudo systemctl start sejilo-relay
```

---

## Incident Response

### Alert: Relay Server Down

**Detection**:
- Prometheus alert: `RelayServerDown`
- Users unable to send messages through relay

**Initial Response** (0–5 min):

```bash
# Check service status
sudo systemctl status sejilo-relay

# View recent logs
sudo journalctl -u sejilo-relay -n 100

# Check system resources
top
free -h
df -h
```

**Diagnosis**:

| Symptom | Cause | Action |
|---------|-------|--------|
| Service stopped | Crash or manual stop | Restart: `systemctl start sejilo-relay` |
| Port in use | Another process bound to 9000 | `lsof -i :9000`, kill conflicting process |
| High memory | Memory leak or overload | Restart service; check recent changes |
| Database unavailable | PostgreSQL down | `systemctl status postgresql` |

**Recovery** (5–30 min):

```bash
# Restart relay
sudo systemctl restart sejilo-relay

# Verify connectivity
curl -k https://relay.example.com:9000/health

# Monitor recovery
sudo tail -f /var/log/sejilo/relay.log
```

### Alert: High Error Rate

**Detection**:
- Prometheus: `rate(sejilo_relay_errors_total[5m]) > 10`
- Device reports delivery failures

**Investigation**:

```bash
# Check error logs
grep ERROR /var/log/sejilo/relay.log | tail -20

# Check specific errors
journalctl -u sejilo-relay --since "10 minutes ago" | grep -i error

# Check database
psql -U relay sejilo -c \
  "SELECT error_type, COUNT(*) FROM error_log GROUP BY error_type;"
```

**Common Causes & Fixes**:

| Error | Cause | Fix |
|-------|-------|-----|
| `AUTH_FAILED` | Invalid tokens | Check token generation, clock skew |
| `DB_CONNECTION_ERROR` | Database pool exhausted | Increase pool size, check for long queries |
| `MESSAGE_TOO_LARGE` | Client sending oversized messages | Enforce client-side size checks |
| `RATE_LIMIT_EXCEEDED` | DoS or heavy load | Increase rate limits or add DDoS protection |

### Alert: High Resource Usage

**CPU >80%**:

```bash
# Identify CPU-heavy processes
top -b -n 1 | head -20

# Check relay worker threads
ps aux | grep sejilo-relay

# Reduce worker threads if overloaded
# Edit config: worker_threads: 4 (reduce from 8)
sudo systemctl restart sejilo-relay
```

**Memory >85%**:

```bash
# Check memory by process
ps aux --sort=-%mem | head -10

# Check for memory leaks
# Monitor over time
watch -n 5 'ps aux | grep sejilo-relay'

# If stable high memory, likely normal; if growing, potential leak
```

**Disk <10%**:

```bash
# See what's using space
du -sh /var/log/*
du -sh /backups/*

# Archive old logs
find /var/log/sejilo -mtime +30 -exec gzip {} \;
find /var/log/sejilo -mtime +60 -delete

# Extend storage (if persistent)
# Add new volume or expand existing
```

### Alert: Message Queue Buildup

**Symptom**: Pending messages accumulate faster than they're delivered.

**Causes**:
- Recipients offline for extended time
- Network latency causing slow delivery
- Message size too large

**Investigation**:

```bash
# Check queue depth
psql -U relay sejilo -c \
  "SELECT recipient_id, COUNT(*) as pending FROM messages \
   WHERE status='queued' GROUP BY recipient_id ORDER BY pending DESC LIMIT 10;"

# Check message age
psql -U relay sejilo -c \
  "SELECT recipient_id, \
          COUNT(*) as count, \
          MAX(created_at) as newest, \
          MIN(created_at) as oldest \
   FROM messages WHERE status='queued' \
   GROUP BY recipient_id ORDER BY oldest ASC LIMIT 10;"
```

**Resolution**:

- Wait for recipients to come online (auto-delivered)
- Manually delete stale messages (>24 hours):
  ```sql
  DELETE FROM messages WHERE status='queued' AND created_at < NOW() - INTERVAL 24 HOURS;
  ```
- Investigate slow recipients (check network connectivity)

---

## Disaster Recovery

### Backup Strategy

**3-2-1 Rule**:
- 3 copies of data
- 2 different media types
- 1 offsite

**Implementation**:

```
Primary database → Local SSD (database)
              ↓
         Daily backup → NAS (network storage)
              ↓
         AWS S3 (cloud, encrypted)
```

### Recovery Time Objectives (RTO/RPO)

| Scenario | RTO | RPO | Notes |
|----------|-----|-----|-------|
| Relay process crash | 5 min | <1 min | Automatic restart |
| Single relay server lost | 30 min | <1 hour | Failover to backup |
| Data center loss | 4 hours | <24 hours | Restore from cloud backup |
| Widespread DoS | 1 hour | <1 min | Activate DDoS protection |

### Failover Procedure

**Scenario**: Primary relay server fails; failover to secondary.

```bash
# On backup relay server:

# 1. Restore latest database backup
sudo -u relay psql sejilo < /backups/sejilo/db-latest.sql.gz

# 2. Restore configuration
tar xzf /backups/sejilo/config-latest.tar.gz -C /

# 3. Start relay service
sudo systemctl start sejilo-relay

# 4. Update DNS to point to backup server
# Edit DNS records: relay.example.com A 192.0.2.2 (backup IP)

# 5. Verify operation
curl -k https://relay.example.com:9000/health

# 6. Monitor logs
sudo tail -f /var/log/sejilo/relay.log
```

### Data Loss Scenario

**If database is corrupted**:

1. **Stop relay immediately**:
   ```bash
   sudo systemctl stop sejilo-relay
   ```

2. **Restore from backup**:
   ```bash
   # Restore to point-in-time before corruption
   pg_restore -d sejilo /backups/sejilo/db-backup.dump
   ```

3. **Verify data integrity**:
   ```bash
   psql -U relay sejilo -c "SELECT COUNT(*) FROM messages;"
   psql -U relay sejilo -c "SELECT COUNT(*) FROM devices;"
   ```

4. **Start relay**:
   ```bash
   sudo systemctl start sejilo-relay
   ```

5. **Notify users**:
   - "Relay server recovered; some messages may have been lost"
   - Direct them to use offline mesh communication if relay is unreliable

---

## Best Practices

### Security

1. **Rotate TLS certificates** quarterly (or use auto-renewal)
2. **Keep relay software updated** (security patches within 1 week)
3. **Restrict relay access** by firewall (whitelist authorized IPs if possible)
4. **Monitor for unauthorized access** (review auth logs daily)
5. **Use strong PostgreSQL passwords** (minimum 20 characters)

### Performance

1. **Size database connection pool** based on expected load
2. **Monitor query performance** (slow query log)
3. **Implement caching** for frequently accessed data
4. **Use CDN** if distributing relay across regions

### Reliability

1. **Run in production mode** (not development)
2. **Enable automatic restarts** via systemd
3. **Test backup/recovery monthly**
4. **Use load balancing** for multiple relay instances
5. **Plan for capacity growth** (monitor trends)

---

## Version Information

- **Runbook Version**: 1.0
- **SejiloChat Relay**: 1.0+
- **Last Updated**: August 2024
