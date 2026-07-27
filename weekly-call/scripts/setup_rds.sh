#!/bin/bash
# setup_rds.sh — Load schema into RDS and connect the app
# Run this AFTER deploy_ec2.sh and AFTER filling in .env
# Usage: bash scripts/setup_rds.sh

set -e
APP_DIR=/var/www/techpathway

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Techpathway — RDS Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Load .env
source $APP_DIR/.env

if [ -z "$MYSQL_HOST" ]; then
    echo "❌  MYSQL_HOST is empty in .env"
    echo "    Run: sudo nano $APP_DIR/.env"
    exit 1
fi

echo ""
echo "  Host:     $MYSQL_HOST"
echo "  Database: $MYSQL_DB"
echo "  User:     $MYSQL_USER"
echo ""

# Load schema into RDS
echo "Loading schema into RDS..."
mysql -h $MYSQL_HOST \
      -P $MYSQL_PORT \
      -u $MYSQL_USER \
      -p$MYSQL_PASSWORD \
      $MYSQL_DB < $APP_DIR/schema.sql

echo "  ✅  Schema and seed data loaded into RDS"

# Restart app to use RDS
echo "Restarting app..."
sudo systemctl restart techpathway
sleep 2

# Check
if sudo systemctl is-active --quiet techpathway; then
    echo "  ✅  App restarted — now using RDS MySQL"
else
    echo "  ❌  App failed to start"
    echo "      sudo journalctl -u techpathway -n 50"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  RDS connected and ready!"
echo ""
echo "  Your data is now live on Amazon RDS."
echo "  Upload images via Admin → they save to S3."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
