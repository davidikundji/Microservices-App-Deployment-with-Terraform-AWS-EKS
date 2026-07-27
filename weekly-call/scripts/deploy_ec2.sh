#!/bin/bash
# deploy_ec2.sh — Deploy Techpathway BothCamp on EC2
# No domain needed — uses EC2 public IP + self-signed SSL
# Usage: bash scripts/deploy_ec2.sh
#
# What this does:
#   1. Installs all system packages
#   2. Sets up firewall
#   3. Creates app directory
#   4. Installs Python dependencies
#   5. Generates self-signed SSL cert
#   6. Configures Nginx
#   7. Sets up systemd service (auto-start on reboot)
#   8. Loads your database (RDS or SQLite)
#   9. Starts the app

set -e

# ── Get EC2 public IP ─────────────────────────────────────────────────────────
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_IP")
APP_DIR=/var/www/techpathway

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Techpathway BothCamp — EC2 Deployment"
echo "  Server IP: $PUBLIC_IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. System packages ────────────────────────────────────────────────────────
echo "[1/8] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-venv \
    nginx \
    openssl \
    mysql-client \
    ufw \
    curl \
    unzip
echo "  ✅  Packages installed"

# ── 2. Firewall ───────────────────────────────────────────────────────────────
echo "[2/8] Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
echo "  ✅  Firewall configured"

# ── 3. App directory ──────────────────────────────────────────────────────────
echo "[3/8] Setting up app directory..."
sudo mkdir -p $APP_DIR
sudo mkdir -p /var/log/techpathway
sudo chown -R ubuntu:www-data $APP_DIR
sudo chown -R ubuntu:ubuntu /var/log/techpathway
sudo chmod -R 755 $APP_DIR

# Copy all project files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
sudo cp -r $PROJECT_DIR/. $APP_DIR/
sudo chown -R ubuntu:www-data $APP_DIR
echo "  ✅  App files copied to $APP_DIR"

# ── 4. Python virtualenv ──────────────────────────────────────────────────────
echo "[4/8] Setting up Python environment..."
cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
echo "  ✅  Python environment ready"

# ── 5. Self-signed SSL ────────────────────────────────────────────────────────
echo "[5/8] Generating SSL certificate..."
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/techpathway.key \
    -out    /etc/nginx/ssl/techpathway.crt \
    -subj "/C=CA/ST=Alberta/L=Calgary/O=Techpathway BothCamp/CN=$PUBLIC_IP" \
    2>/dev/null
sudo chmod 600 /etc/nginx/ssl/techpathway.key
echo "  ✅  SSL certificate generated"

# ── 6. Nginx ──────────────────────────────────────────────────────────────────
echo "[6/8] Configuring Nginx..."
sudo tee /etc/nginx/sites-available/techpathway > /dev/null << NGINX
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $PUBLIC_IP;
    return 301 https://\$host\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $PUBLIC_IP;

    ssl_certificate     /etc/nginx/ssl/techpathway.crt;
    ssl_certificate_key /etc/nginx/ssl/techpathway.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # Upload size
    client_max_body_size 50M;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # Logs
    access_log /var/log/techpathway/nginx_access.log;
    error_log  /var/log/techpathway/nginx_error.log;

    # Static files served directly by Nginx
    location /static/ {
        alias $APP_DIR/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Everything else goes to Flask via Gunicorn
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_connect_timeout 10s;
        proxy_read_timeout    30s;
        proxy_send_timeout    30s;
    }

    # Block sensitive files
    location ~ /\.env { deny all; }
    location ~ /\.git  { deny all; }
    location ~* \.(sql|sh|bak|log)$ { deny all; }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/techpathway /etc/nginx/sites-enabled/techpathway
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
echo "  ✅  Nginx configured"

# ── 7. Environment file ───────────────────────────────────────────────────────
echo "[7/8] Setting up environment..."
if [ ! -f $APP_DIR/.env ]; then
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    cat > $APP_DIR/.env << ENV
# ── App ──────────────────────────────────────────────────────────────
SECRET_KEY=$SECRET
FLASK_ENV=production

# ── Amazon RDS MySQL ─────────────────────────────────────────────────
# Fill these in after creating your RDS instance
MYSQL_HOST=
MYSQL_PORT=3306
MYSQL_USER=admin
MYSQL_PASSWORD=
MYSQL_DB=shopdb

# ── Amazon S3 ────────────────────────────────────────────────────────
# Fill these in after creating your S3 bucket and IAM user
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1
S3_BUCKET=

# ── Rate limiting ─────────────────────────────────────────────────────
RATELIMIT_STORAGE_URL=memory://
ENV
    echo "  ✅  .env file created at $APP_DIR/.env"
fi

# ── 8. Systemd service ────────────────────────────────────────────────────────
echo "[8/8] Setting up systemd service..."
sudo tee /etc/systemd/system/techpathway.service > /dev/null << SERVICE
[Unit]
Description=Techpathway BothCamp — Flask App
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --workers 3 \\
    --bind 127.0.0.1:8000 \\
    --timeout 30 \\
    --access-logfile /var/log/techpathway/access.log \\
    --error-logfile /var/log/techpathway/error.log \\
    wsgi:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always
RestartSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable techpathway
sudo systemctl start techpathway
sleep 3

# ── Check status ──────────────────────────────────────────────────────────────
if sudo systemctl is-active --quiet techpathway; then
    STATUS="✅  Running"
else
    STATUS="⚠️  Check logs: sudo journalctl -u techpathway -n 50"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Deployment Complete!"
echo ""
echo "  Store:   https://$PUBLIC_IP/store"
echo "  Admin:   https://$PUBLIC_IP/"
echo "  Health:  https://$PUBLIC_IP/health"
echo ""
echo "  Status:  $STATUS"
echo ""
echo "  ⚠️  Browser will show SSL warning (self-signed)"
echo "     Click Advanced → Proceed to continue"
echo ""
echo "  Next — connect RDS + S3:"
echo "  sudo nano $APP_DIR/.env"
echo "  sudo systemctl restart techpathway"
echo ""
echo "  Useful commands:"
echo "  sudo journalctl -u techpathway -f    # live logs"
echo "  sudo systemctl restart techpathway   # restart"
echo "  sudo systemctl status techpathway    # status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
