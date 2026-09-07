FROM python:3.12-slim

WORKDIR /app

# podman CLI is needed so the dashboard can start/stop tool containers
# (lazy-start) via `podman-compose`. We mount the host's podman API socket
# in and point CONTAINER_HOST at it (set in core/dashboard/docker-compose.yml).
RUN apt-get update && apt-get install -y --no-install-recommends \
    podman curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt podman-compose

COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
