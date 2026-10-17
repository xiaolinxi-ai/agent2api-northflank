# syntax=docker/dockerfile:1
# Agent2API official release v3.0.8; upstream commit 68d0a4e4bfd8dc5a1daa296c61e0cc0b10a871da.
# An independent MinIO addon provides persistence because the free volume is in use.
FROM litestream/litestream:0.5.17@sha256:4b02b9859a6b6b4087d8b8944e15f7e984bd7957cba322bbeee38b0e27b9656a AS replication
FROM aimodcc/agent2api:3.0.8@sha256:be62351d36716708ab50702a162bd13c54e6782cdb9dfecdac36a34003c87029
COPY --from=replication /usr/local/bin/litestream /usr/local/bin/litestream
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 && rm -rf /var/lib/apt/lists/*
COPY <<'YAML' /etc/litestream.yml
addr: "127.0.0.1:9090"
shutdown-sync-timeout: 20s
shutdown-sync-interval: 500ms
logging:
  level: info
  type: text
snapshot:
  interval: 1h
  retention: 24h
dbs:
  - path: /tmp/agent2api-data/agent2api.db
    monitor-interval: 1s
    replica:
      type: s3
      bucket: ${LITESTREAM_BUCKET}
      path: agent2api
      endpoint: ${LITESTREAM_ENDPOINT}
      region: us-east-1
      access-key-id: ${LITESTREAM_ACCESS_KEY_ID}
      secret-access-key: ${LITESTREAM_SECRET_ACCESS_KEY}
      force-path-style: true
      sign-payload: true
      sync-interval: 1s
YAML
COPY --chmod=755 <<'SH' /usr/local/bin/start-agent2api
#!/bin/sh
set -eu
umask 077
: "${LITESTREAM_ENDPOINT:?missing object store endpoint}"
: "${LITESTREAM_BUCKET:?missing object store bucket}"
: "${LITESTREAM_ACCESS_KEY_ID:?missing object store access key}"
: "${LITESTREAM_SECRET_ACCESS_KEY:?missing object store secret key}"
mkdir -p /tmp/agent2api-data
: "${AGENT2API_UPDATE_KEY_B64:?missing persistent update encryption key}"
printf '%s' "$AGENT2API_UPDATE_KEY_B64" | base64 -d > /tmp/agent2api-data/update-token.key
# MinIO stays private to this Northflank project. Do not print credentials.
status=$(curl --silent --show-error --connect-timeout 5 --max-time 30   --aws-sigv4 'aws:amz:us-east-1:s3'   --user "$LITESTREAM_ACCESS_KEY_ID:$LITESTREAM_SECRET_ACCESS_KEY"   --header 'x-amz-content-sha256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'   --request PUT --output /tmp/bucket-result.xml --write-out '%{http_code}'   "${LITESTREAM_ENDPOINT%/}/$LITESTREAM_BUCKET")
case "$status" in
  200|204) ;;
  409) grep -q '<Code>BucketAlreadyOwnedByYou</Code>' /tmp/bucket-result.xml || { echo 'Unexpected bucket conflict' >&2; exit 1; } ;;
  *) echo "Object storage initialization failed: HTTP $status" >&2; exit 1 ;;
esac
# Fail startup on a restore error. A missing replica is allowed only for first use.
litestream restore -config /etc/litestream.yml -if-db-not-exists -if-replica-exists /tmp/agent2api-data/agent2api.db
# Litestream supervises the app and flushes replication during graceful shutdown.
exec litestream replicate -config /etc/litestream.yml -exec /usr/local/bin/agent2api-server
SH
ENV AGENT2API_HOST=0.0.0.0 \
    AGENT2API_PROXY_PORT=3065 \
    AGENT2API_PROXY_HOME=/tmp/agent2api-data \
    AGENT2API_UI_DIR=/app/ui \
    AGENT2API_CAPTCHA_ENABLED=1 \
    AGENT2API_SELF_UPDATE=0
USER 10001:10001
ENTRYPOINT ["/usr/local/bin/start-agent2api"]
