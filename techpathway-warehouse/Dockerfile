# techpathway-warehouse — inventory + order fulfillment tracking
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1

EXPOSE 5002

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0) if urllib.request.urlopen('http://localhost:5002/health').status==200 else sys.exit(1)"

CMD ["gunicorn", "--bind", "0.0.0.0:5002", "--workers", "2", "--timeout", "30", "app:app"]
