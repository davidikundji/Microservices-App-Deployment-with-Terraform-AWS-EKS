#!/bin/bash
# start.sh — One command to run Techpathway BothCamp locally
# Usage: bash start.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Techpathway BothCamp — Starting..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install dependencies if needed
if [ ! -d "venv" ]; then
    echo "Setting up Python environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --quiet -r requirements.txt
else
    source venv/bin/activate
fi

# Create .env if missing
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "Created .env file — edit it to connect RDS + S3"
fi

echo ""
echo "  Store:  http://localhost:5111/store"
echo "  Admin:  http://localhost:5111/"
echo ""
echo "  NOTE: this only starts the main app. For notification-service and"
echo "  warehouse-service too (needed for order-confirm emails and the"
echo "  warehouse board), run ../run-local.sh from the repo root instead."
echo ""
echo "  Press Ctrl+C to stop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

python3 app.py
