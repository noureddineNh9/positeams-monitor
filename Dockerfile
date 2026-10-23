FROM alpine:3.22

RUN apk add --no-cache netcat-openbsd curl ca-certificates

WORKDIR /app

COPY monitor.sh /app/monitor.sh

RUN chmod +x /app/monitor.sh && mkdir -p /data

CMD ["/app/monitor.sh"]