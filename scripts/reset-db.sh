#!/usr/bin/env bash
# Rebuild the database from scratch and load seed data.
set -euo pipefail
cd "$(dirname "$0")/.."

psql_run() { docker compose exec -T -e PGOPTIONS='-c client_min_messages=warning' db psql -U oep -d oep -v ON_ERROR_STOP=1 -q; }

echo "waiting for postgres..."
for _ in $(seq 1 30); do
  docker compose exec -T db pg_isready -U oep -d oep >/dev/null 2>&1 && break
  sleep 1
done

for f in db/01_schema.sql db/02_rules.sql db/03_views.sql db/04_seed.sql; do
  echo "applying $f"
  psql_run < "$f"
done
echo "database ready"
