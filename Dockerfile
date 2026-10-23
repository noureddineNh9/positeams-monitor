FROM alpine:3.22

RUN apk add --no-cache netcat-openbsd curl ca-certificates

WORKDIR /app

COPY mysql-monitor.sh /app/mysql-monitor.sh

RUN chmod +x /app/mysql-monitor.sh && mkdir -p /data

CMD ["/app/mysql-monitor.sh"]
