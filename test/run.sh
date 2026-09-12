#!/usr/bin/env bash
# Self-check for action.yml. No framework: extract the real Release step, run it
# against a fake CLI, assert on the argv it built and the outputs it wrote.
#
#   ./test/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."

pass=0; fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export PATH="$PWD/test:$tmp/bin:$PATH"
mkdir -p "$tmp/bin"
ln -sf "$PWD/test/fake-one9x" "$tmp/bin/one9x"

python3 test/extract.py 'Release' > "$tmp/release.sh"

ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()  { fail=$((fail+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# run <json> <env assignments...> ; sets $ARGV and $OUT
run() {
  local json="$1"; shift
  printf '%s' "$json" > "$tmp/json"
  : > "$tmp/argv"; : > "$tmp/out"
  ARGV_OUT="$tmp/argv" JSON_IN="$tmp/json" GITHUB_OUTPUT="$tmp/out" \
  ONE9X_TOKEN="tok" SITE="mysite" DIR="$tmp/dist" \
  DEPLOY="false" SPA="false" COMMENT="false" INDEX="" ERROR_PAGES="" EXCLUDE="" TAG="" \
  env "$@" bash "$tmp/release.sh" >/dev/null 2>&1
  rc=$?
  ARGV=$(cat "$tmp/argv" 2>/dev/null)
  OUT=$(cat "$tmp/out" 2>/dev/null)
  return $rc
}

mkdir -p "$tmp/dist"
J='{"host":"mysite.one9x.app","version":"sha256:abc","seq":6,"live":false,"preview_url":"https://v6--mysite.one9x.app"}'

# --- the flags map through, and only the ones asked for ---------------------
run "$J"
[ "$ARGV" = "$(printf 'pages\nrelease\n%s\n--site\nmysite\n--json' "$tmp/dist")" ] \
  && ok "bare release passes only dir, site, json" \
  || no "bare release" "$ARGV"

run "$J" DEPLOY=true
grep -qx -- '--deploy' <<< "$ARGV" && ok "deploy=true adds --deploy" || no "deploy=true" "$ARGV"

run "$J" DEPLOY=false
grep -qx -- '--deploy' <<< "$ARGV" && no "deploy=false must not add --deploy" "$ARGV" || ok "deploy=false omits --deploy"

# Every optional flag off: the CLI must still be invoked, and the step must still
# succeed. (`set -e` ignores a failed AND-OR list member unless it is the last
# command, so the `&&` form would survive here too — what this pins down is that
# no future rewrite makes an unset flag fatal.)
run "$J" DEPLOY=false SPA=false
[ -n "$ARGV" ] && ok "every optional flag off still invokes the CLI" \
               || no "all-false inputs" "the CLI was never invoked"

run "$J" SPA=true
grep -qx -- '--spa' <<< "$ARGV" && ok "spa=true adds --spa" || no "spa=true" "$ARGV"

run "$J" INDEX=/install.sh
grep -qx -- '/install.sh' <<< "$ARGV" && ok "index passes through" || no "index" "$ARGV"

run "$J" TAG=prod
grep -qx -- 'prod' <<< "$ARGV" && ok "tag passes through" || no "tag" "$ARGV"

# --- multi-line inputs become repeated flags, blanks dropped ----------------
run "$J" ERROR_PAGES=$'404:/404.html\n\n500:/500.html'
[ "$(grep -cx -- '--error' <<< "$ARGV")" = 2 ] \
  && ok "error-pages: one --error per non-empty line" || no "error-pages" "$ARGV"

run "$J" EXCLUDE=$'*.map\n*.txt'
[ "$(grep -cx -- '--exclude' <<< "$ARGV")" = 2 ] \
  && ok "exclude: one --exclude per line" || no "exclude" "$ARGV"

run "$J" EXCLUDE=""
grep -qx -- '--exclude' <<< "$ARGV" && no "empty exclude must add nothing" "$ARGV" \
                                    || ok "empty multi-line input adds nothing"

# --- a path with a space survives (array, not string) ----------------------
mkdir -p "$tmp/my dist"
run "$J" DIR="$tmp/my dist"
grep -qx -- "$tmp/my dist" <<< "$ARGV" && ok "a dir containing a space stays one argv entry" \
                                       || no "dir with space" "$ARGV"

# --- outputs ---------------------------------------------------------------
run "$J"
grep -qx 'preview-url=https://v6--mysite.one9x.app' <<< "$OUT" && ok "preview-url output" || no "preview-url" "$OUT"
grep -qx 'seq=6' <<< "$OUT"      && ok "seq output"      || no "seq" "$OUT"
grep -qx 'live=false' <<< "$OUT" && ok "live output"     || no "live" "$OUT"

# THE OTHER REGRESSION THIS FILE EXISTS FOR: `url` is OMITTED when staging, and
# a bare `jq -r .url` would write the four characters "null" into the output,
# which then shows up in someone's summary as if it were a URL.
grep -qx 'url=' <<< "$OUT" && ok "absent url is empty, never the string null" \
                           || no "absent url" "$(grep '^url=' <<< "$OUT")"

run '{"host":"h","version":"sha256:abc","seq":7,"live":true,"url":"https://mysite.one9x.app"}'
grep -qx 'url=https://mysite.one9x.app' <<< "$OUT" && ok "live url output" || no "live url" "$OUT"
grep -qx 'preview-url=' <<< "$OUT" && ok "absent preview_url is empty" || no "absent preview_url" "$OUT"
grep -qx 'live=true' <<< "$OUT" && ok "live=true output" || no "live=true" "$OUT"

# Forward-compatible: the CLI does not emit `unchanged` yet (portal work is
# pending), so its absence must read as false rather than as "null".
grep -qx 'unchanged=false' <<< "$OUT" && ok "missing unchanged defaults to false" || no "unchanged" "$OUT"

run '{"host":"h","version":"sha256:abc","seq":6,"live":true,"url":"https://h","unchanged":true}'
grep -qx 'unchanged=true' <<< "$OUT" && ok "unchanged passes through when present" || no "unchanged=true" "$OUT"

# --- refusals name the fix -------------------------------------------------
run "$J" ONE9X_TOKEN="" && no "empty token must fail" "exit 0" || ok "empty token fails"
run "$J" DIR="$tmp/nope" && no "missing dir must fail" "exit 0" || ok "missing dir fails"

# CONFIGURATION ERRORS FAIL, THEY DO NOT DEGRADE. `deploy: yes` compares unequal
# to 'true', so a permissive check would read it as false and quietly STAGE a
# release meant to go live — a misconfiguration whose only symptom is the site
# not changing. Same for a value that merely looks boolean.
for bad in yes no 1 0 True TRUE ""; do
  if run "$J" DEPLOY="$bad"; then
    no "deploy=$bad must fail" "exited 0"
  else
    ok "deploy=${bad:-<empty>} is rejected, not coerced"
  fi
done
run "$J" SPA=yes  && no "spa=yes must fail" "exited 0"  || ok "spa=yes is rejected"
run "$J" COMMENT=1 && no "comment=1 must fail" "exited 0" || ok "comment=1 is rejected"

# …and the valid values still work, so the guard has not become a wall.
run "$J" DEPLOY=true  && ok "deploy=true still accepted"  || no "deploy=true" "rejected a valid value"
run "$J" DEPLOY=false && ok "deploy=false still accepted" || no "deploy=false" "rejected a valid value"

# spa and index are the same slot; passing both is a setup error, caught before
# the directory is hashed rather than after.
run "$J" SPA=true INDEX=/install.sh && no "spa+index must fail" "exited 0" \
                                    || ok "spa and index together are rejected"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
