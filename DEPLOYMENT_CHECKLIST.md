# Deployment Checklist

Step-by-step checklist for deploying Firecrawl Production infrastructure.

## Pre-Deployment

### ☐ Server Preparation

- [ ] DigitalOcean droplet created (Ubuntu 24.04)
- [ ] Server size: 4GB RAM minimum (recommended for 70k req/day)
- [ ] Region: NYC3 (or your preferred region)
- [ ] SSH access configured
- [ ] Root access available

### ☐ Mullvad VPN Account

- [ ] Active Mullvad account (subscription not expired)
- [ ] Account number saved: `____________________`
- [ ] Logged in via Mullvad CLI on server
- [ ] WireGuard private key obtained
- [ ] WireGuard IP address obtained (format: `10.x.x.x/32`)

### ☐ Alert Configuration (Optional but Recommended)

- [ ] Slack workspace access
- [ ] Slack webhook URL created: https://hooks.slack.com/services/...
- [ ] Email SMTP credentials ready (Gmail App Password or similar)
- [ ] Alert recipient email address: `____________________`

### ☐ Repository Setup

- [ ] Code cloned to `/root/firecrawl-production`
- [ ] Scripts are executable (`chmod +x scripts/*.sh`)
- [ ] `.env.example` reviewed

## Deployment Steps

### ☐ 1. Environment Configuration (10 minutes)

```bash
cd /root/firecrawl-production
cp .env.example .env
nano .env
```

Required values:
- [ ] `WIREGUARD_PRIVATE_KEY` = (your key from Mullvad)
- [ ] `WIREGUARD_ADDRESSES` = (your IP from Mullvad)
- [ ] `POSTGRES_PASSWORD` = (generate secure password)
- [ ] `GRAFANA_ADMIN_PASSWORD` = (generate secure password)
- [ ] `BULL_AUTH_KEY` = (generate random string)

Optional but recommended:
- [ ] `SLACK_WEBHOOK_URL` = (your webhook)
- [ ] `SMTP_HOST` = smtp.gmail.com (if using Gmail)
- [ ] `SMTP_PORT` = 587
- [ ] `SMTP_FROM` = (your email)
- [ ] `SMTP_USERNAME` = (your email)
- [ ] `SMTP_PASSWORD` = (Gmail App Password)
- [ ] `ALERT_EMAIL` = (where to send alerts)

### ☐ 2. Firewall Configuration

```bash
# Allow required ports
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 3002/tcp     # Firecrawl API
sudo ufw allow 51820/udp    # WireGuard
sudo ufw enable
sudo ufw status
```

- [ ] Firewall rules added
- [ ] Firewall enabled
- [ ] SSH access still works

### ☐ 3. Deploy Infrastructure

```bash
cd /root/firecrawl-production
sudo ./scripts/deploy.sh
```

Wait for deployment to complete (~5-10 minutes)

- [ ] Pre-flight checks passed
- [ ] Docker images pulled
- [ ] Systemd timer installed
- [ ] All services started
- [ ] Health checks passed

### ☐ 4. Verify Core Services

```bash
# Check all containers running
docker-compose ps
```

Expected output: All services showing "Up" status

- [ ] gluetun: Up (healthy)
- [ ] firecrawl-api: Up (healthy)
- [ ] firecrawl-playwright-service: Up (healthy)
- [ ] firecrawl-redis: Up
- [ ] firecrawl-postgres: Up
- [ ] nginx: Up (healthy)
- [ ] prometheus: Up (healthy)
- [ ] grafana: Up (healthy)
- [ ] alertmanager: Up (healthy)
- [ ] autoheal: Up
- [ ] node-exporter: Up
- [ ] cadvisor: Up

### ☐ 5. Verify VPN Connection

```bash
# Test proxy connection
curl --proxy http://localhost:8888 https://api.ipify.org
```

- [ ] Returns VPN IP (not your server IP)
- [ ] VPN IP is from NYC region

```bash
# Check rotation logs
tail -20 /var/log/gluetun-rotation.log
```

- [ ] Logs show successful connection
- [ ] VPN IP logged

### ☐ 6. Test Firecrawl API

```bash
# Health check
curl http://localhost:3002/health
```

Expected: `{"status":"healthy"}` or similar

- [ ] API responds
- [ ] Health status is good

```bash
# Test scrape
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://example.com"}'
```

- [ ] Returns scraped content
- [ ] Success: true
- [ ] No errors

```bash
# Test VPN routing (verify scrape uses VPN IP)
curl -X POST http://localhost:3002/v0/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://api.ipify.org"}' | jq -r '.data.content'
```

- [ ] Returns VPN IP (matches proxy test above)
- [ ] NOT your server's public IP

### ☐ 7. Access Monitoring

From your local machine:

```bash
# Create SSH tunnel
ssh -L 3001:localhost:3001 -L 9090:localhost:9090 root@YOUR_SERVER_IP
```

Open in browser:
- [ ] Grafana: http://localhost:3001 (login with admin / your_password)
- [ ] Prometheus: http://localhost:9090

In Grafana:
- [ ] Dashboard "Firecrawl Production Overview" loads
- [ ] API Status shows "UP" (green)
- [ ] VPN Status shows "CONNECTED" (green)
- [ ] Request rate shows data
- [ ] No errors in error rate panel

### ☐ 8. Verify Systemd Timer

```bash
# Check timer is active
sudo systemctl status gluetun-rotator.timer
```

- [ ] Timer is active and running
- [ ] Shows next rotation time

```bash
# Check timer logs
sudo journalctl -u gluetun-rotator -n 20
```

- [ ] No errors
- [ ] Shows rotation schedule

### ☐ 9. Test Alerts (If Configured)

```bash
# Trigger test alert
curl -X POST http://localhost:9093/api/v1/alerts -d '[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "warning"
  },
  "annotations": {
    "summary": "This is a test alert from Firecrawl deployment"
  }
}]'
```

- [ ] Alert appears in Alertmanager: http://localhost:9093
- [ ] Slack message received (if configured)
- [ ] Email received (if configured)

### ☐ 10. Create First Backup

```bash
cd /root/firecrawl-production
./scripts/backup.sh
```

- [ ] Backup completes without errors
- [ ] Files created in `backups/` directory
- [ ] Backup manifest created

### ☐ 11. Document Your Setup

Record these values for future reference:

```
Server IP: ____________________
Firecrawl API URL: http://YOUR_IP:3002
Grafana URL: http://localhost:3001 (via SSH tunnel)
Grafana Password: ____________________

Mullvad Account: ____________________
WireGuard IP: ____________________

Slack Channel: ____________________
Alert Email: ____________________

Backup Location: /root/firecrawl-production/backups/
Last Backup: ____________________

Deployment Date: ____________________
```

## Post-Deployment (24-48 Hours)

### ☐ Monitor Initial Operation

- [ ] Check Grafana dashboard twice daily
- [ ] Review VPN rotation logs
- [ ] Verify no critical alerts
- [ ] Confirm auto-recovery works (observe container restarts)

### ☐ Performance Baseline

Record initial metrics:
- [ ] Average requests/day: ____________________
- [ ] Average CPU usage: ____________________
- [ ] Average memory usage: ____________________
- [ ] p95 response time: ____________________
- [ ] Error rate: ____________________

### ☐ Tune Alerts (If Needed)

- [ ] Review alert thresholds in `monitoring/alerts.yml`
- [ ] Adjust if getting false positives
- [ ] Test critical alerts manually

### ☐ Schedule Regular Maintenance

Set calendar reminders:
- [ ] **Daily**: Check Grafana dashboard (2 min)
- [ ] **Weekly**: Review logs and backups (10 min)
- [ ] **Monthly**: Update Docker images (30 min)

## Scaling Preparation (Future)

When approaching capacity:

- [ ] Review [SCALING.md](docs/SCALING.md)
- [ ] Plan multi-droplet architecture
- [ ] Budget for additional servers
- [ ] Test load balancer setup

## Troubleshooting

If something doesn't work:

1. **Check logs**:
   ```bash
   docker-compose logs -f
   ```

2. **Restart services**:
   ```bash
   docker-compose restart
   ```

3. **Review documentation**:
   - [DEPLOYMENT.md](docs/DEPLOYMENT.md)
   - [MONITORING.md](docs/MONITORING.md)
   - [QUICK_REFERENCE.md](QUICK_REFERENCE.md)

4. **Common issues**:
   - VPN not working → Check Mullvad account status
   - API not responding → Check `.env` configuration
   - Containers restarting → Check `docker-compose logs`

## Success Criteria

✅ All checkboxes above completed
✅ API responding to requests
✅ VPN routing confirmed
✅ Monitoring dashboards accessible
✅ Alerts configured and tested
✅ Backup created successfully
✅ No critical errors in logs

**Congratulations! Your Firecrawl production infrastructure is deployed and operational.**

## Next Steps

1. Update DNS to point to your server (if using custom domain)
2. Configure API clients to use http://YOUR_SERVER_IP:3002
3. Monitor performance for 1 week
4. Plan scaling when approaching 200k requests/day
5. Set up SSL/HTTPS (see [SCALING.md](docs/SCALING.md))

---

**Deployment Date**: _______________
**Deployed By**: _______________
**Server IP**: _______________
**Status**: ☐ Complete ☐ In Progress ☐ Issues
