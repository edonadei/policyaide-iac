# Firecrawl Production Monitoring Guide

Complete guide to monitoring your Firecrawl deployment with Prometheus, Grafana, and Alertmanager.

## Overview

Your monitoring stack consists of:

- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization dashboards
- **Alertmanager** - Alert routing and notifications
- **Node Exporter** - System metrics (CPU, RAM, disk)
- **cAdvisor** - Container metrics
- **Autoheal** - Automatic container recovery

## Accessing Dashboards

### Grafana

```bash
# SSH tunnel from your local machine
ssh -L 3001:localhost:3001 root@YOUR_SERVER_IP

# Open in browser
http://localhost:3001

# Login credentials
Username: admin
Password: (from your .env file)
```

### Pre-built Dashboard

Navigate to **Dashboards → Firecrawl Production Overview**

This dashboard shows:
- API uptime status
- VPN connection status
- Request rate (req/sec)
- Success/error rates
- Response time percentiles (p50, p95, p99)
- CPU and memory usage
- Container restart rates

## Key Metrics to Monitor

### 1. API Health

**Metric**: `up{job="firecrawl-api"}`
- **Expected**: 1 (UP)
- **Alert**: Critical if down > 2 minutes
- **Action**: Check `docker-compose logs api`

**Metric**: `rate(http_requests_total{status=~"5.."}[5m])`
- **Expected**: < 5% error rate
- **Alert**: Warning if > 5% for 5 minutes
- **Action**: Check API logs for errors

### 2. VPN Health

**Metric**: `up{job="gluetun"}`
- **Expected**: 1 (UP)
- **Alert**: Critical if down > 3 minutes
- **Action**: Check rotation logs, Mullvad account status

**Metric**: `vpn_rotation_failures_total`
- **Expected**: 0-2 failures per hour
- **Alert**: Warning if > 3 failures in 1 hour
- **Action**: Verify Mullvad servers, check credentials

### 3. Performance

**Metric**: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`
- **Expected**: < 10s for p95
- **Alert**: Warning if > 30s for 5 minutes
- **Action**: Check resource usage, scale if needed

**Metric**: `rate(http_requests_total[5m])`
- **Expected**: ~0.8 req/sec (70k/day average)
- **Alert**: Info if > 100 req/sec (may need scaling)
- **Action**: Consider adding more droplets

### 4. Resource Usage

**Metric**: `rate(process_cpu_seconds_total[5m])`
- **Expected**: < 80%
- **Alert**: Warning if > 80% for 10 minutes
- **Action**: Optimize or scale up droplet

**Metric**: `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes`
- **Expected**: < 90%
- **Alert**: Warning if > 90% for 5 minutes
- **Action**: Check for memory leaks, restart services

### 5. Container Health

**Metric**: `container_health_status{state="unhealthy"}`
- **Expected**: 0
- **Alert**: Warning if > 0 for 2 minutes
- **Action**: Autoheal should restart, check logs if persists

## Alert Levels

### Critical (Immediate Action Required)

These alerts are sent to **both Slack and email**:

- `FirecrawlAPIDown` - API offline > 2 minutes
- `GluetunVPNDown` - VPN offline > 3 minutes
- `RedisDown` - Redis offline > 2 minutes
- `PostgresDown` - Database offline > 2 minutes
- `DiskSpaceLow` - < 10% disk space remaining

**Response**: Immediate investigation required. Check logs, restart services if needed.

### Warning (Action Needed Soon)

These alerts go to **Slack #alerts-warnings**:

- `FirecrawlHighErrorRate` - Error rate > 5% for 5 minutes
- `FirecrawlHighLatency` - p95 latency > 30s for 5 minutes
- `VPNRotationFailed` - > 3 rotation failures in 1 hour
- `ContainerUnhealthy` - Container unhealthy > 2 minutes
- `ContainerRestarting` - Frequent restarts (> 0.1/min for 5 min)
- `HighCPUUsage` - CPU > 80% for 10 minutes
- `HighMemoryUsage` - Memory > 90% for 5 minutes
- `QueueBacklog` - > 1000 pending jobs

**Response**: Investigate within 1-2 hours. May require optimization or scaling.

### Info (Awareness Only)

These alerts go to **Slack #alerts-info** (low frequency):

- `HighRequestVolume` - > 100 req/sec for 10 minutes
  - **Action**: Good problem to have! Plan scaling.

## Prometheus Queries

### Useful PromQL Queries

Access Prometheus at `http://localhost:9090` (via SSH tunnel)

```promql
# Current request rate (requests per second)
rate(http_requests_total[5m])

# Error rate percentage
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100

# Average response time
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# VPN uptime percentage (last 24 hours)
avg_over_time(up{job="gluetun"}[24h]) * 100

# Container CPU usage by container
rate(container_cpu_usage_seconds_total[5m]) * 100

# Memory usage by container
container_memory_working_set_bytes / container_spec_memory_limit_bytes * 100

# Disk I/O read rate
rate(node_disk_read_bytes_total[5m])

# Network traffic
rate(node_network_receive_bytes_total[5m])
```

## Grafana Custom Dashboards

### Creating a New Dashboard

1. Login to Grafana
2. Click **+ → Dashboard → Add new panel**
3. Enter PromQL query
4. Configure visualization
5. Save dashboard

### Recommended Custom Panels

**VPN Rotation History**
```promql
changes(vpn_last_rotation_timestamp[24h])
```
Shows how many times VPN rotated in last 24 hours.

**Request Volume Heatmap**
```promql
sum(rate(http_requests_total[5m])) by (hour_of_day)
```
Shows traffic patterns by hour.

**Top Error URLs**
```promql
topk(10, sum by (url) (rate(http_requests_total{status=~"5.."}[1h])))
```
Identifies problematic URLs.

## Alertmanager Configuration

### Slack Integration

Edit `monitoring/alertmanager.yml`:

```yaml
receivers:
  - name: 'slack-critical'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK'
        channel: '#alerts-critical'
        title: ':rotating_light: Critical Alert'
```

Create Slack channels:
- `#alerts-critical` - For critical alerts only
- `#alerts-warnings` - For warning-level alerts
- `#alerts-info` - For informational alerts

### Email Integration

For Gmail with 2FA:

1. Generate App Password: https://myaccount.google.com/apppasswords
2. Update `.env`:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_FROM=your-email@gmail.com
   SMTP_USERNAME=your-email@gmail.com
   SMTP_PASSWORD=your-16-char-app-password
   ALERT_EMAIL=destination@example.com
   ```
3. Restart: `docker-compose restart alertmanager`

### Testing Alerts

```bash
# Trigger test alert
curl -X POST http://localhost:9093/api/v1/alerts -d '[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "warning"
  },
  "annotations": {
    "summary": "This is a test alert"
  }
}]'

# Check if alert was sent to Slack/email
```

## Retention & Storage

### Prometheus Data Retention

Default: 30 days

To change, edit `docker-compose.yml`:

```yaml
prometheus:
  command:
    - '--storage.tsdb.retention.time=90d'  # Change to 90 days
```

### Disk Space Management

```bash
# Check current usage
docker exec prometheus du -sh /prometheus

# Clean old data manually (if needed)
docker exec prometheus rm -rf /prometheus/wal

# Check total disk space
df -h
```

## Performance Optimization

### If Prometheus is slow

1. **Reduce scrape interval** (edit `monitoring/prometheus.yml`):
   ```yaml
   global:
     scrape_interval: 30s  # From 15s
   ```

2. **Disable unused exporters**:
   ```bash
   # Comment out in docker-compose.yml
   # cadvisor:
   #   ...
   ```

3. **Reduce retention**:
   ```yaml
   - '--storage.tsdb.retention.time=15d'
   ```

### If Grafana is slow

1. **Increase cache** (edit `docker-compose.yml`):
   ```yaml
   grafana:
     environment:
       - GF_RENDERING_SERVER_URL=http://renderer:8081/render
       - GF_DATABASE_CACHE_ENABLED=true
   ```

2. **Use shorter time ranges** in dashboards (6h instead of 24h)

## Monitoring Best Practices

### Daily Checks

1. **Check Grafana dashboard** - Verify green status indicators
2. **Review error logs** - `docker-compose logs | grep ERROR`
3. **Verify VPN rotation** - `tail /var/log/gluetun-rotation.log`

### Weekly Checks

1. **Review alert history** - Are warnings becoming critical?
2. **Check disk space** - `df -h`
3. **Update Docker images** - `docker-compose pull`
4. **Review backup logs** - Ensure backups are running

### Monthly Checks

1. **Analyze traffic trends** - Are you hitting capacity?
2. **Review and tune alert thresholds**
3. **Update documentation** - Document any changes
4. **Security updates** - `apt update && apt upgrade`

## Troubleshooting Monitoring

### Prometheus not collecting metrics

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq

# All targets should show "up": true

# If target is down
docker-compose restart CONTAINER_NAME
```

### Grafana dashboard shows "No Data"

```bash
# Check Prometheus datasource
# Grafana → Configuration → Data Sources → Prometheus
# Click "Test" button

# Verify Prometheus is accessible
docker exec grafana curl http://prometheus:9090/-/healthy

# Restart Grafana
docker-compose restart grafana
```

### Alerts not firing

```bash
# Check alert rules are loaded
curl http://localhost:9090/api/v1/rules | jq

# Check Alertmanager is receiving alerts
curl http://localhost:9093/api/v1/alerts | jq

# Test Alertmanager config
docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
```

### Too many false alerts

Tune thresholds in `monitoring/alerts.yml`:

```yaml
- alert: FirecrawlHighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.10  # Increase from 0.05
  for: 10m  # Increase from 5m
```

Then reload Prometheus:

```bash
docker exec prometheus kill -HUP 1
```

## Additional Resources

- [Prometheus Query Language (PromQL)](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Alertmanager Routing](https://prometheus.io/docs/alerting/latest/configuration/)

## Next Steps

- [Scaling Guide](./SCALING.md) - When you need more capacity
- [Deployment Guide](./DEPLOYMENT.md) - Setup and configuration reference
