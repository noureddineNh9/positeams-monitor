#!/bin/sh
set -eu

: "${MYSQL_HOST:?MYSQL_HOST is required}"
: "${MYSQL_PORT:?MYSQL_PORT is required}"
: "${MAILGUN_API_KEY:?MAILGUN_API_KEY is required}"
: "${MAILGUN_DOMAIN:?MAILGUN_DOMAIN is required}"
: "${FROM_EMAIL:?FROM_EMAIL is required}"
: "${ALERT_EMAIL:?ALERT_EMAIL is required}"

CHECK_INTERVAL="${CHECK_INTERVAL:-300}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"
RETRY_DELAY="${RETRY_DELAY:-10}"
MAILGUN_REGION="${MAILGUN_REGION:-US}"
STATE_FILE="/data/status"
LOG_DIR="${LOG_DIR:-/logs}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"

for value in "$CHECK_INTERVAL" "$CHECK_TIMEOUT" "$RETRY_DELAY" "$MYSQL_PORT" "$LOG_RETENTION_DAYS"; do
  case "$value" in
    ''|*[!0-9]*)
      echo "Invalid numeric configuration: $value" >&2
      exit 1
      ;;
  esac
done

if [ "$CHECK_INTERVAL" -eq 0 ] || [ "$CHECK_TIMEOUT" -eq 0 ] || [ "$LOG_RETENTION_DAYS" -eq 0 ]; then
  echo 'CHECK_INTERVAL, CHECK_TIMEOUT, and LOG_RETENTION_DAYS must be greater than zero.' >&2
  exit 1
fi

case "$MAILGUN_REGION" in
  US|us) MAILGUN_HOST='api.mailgun.net' ;;
  EU|eu) MAILGUN_HOST='api.eu.mailgun.net' ;;
  *)
    echo 'MAILGUN_REGION must be US or EU.' >&2
    exit 1
    ;;
esac

mkdir -p "$LOG_DIR"
LAST_LOG_DATE=''

cleanup_logs() {
  find "$LOG_DIR" -type f -name 'monitor-*.log' \
    -mtime "+$LOG_RETENTION_DAYS" -exec rm -f '{}' ';'
}

log() {
  current_log_date="$(date -u '+%Y-%m-%d')"

  if [ "$current_log_date" != "$LAST_LOG_DATE" ]; then
    cleanup_logs
    LAST_LOG_DATE="$current_log_date"
  fi

  printf '[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$*" \
    | tee -a "${LOG_DIR}/monitor-${current_log_date}.log"
}

read_state() {
  if [ -r "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    printf 'unknown\n'
  fi
}

save_state() {
  printf '%s\n' "$1" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

check_connection() {
  nc -zv -w "$CHECK_TIMEOUT" "$MYSQL_HOST" "$MYSQL_PORT" >/dev/null 2>&1
}

send_email() {
  subject="$1"
  message="$2"

  curl --silent --show-error --fail \
    --connect-timeout 5 --max-time 20 \
    --retry 2 --retry-delay 2 \
    --user "api:${MAILGUN_API_KEY}" \
    --form-string "from=${FROM_EMAIL}" \
    --form-string "to=${ALERT_EMAIL}" \
    --form-string "subject=${subject}" \
    --form-string "text=${message}" \
    "https://${MAILGUN_HOST}/v3/${MAILGUN_DOMAIN}/messages" \
    --output /dev/null
}

log "Started monitoring ${MYSQL_HOST}:${MYSQL_PORT} every ${CHECK_INTERVAL}s"

while true; do
  healthy=false

  if check_connection; then
    healthy=true
  else
    log "TCP check failed; retrying in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"

    if check_connection; then
      healthy=true
    fi
  fi

  previous_state="$(read_state)"

  if [ "$healthy" = true ]; then
    log "MySQL TCP connection: OK"

    if [ "$previous_state" = down ]; then
      message="MySQL TCP connection recovered.
      Host: ${MYSQL_HOST}
      Port: ${MYSQL_PORT}
      Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

      if send_email "[RECOVERED] MySQL connection restored" "$message"; then
        save_state up
        log 'Recovery email accepted by Mailgun'
      else
        log 'ERROR: Recovery email failed; will retry at next check'
      fi

    elif [ "$previous_state" != up ]; then
      save_state up
    fi

  else
    log "MySQL TCP connection: FAILED (${MYSQL_HOST}:${MYSQL_PORT})"

    if [ "$previous_state" != down ]; then
      message="MySQL TCP connection failed twice.
      Host: ${MYSQL_HOST}
      Port: ${MYSQL_PORT}
      Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')

      This checks TCP connectivity from the application VPS, not MySQL query health."

      if send_email "[ALERT] MySQL connection failed" "$message"; then
        save_state down
        log 'Failure email accepted by Mailgun'
      else
        log 'ERROR: Failure email failed; will retry at next check'
      fi
    fi
  fi

  sleep "$CHECK_INTERVAL"
done
