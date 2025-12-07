#!/usr/bin/env python3
import subprocess
import re
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

# Get the gateway IP dynamically
def get_gateway_ip():
    try:
        result = subprocess.run(['ip', 'route', 'show', 'default'], 
                               capture_output=True, text=True, timeout=2)
        # Parse: default via 172.17.0.1 dev eth0
        match = re.search(r'default via ([\d.]+)', result.stdout)
        if match:
            return match.group(1)
    except:
        pass
    return 'host.docker.internal'

GATEWAY_IP = get_gateway_ip()
API_URL = f'http://{GATEWAY_IP}:3002/'
VPN_PROXY = f'http://{GATEWAY_IP}:8888'

print(f'Using gateway IP: {GATEWAY_IP}')
print(f'API URL: {API_URL}')
print(f'VPN Proxy: {VPN_PROXY}')

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            metrics = self.generate_metrics()
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            self.wfile.write(metrics.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def generate_metrics(self):
        metrics = []
        
        # Check API status
        try:
            result = subprocess.run(['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', 
                                    API_URL], 
                                    capture_output=True, timeout=5)
            http_code = result.stdout.decode().strip()
            api_up = 1 if http_code and http_code != '000' else 0
        except:
            api_up = 0
        
        metrics.append(f'# HELP firecrawl_api_up API availability (1 = up, 0 = down)')
        metrics.append(f'# TYPE firecrawl_api_up gauge')
        metrics.append(f'firecrawl_api_up {api_up}')
        
        # Check VPN status
        try:
            result = subprocess.run(['curl', '-s', '--proxy', VPN_PROXY, 
                                    'https://api.ipify.org'], 
                                    capture_output=True, timeout=5)
            vpn_ip = result.stdout.decode().strip()
            vpn_up = 1 if vpn_ip and vpn_ip != '138.197.91.30' and len(vpn_ip) > 0 else 0
        except:
            vpn_up = 0
        
        metrics.append(f'# HELP firecrawl_vpn_connected VPN connection status (1 = connected, 0 = disconnected)')
        metrics.append(f'# TYPE firecrawl_vpn_connected gauge')
        metrics.append(f'firecrawl_vpn_connected {vpn_up}')
        
        # Count total requests from API logs
        try:
            result = subprocess.run(['docker', 'logs', '--tail', '10000', 'firecrawl-api'], 
                                    capture_output=True, timeout=10)
            logs = result.stdout.decode() + result.stderr.decode()
            request_count = len(re.findall(r'POST /v[12]/scrape', logs))
        except:
            request_count = 0
        
        metrics.append(f'# HELP firecrawl_requests_total Total number of scrape requests')
        metrics.append(f'# TYPE firecrawl_requests_total counter')
        metrics.append(f'firecrawl_requests_total {request_count}')
        
        return '\n'.join(metrics) + '\n'
    
    def log_message(self, format, *args):
        pass  # Suppress access logs

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 9101), MetricsHandler)
    print('Metrics exporter running on port 9101')
    server.serve_forever()
