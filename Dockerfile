# syntax=docker/dockerfile:1
# Agent2API official release v3.0.8; upstream commit 68d0a4e4bfd8dc5a1daa296c61e0cc0b10a871da.
# An independent MinIO addon provides persistence because the free volume is in use.
FROM litestream/litestream:0.5.17@sha256:4b02b9859a6b6b4087d8b8944e15f7e984bd7957cba322bbeee38b0e27b9656a AS replication
FROM aimodcc/agent2api:3.0.8@sha256:be62351d36716708ab50702a162bd13c54e6782cdb9dfecdac36a34003c87029
COPY --from=replication /usr/local/bin/litestream /usr/local/bin/litestream
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 && rm -rf /var/lib/apt/lists/*
COPY litestream.yml /etc/litestream.yml
COPY --chmod=755 start-agent2api.sh /usr/local/bin/start-agent2api
ENV AGENT2API_HOST=0.0.0.0 \
    AGENT2API_PROXY_PORT=3065 \
    AGENT2API_PROXY_HOME=/tmp/agent2api-data \
    AGENT2API_UI_DIR=/app/ui \
    AGENT2API_CAPTCHA_ENABLED=1 \
    AGENT2API_SELF_UPDATE=0
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/start-agent2api"]
