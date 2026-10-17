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
