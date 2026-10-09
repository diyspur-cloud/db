#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-auto}"

case "$MODE" in
  --reduced|reduced)
    exec node "$ROOT/scripts/replay-local.mjs" --reduced
    ;;
  --full|full)
    FULL=1
    ;;
  auto)
    FULL=0
    if command -v docker >/dev/null 2>&1 && timeout 5 docker info >/dev/null 2>&1; then
      FULL=1
    fi
    if [[ "$FULL" == 0 ]]; then
      echo "INFO: Docker is unavailable; running reduced PGlite replay (not full Supabase)."
      exec node "$ROOT/scripts/replay-local.mjs" --reduced
    fi
    ;;
  --help|-h)
    cat <<'USAGE'
Usage: scripts/replay-local.sh [auto|--reduced|--full]

  auto      use a disposable Docker/Supabase replay when Docker is reachable;
            otherwise use the existing PGlite reduced replay (default)
  --reduced run only the PGlite replay; it never reaches a remote project
  --full    copy Supabase migrations to a temporary directory, apply the
            replay correction in that copy, reset/query only the local stack,
            then load and validate seed.sql and seed_complement.sql twice

The historical migration in this repository is never edited and no --linked,
--db-url, or remote Supabase command is used.
USAGE
    exit 0
    ;;
  *)
    echo "ERROR: unknown mode '$MODE' (use --help)" >&2
    exit 2
    ;;
esac

if command -v supabase >/dev/null 2>&1; then
  SUPABASE_CLI=(supabase)
elif command -v npx >/dev/null 2>&1; then
  SUPABASE_CLI=(npx --yes supabase@2.120.0)
else
  echo "ERROR: --full requires the Supabase CLI or npx." >&2
  exit 2
fi
if ! command -v docker >/dev/null 2>&1 || ! timeout 5 docker info >/dev/null 2>&1; then
  echo "ERROR: --full requires a reachable Docker daemon; use --reduced when Docker is absent." >&2
  exit 2
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/diyspur-replay.XXXXXX")"
cleanup() {
  "${SUPABASE_CLI[@]}" stop --workdir "$TMP_ROOT" --no-backup >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

# Full mode uses a disposable copy. The source migration is corrected exactly
# once in that copy before the local reset; the tracked historical file stays
# untouched and no migration repair/history operation is run.
cp -a "$ROOT/supabase" "$TMP_ROOT/supabase"
python3 - "$TMP_ROOT/supabase/migrations/20261008214920_add_community_reading_views.sql" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "s.title as current_season_title"
new = "current_season.title as current_season_title"
if text.count(old) != 1:
    raise SystemExit(f"expected one known replay defect in {path}, found {text.count(old)}")
path.write_text(text.replace(old, new))
PY

"${SUPABASE_CLI[@]}" start --workdir "$TMP_ROOT"
"${SUPABASE_CLI[@]}" db reset --local --workdir "$TMP_ROOT" --yes --no-seed

# Seeds are loaded explicitly rather than relying only on db reset's implicit
# seed phase. Replaying both files twice proves the guards are idempotent.
for pass in 1 2; do
  echo "INFO: loading seed.sql and seed_complement.sql (pass $pass)"
  "${SUPABASE_CLI[@]}" db query --local --workdir "$TMP_ROOT" --file "$ROOT/supabase/seed.sql"
  "${SUPABASE_CLI[@]}" db query --local --workdir "$TMP_ROOT" --file "$ROOT/supabase/seed_complement.sql"
done
"${SUPABASE_CLI[@]}" db query --local --workdir "$TMP_ROOT" --file "$ROOT/scripts/replay-local.seed-check.sql"
"${SUPABASE_CLI[@]}" db query --local --workdir "$TMP_ROOT" --file "$ROOT/supabase/tests/sdd_contract.test.sql"
echo "RESULT: FULL local Supabase/Docker replay + double seed validation PASS (temporary copy only; no remote target)"
