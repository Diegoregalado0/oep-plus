#!/usr/bin/env bash
# Exercise every business rule in section 5, accepted and rejected cases.
# Runs in a transaction that is rolled back; seed data is left untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

# Reload the seed first so the demonstration starts from a known state.
./scripts/reset-db.sh >/dev/null

docker compose exec -T db psql -U oep -d oep -q -f - < db/05_rule_demo.sql 2>&1 \
  | sed 's/^psql:<stdin>:[0-9]*: NOTICE:  //'
