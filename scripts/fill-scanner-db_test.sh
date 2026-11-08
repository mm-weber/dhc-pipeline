#!/usr/bin/env bash
# Tests for scripts/fill-scanner-db.sh: the vulnerability database's origin and
# timestamp, written into a cosign-vuln predicate right after conversion
# (Req 6.55, ledger row 6.55).
#
# Why the script exists: `trivy convert --format cosign-vuln` leaves
# scanner.db.uri and scanner.db.version empty (measured on trivy 0.72.0 and
# 0.75.0), so the attested report names the scanner but not the database it
# matched against, and a consumer cannot tell findings from a week-old database
# apart from findings from today's. Two facts on the runner close that gap: the
# database's UpdatedAt, which `trivy version --format json` reports, and the
# repository it was pulled from, which trivy never records anywhere, so the
# pinned TRIVY_DB_REPOSITORY is the only honest source for the origin.
#
# Trivy is stubbed here. What this suite pins is which fields are filled, from
# which facts, and that nothing else in the predicate moves: the result is
# compared as parsed JSON against a pristine copy carrying the two expected
# values, since a rewrite may legitimately reformat the file.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FILL="$HERE/fill-scanner-db.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
expect() { # name, expected rc, actual rc, output, needles...
  local name="$1" want="$2" rc="$3" out="$4"; shift 4
  if [ "$rc" -ne "$want" ]; then fail "$name" "exit=$rc, wanted $want" "$out"; return; fi
  local n; for n in "$@"; do
    if ! grep -qF -- "$n" <<<"$out"; then fail "$name" "missing '$n'" "$out"; return; fi
  done
  pass "$name"
}

DB_REPO="ghcr.io/aquasecurity/trivy-db:2"
DB_UPDATED="2026-10-15T07:10:08.755380281Z"

fresh() { # a sandbox with a stub trivy and a converted, unfilled predicate
  SB=$(mktemp -d); mkdir -p "$SB/bin"
  # The database timestamp is the only thing the script may ask trivy for; any
  # other invocation is a design error and is refused loudly.
  cat > "$SB/bin/trivy" <<'STUB'
#!/usr/bin/env bash
if [ "$*" = "version --format json" ]; then
  cat <<'JSON'
{"Version":"0.72.0","VulnerabilityDB":{"Version":2,"NextUpdate":"2026-10-15T13:10:08.755380281Z","UpdatedAt":"2026-10-15T07:10:08.755380281Z","DownloadedAt":"2026-10-15T08:02:41.418203117Z"}}
JSON
  exit 0
fi
echo "stub trivy: unexpected arguments: $*" >&2
exit 1
STUB
  chmod +x "$SB/bin/trivy"
  # What `trivy convert --format cosign-vuln` writes: the scanner named, its
  # database not, and the whole report nested under scanner.result.
  cat > "$SB/vuln.json" <<'JSON'
{
  "invocation": {
    "parameters": null,
    "uri": "",
    "event_id": "",
    "builder.id": ""
  },
  "scanner": {
    "uri": "pkg:github/aquasecurity/trivy@0.72.0",
    "version": "0.72.0",
    "db": {
      "uri": "",
      "version": ""
    },
    "result": {
      "SchemaVersion": 2,
      "CreatedAt": "2026-10-15T09:14:02.113498217Z",
      "ArtifactName": "ghcr.io/mm-weber/dhc/valkey@sha256:7f0a4a1c0f1b1d2e3c4b5a6978899aabbccddeeff00112233445566778899aab",
      "ArtifactType": "container_image",
      "Metadata": {
        "OS": {
          "Family": "alpine",
          "Name": "3.23.0"
        },
        "ImageID": "sha256:1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
        "DiffIDs": [
          "sha256:2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c"
        ]
      },
      "Results": [
        {
          "Target": "ghcr.io/mm-weber/dhc/valkey (alpine 3.23.0)",
          "Class": "os-pkgs",
          "Type": "alpine",
          "Vulnerabilities": [
            {
              "VulnerabilityID": "CVE-2026-111943",
              "PkgID": "libcrypto3@3.6.1-r0",
              "PkgName": "libcrypto3",
              "InstalledVersion": "3.6.1-r0",
              "FixedVersion": "3.6.2-r0",
              "Status": "fixed",
              "Severity": "HIGH",
              "Title": "openssl: certificate verification flaw",
              "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2026-111943"
            }
          ]
        }
      ]
    }
  },
  "metadata": {
    "scanStartedOn": "2026-10-15T09:14:02Z",
    "scanFinishedOn": "2026-10-15T09:14:11Z"
  }
}
JSON
  cp "$SB/vuln.json" "$SB/pristine.json"
}

# 1: the declared origin and the reported timestamp land in scanner.db, and the
#    rest of the predicate is left exactly as the conversion wrote it.
fresh
out=$(TRIVY_DB_REPOSITORY="$DB_REPO" PATH="$SB/bin:$PATH" "$FILL" "$SB/vuln.json" 2>&1); rc=$?
report=$(python3 - "$SB/vuln.json" "$SB/pristine.json" "$DB_REPO" "$DB_UPDATED" <<'PY' 2>&1
import json, sys

filled_path, pristine_path, want_uri, want_version = sys.argv[1:5]
try:
    filled = json.load(open(filled_path))
except Exception as exc:                      # an unreadable result is a failure, not a crash
    print("the document could not be read back: %s" % exc)
    raise SystemExit(0)
pristine = json.load(open(pristine_path))

db = filled.get("scanner", {}).get("db", {})
print('db.uri = "%s"' % db.get("uri"))
print('db.version = "%s"' % db.get("version"))

def differences(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        out = []
        for k in sorted(set(a) | set(b)):
            if k not in a:
                out.append(path + "/" + k + " (removed)")
            elif k not in b:
                out.append(path + "/" + k + " (added)")
            else:
                out += differences(a[k], b[k], path + "/" + k)
        return out
    return [] if a == b else [path or "/"]

pristine.setdefault("scanner", {})["db"] = {"uri": want_uri, "version": want_version}
rest = differences(filled, pristine)
if rest:
    print("the rest of the document changed: %s" % ", ".join(rest))
else:
    print("the rest of the document is unchanged")
PY
)
expect "fills the database origin and timestamp, nothing else" 0 "$rc" "$out
$report" \
  "db.uri = \"$DB_REPO\"" \
  "db.version = \"$DB_UPDATED\"" \
  "the rest of the document is unchanged"

# 2: a database origin that was never declared stops the step by name, and the
#    predicate is left exactly as it was. An absent TRIVY_DB_REPOSITORY lands
#    as an empty db.uri, which attests a claim about the database's origin that
#    says nothing while looking filled, so the missing fact has to refuse by
#    name rather than be written as emptiness (Req 6.55). Unset and set-to-empty
#    are the same missing fact and are refused alike; the file is compared with
#    cmp here, not as parsed JSON, because nothing should have been rewritten at
#    all, not even reformatted.
report=""
accepted=0
for shape in unset empty; do
  fresh
  if [ "$shape" = unset ]; then
    out=$(env -u TRIVY_DB_REPOSITORY PATH="$SB/bin:$PATH" "$FILL" "$SB/vuln.json" 2>&1); rc=$?
  else
    out=$(TRIVY_DB_REPOSITORY="" PATH="$SB/bin:$PATH" "$FILL" "$SB/vuln.json" 2>&1); rc=$?
  fi
  if [ "$rc" -ne 0 ]; then verdict="refused (exit $rc)"; else verdict="accepted (exit 0)"; accepted=$((accepted+1)); fi
  if grep -qF -- "TRIVY_DB_REPOSITORY" <<<"$out"; then named_var=yes; else named_var=no; fi
  if grep -qF -- "Req 6.55" <<<"$out"; then named_req=yes; else named_req=no; fi
  if cmp -s "$SB/vuln.json" "$SB/pristine.json"; then state=untouched; else state=rewritten; fi
  report="$report
$shape: $verdict
$shape: names TRIVY_DB_REPOSITORY: $named_var
$shape: names Req 6.55: $named_req
$shape: predicate $state
$shape: said: $out"
done
# The exit slot carries how many of the two invocations the script accepted: a
# fact it was never given must stop the step both times, so that count is 0.
expect "an undeclared database origin is refused by name, the predicate untouched" 0 "$accepted" "$report" \
  "unset: refused" \
  "unset: names TRIVY_DB_REPOSITORY: yes" \
  "unset: names Req 6.55: yes" \
  "unset: predicate untouched" \
  "empty: refused" \
  "empty: names TRIVY_DB_REPOSITORY: yes" \
  "empty: names Req 6.55: yes" \
  "empty: predicate untouched"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all fill-scanner-db tests passed"
