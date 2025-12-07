# Firecrawl Production - Quick Reference

One-page cheat sheet for common operations.

## Deployment

```bash
# Initial deployment
cd /root/firecrawl-production
cp .env.example .env && nano .env
sudo ./scripts/deploy.sh

# Update deployment
git pull
docker-compose pull
docker-compose up -d
```

## Service Management

```bash
# View all services
docker-compose ps

# View logs
docker-compose logs -f
docker-compose logs -f api

# Restart services
docker-compose restart
docker-compose restart api
docker-compose restart gluetun

# Stop/Start all
docker-compose down
docker-compose up -d
```

## VPN Operations

```bash
# Check VPN IP
curl --proxy http://localhost:8888 https://api.ipify.org

# Force rotation
sudo systemctl start gluetun-rotator.service

# View rotation logs
tail -f /var/log/gluetun-rotation.log
sudo journalctl -u gluetun-rotator -f

# Rotation status
sudo systemctl status gluetun-rotator.timer
```

## Monitoring

```bash
# Access Grafana (from local machine)
ssh -L 3001:localhost:3001 root@SERVER_IP
# Open http://localhost:3001

# Access Prometheus
ssh -L 9090:localhost:9090 root@SERVER_IP
# Open http://localhost:9090

# Check health
curl http://localhost:3002/health
curl http://localhost:9090/-/healthy
curl http://localhost:3001/api/health
```

## Testing

```bash
# Test API
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://example.com"}'

# Test VPN routing
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://api.ipify.org"}' | jq -r '.data.content'
# Should match VPN IP, not server IP
```

## Backups

```bash
# Create backup
./scripts/backup.sh

# List backups
ls -lh backups/

# Restore database
docker run --rm -v firecrawl-plus-rotating-vpn_postgres_data:/data \
  -v $(pwd)/backups:/backup alpine \
  tar xzf /backup/firecrawl-backup-TIMESTAMP-postgres.tar.gz -C /data
```

## Troubleshooting

```bash
# Container won't start
docker-compose logs CONTAINER_NAME
docker-compose up -d CONTAINER_NAME

# High resource usage
docker stats
htop

# Check disk space
df -h

# Clean up Docker
docker system prune -a

# Restart everything
docker-compose down
sudo systemctl restart docker
docker-compose up -d
```

## Alerting

```bash
# Test Slack webhook
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert"}'

# View active alerts
curl http://localhost:9090/api/v1/alerts | jq

# Silence alert
# Via Alertmanager UI: http://localhost:9093
```

## Useful Paths

```
/root/firecrawl-production/          - Project root
/root/firecrawl-production/.env      - Configuration
/var/log/gluetun-rotation.log        - VPN rotation logs
/etc/systemd/system/gluetun-rotator* - Systemd service files
```

## Quick Checks

```bash
# All green?
docker-compose ps | grep -v Up && echo "Issues found" || echo "All running"

# VPN working?
curl --proxy http://localhost:8888 https://api.ipify.org && echo "VPN OK"

# API responding?
curl -s http://localhost:3002/health | jq -r '.status' # Should be "healthy"
```

## Emergency Procedures

### API is down
```bash
docker-compose restart api
docker-compose logs api --tail=50
```

### VPN not connecting
```bash
docker-compose restart gluetun
mullvad account get  # Check account active
```

### Out of disk space
```bash
docker system prune -a
rm -rf /var/log/*.log.*
```

### Complete restart
```bash
docker-compose down
sudo systemctl restart docker
sudo systemctl restart gluetun-rotator.timer
docker-compose up -d
```

## Performance Metrics

| Metric | Current | Warning | Critical |
|--------|---------|---------|----------|
| Requests/day | 70k | 200k | 250k |
| CPU Usage | <50% | >80% | >95% |
| Memory | <70% | >90% | >95% |
| Error Rate | <1% | >5% | >10% |
| Response Time (p95) | <10s | >30s | >60s |

## Access URLs

- **API**: http://SERVER_IP:3002
- **Grafana**: http://localhost:3001 (via SSH tunnel)
- **Prometheus**: http://localhost:9090 (via SSH tunnel)
- **Alertmanager**: http://localhost:9093 (via SSH tunnel)

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: GitHub Issues
- **Logs**: `docker-compose logs -f`
