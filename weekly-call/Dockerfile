# Techpathway BothCamp — main app (storefront + admin)
FROM python:3.11-slim

WORKDIR /app

# All dependencies (PyMySQL, Pillow, cryptography, gunicorn, boto3...) ship
# prebuilt wheels for this base image — no system build toolchain needed.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV FLASK_ENV=production \
    PYTHONUNBUFFERED=1

EXPOSE 5111

# /health is used by Docker/Kubernetes liveness & readiness probes
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0) if urllib.request.urlopen('http://localhost:5111/health').status==200 else sys.exit(1)"

# NOTE: this directory also contains gunicorn.conf.py, written for the EC2/
# systemd deploy path (it logs to /var/log/shopdb/, which doesn't exist in a
# container). Gunicorn auto-loads that file from the CWD, so we override its
# log paths on the command line — CLI flags win over the config file.
CMD ["gunicorn", "--bind", "0.0.0.0:5111", "--workers", "3", "--timeout", "30", \
     "--access-logfile", "-", "--error-logfile", "-", "wsgi:app"]
