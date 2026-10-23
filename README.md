# Positeams Monitor

Self-hosted uptime monitoring powered by [Uptime Kuma](https://github.com/louislam/uptime-kuma). The service runs on the staging server and checks production from the staging network's point of view.

## Requirements

- Docker Engine
- Docker Compose v2 (`docker compose`)
- A local Docker volume; do not place Uptime Kuma's data on NFS

## Start Uptime Kuma

Create the local configuration file:

```bash
cp .env.example .env
```

Start the service:

```bash
docker compose up -d
docker compose ps
```

The dashboard listens on `127.0.0.1:3001` by default and is not directly reachable from the internet.

For initial access, open an SSH tunnel from your computer:

```bash
ssh -L 3001:127.0.0.1:3001 user@staging-server
```

Then visit <http://127.0.0.1:3001>, create the administrator account, use a strong password, and enable two-factor authentication.

For permanent browser access, place Uptime Kuma behind an HTTPS reverse proxy with WebSocket support. Prefer a dedicated hostname such as `monitor.example.com`; do not expose port `3001` publicly without firewall protection.

## Configure the first production monitor

In the Uptime Kuma dashboard, select **Add New Monitor** and use:

- Monitor type: `HTTP(s)`
- Friendly name: `Production Application`
- URL: the existing production website or API URL
- Method: `GET`
- Heartbeat interval: `60` seconds
- Request timeout: `5` seconds
- Retries: `2`
- Retry interval: `20` to `30` seconds
- Accepted status codes: `200-299`
- TLS verification: enabled

If possible, use an HTTP keyword monitor and require content unique to a successful application response. This detects generic error pages that incorrectly return HTTP 200.

Configure a notification under **Settings > Notifications**, test it, and explicitly assign it to the production monitor. For Mailgun SMTP, use Mailgun's SMTP hostname, username, and password; an HTTP API key is not necessarily an SMTP password.

Test the complete failure and recovery path before relying on the monitor. Temporarily use an invalid URL or port, confirm the DOWN alert, restore the URL, and confirm the recovery alert.

## Operations

View service status and logs:

```bash
docker compose ps
docker compose logs -f --tail=100 uptime-kuma
```

Stop or restart the service:

```bash
docker compose stop
docker compose restart uptime-kuma
```

## Persistent data and backups

Configuration, accounts, notification credentials, and monitoring history are stored in the Docker volume named `uptime-kuma-data` by default. Treat backups as sensitive.

If you change `UPTIME_KUMA_VOLUME_NAME`, use that same volume name in the backup command below.

Create a consistent backup by stopping Kuma briefly:

```bash
mkdir -p backups
docker compose stop uptime-kuma
docker run --rm \
  -v uptime-kuma-data:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine:3.22 \
  tar -czf "/backup/uptime-kuma-$(date -u +%Y%m%d-%H%M%S).tar.gz" -C /data .
docker compose start uptime-kuma
```

Copy backups away from the staging server. Before restoring, stop Kuma and restore into an empty data volume using a backup created from a compatible Uptime Kuma version.

## Updates

Back up the data volume first, review the Uptime Kuma release and migration notes, then run:

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose logs --tail=100 uptime-kuma
```

For stricter release control, set `UPTIME_KUMA_VERSION` in `.env` to a tested exact image tag instead of the major tag `2`.

## Important limitations

- A successful web check does not yet prove that MySQL is healthy.
- If staging or Uptime Kuma is down, it cannot send its own alerts.
- If staging and production share infrastructure, a common outage can affect both.
- Uptime Kuma provides availability monitoring, not application logs, tracing, or full infrastructure metrics.

After the initial monitor is proven, add a lightweight production API health endpoint that tests critical dependencies such as MySQL without exposing internal error details.
