#!/bin/bash
set -euo pipefail

#######################################
# Firecrawl Production Deployment Script
# Deploys entire stack to server
#######################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/.env"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Firecrawl Production Deployment${NC}"
echo -e "${GREEN}========================================${NC}"

# Pre-flight checks
echo -e "\n${YELLOW}Running pre-flight checks...${NC}"

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}ERROR: .env file not found!${NC}"
    echo "Please create .env from .env.example and fill in required values"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not running!${NC}"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}ERROR: docker-compose is not installed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Pre-flight checks passed"

# Stop existing services
echo -e "\n${YELLOW}Stopping existing services...${NC}"
cd "$PROJECT_ROOT"
docker-compose down || true
echo -e "${GREEN}✓${NC} Services stopped"

# Pull latest images
echo -e "\n${YELLOW}Pulling latest Docker images...${NC}"
docker-compose pull
echo -e "${GREEN}✓${NC} Images pulled"

# Build custom images if needed
echo -e "\n${YELLOW}Building custom images...${NC}"
docker-compose build
echo -e "${GREEN}✓${NC} Images built"

# Create required directories
echo -e "\n${YELLOW}Creating required directories...${NC}"
mkdir -p /var/log
mkdir -p /var/lib/gluetun
echo -e "${GREEN}✓${NC} Directories created"

# Install systemd services
echo -e "\n${YELLOW}Installing systemd timer for VPN rotation...${NC}"
if [ -f "/etc/systemd/system/gluetun-rotator.service" ]; then
    sudo systemctl stop gluetun-rotator.timer || true
    sudo systemctl disable gluetun-rotator.timer || true
fi

sudo cp "${SCRIPT_DIR}/gluetun-rotator.service" /etc/systemd/system/
sudo cp "${SCRIPT_DIR}/gluetun-rotator.timer" /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/gluetun-rotator.{service,timer}
sudo systemctl daemon-reload
sudo systemctl enable gluetun-rotator.timer
sudo systemctl start gluetun-rotator.timer
echo -e "${GREEN}✓${NC} Systemd timer installed"

# Make scripts executable
echo -e "\n${YELLOW}Making scripts executable...${NC}"
chmod +x "${SCRIPT_DIR}"/*.sh
echo -e "${GREEN}✓${NC} Scripts are executable"

# Start services
echo -e "\n${YELLOW}Starting all services...${NC}"
docker-compose up -d
echo -e "${GREEN}✓${NC} Services started"

# Wait for services to be healthy
echo -e "\n${YELLOW}Waiting for services to be healthy (60s)...${NC}"
sleep 60

# Health checks
echo -e "\n${YELLOW}Running health checks...${NC}"

# Check Gluetun
if docker ps | grep -q gluetun; then
    VPN_IP=$(timeout 10 curl -s --proxy http://localhost:8888 https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$VPN_IP" ]; then
        echo -e "${GREEN}✓${NC} Gluetun VPN: Connected (IP: $VPN_IP)"
    else
        echo -e "${YELLOW}⚠${NC} Gluetun VPN: Running but unable to verify IP"
    fi
else
    echo -e "${RED}✗${NC} Gluetun VPN: Not running"
fi

# Check Firecrawl API
if curl -s http://localhost:3002/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Firecrawl API: Healthy"
else
    echo -e "${RED}✗${NC} Firecrawl API: Not responding"
fi

# Check Prometheus
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Prometheus: Healthy"
else
    echo -e "${YELLOW}⚠${NC} Prometheus: Not responding"
fi

# Check Grafana
if curl -s http://localhost:3001/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Grafana: Healthy"
else
    echo -e "${YELLOW}⚠${NC} Grafana: Not responding"
fi

# Display access information
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Service Access:${NC}"
echo "  Firecrawl API:  http://localhost:3002"
echo "  Grafana:        http://localhost:3001 (admin / check .env for password)"
echo "  Prometheus:     http://localhost:9090"
echo "  Alertmanager:   http://localhost:9093"
echo -e "\n${YELLOW}Useful Commands:${NC}"
echo "  View logs:           docker-compose logs -f"
echo "  View rotation logs:  tail -f /var/log/gluetun-rotation.log"
echo "  Check services:      docker-compose ps"
echo "  Restart service:     docker-compose restart <service>"
echo "  Force VPN rotation:  sudo systemctl start gluetun-rotator.service"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo "  1. Access Grafana and verify dashboards are loading"
echo "  2. Configure Alertmanager with your Slack webhook"
echo "  3. Test API endpoint: curl http://localhost:3002/v0/scrape -H 'Content-Type: application/json' -d '{\"url\": \"https://example.com\"}'"
echo "  4. Monitor VPN rotations: sudo journalctl -u gluetun-rotator -f"
echo ""
