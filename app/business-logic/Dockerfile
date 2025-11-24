FROM python:3.11-slim

WORKDIR /app

# Install system dependencies and debugging tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    netcat-openbsd \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8081

# Run with gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8081", "--workers", "4", "--timeout", "60", "app:app"]
