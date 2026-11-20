#!/usr/bin/env bash
# check-governance.sh <rulesets-dir> <owner/repo> <out.json>
#
# The daily governance invariants (task 13.2):
#
#   Req 9.3  private vulnerability reporting is enabled on the repository
#   Req 9.9  every committed ruleset under <rulesets-dir> matches its live
#            counterpart, and every active live branch ruleset has a
#            committed counterpart
#
# Every read is anonymous, no token: the comparison sees exactly what a
# consumer sees and needs no permission. Consequently `bypass_actors` is
# outside the compared set, because anonymous reads withhold it; the
# committed export carries it, SECURITY.md states it, and data/ holds the
# admin view.
#
# Anonymous reads share a limit of 60 an hour per network address, and a
# runner's address is shared with other GitHub customers, so a read can be
# answered "rate limit exceeded" through no fault of this repository. A read
# answered 403 or 429 with `x-ratelimit-remaining: 0` or a `retry-after`
# header is therefore waited out: one warning line, `sleep` until the reset
# (`x-ratelimit-reset`, or the seconds of `retry-after`) plus 5 seconds, then
# the same read again, still anonymous. The read is unreadable, with the rate
# limit named as the cause, when the wait would exceed
# DHC_GOVERNANCE_MAX_WAIT seconds (default 3900), when the answer names no
# reset, or when it is still rate-limited after two waits. Any other failure
# is unreadable at once. The record lists every wait under
# `rate_limit_waits`.
#
# If the waiting ever costs too much: the alternative that was considered and
# not built is to repeat a rate-limited read with the workflow's own token,
# since authenticated reads have their own, far larger allowance. It would
# need criterion 9.9 amended, which says "through anonymous reads", the
# record to say which reads were authenticated, and `GH_TOKEN` handed to the
# posture step of `.github/workflows/rescan.yml`. The compared fields are the
# same either way, since `bypass_actors` is withheld from this token as well.
#
# The comparison canonicalises by ruleset name over name, target,
# enforcement, conditions and rules. Server-assigned fields (id, source,
# source_type, node_id, _links, created_at, updated_at,
# current_user_can_bypass) are dropped, keys are sorted, and lists are
# sorted by their canonical form, so rule order and check order never read
# as drift. Each difference is one line naming the path and both values.
# Both directions run: a committed ruleset without a live counterpart and an
# active live branch ruleset without a committed counterpart are failures,
# so a retired ruleset that returns is caught (review 3.9).
#
# Exit 1 on any failure; the record at <out.json> is what the workflow reads.
# Seams for the tests: DHC_GITHUB_API (default https://api.github.com), and
# the waiting is the external command `sleep`.
set -uo pipefail
DIR="${1:?usage: check-governance.sh <rulesets-dir> <owner/repo> <out.json>}"
REPO="${2:?usage: check-governance.sh <rulesets-dir> <owner/repo> <out.json>}"
OUT="${3:?usage: check-governance.sh <rulesets-dir> <owner/repo> <out.json>}"
API="${DHC_GITHUB_API:-https://api.github.com}"
MAX_WAIT="${DHC_GOVERNANCE_MAX_WAIT:-3900}"

python3 - "$DIR" "$REPO" "$OUT" "$API" "$MAX_WAIT" <<'PY'
import glob, json, os, subprocess, sys, time, urllib.error, urllib.request

rulesets_dir, repo, out_path, api = sys.argv[1:5]
max_wait = int(sys.argv[5])
COMPARED = ("name", "target", "enforcement", "conditions", "rules")
failures = []

def error(msg):
    failures.append(msg)
    print(f"::error::{msg}")

def get(path):
    req = urllib.request.Request(f"{api}/{path}", headers={
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "dhc-pipeline check-governance (anonymous)",
    })
    for waited in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            h = e.headers
            if e.code not in (403, 429) or not (h.get("x-ratelimit-remaining") == "0" or h.get("retry-after")):
                raise
            try:
                if h.get("retry-after"):
                    seconds = int(h["retry-after"]) + 5
                else:
                    seconds = max(0, int(h["x-ratelimit-reset"]) - int(time.time())) + 5
            except (TypeError, ValueError):
                raise RuntimeError("GitHub's anonymous rate limit is spent and the answer names no reset") from None
            if seconds > max_wait:
                raise RuntimeError(f"GitHub's anonymous rate limit is spent, its reset {seconds} seconds away, "
                                   f"beyond the bound of {max_wait} seconds") from None
            if waited == 2:
                raise RuntimeError("GitHub's anonymous rate limit is still spent after two waits") from None
            print(f"::warning::governance: {path}: GitHub's anonymous rate limit is spent, "
                  f"waiting {seconds} seconds for its reset (Req 9.9)", flush=True)
            record["rate_limit_waits"].append({"path": path, "seconds": seconds})
            subprocess.run(["sleep", str(seconds)], check=True)

def canon(v):
    if isinstance(v, dict):
        return {k: canon(v[k]) for k in sorted(v)}
    if isinstance(v, list):
        return sorted((canon(x) for x in v), key=lambda x: json.dumps(x, sort_keys=True))
    return v

def flatten(doc):
    """path -> value over the compared fields; rules keyed by type, lists left whole."""
    flat = {}
    def walk(prefix, v):
        if isinstance(v, dict):
            for k, x in v.items():
                walk(f"{prefix}.{k}", x)
        else:
            flat[prefix] = v
    for key in COMPARED:
        if key == "rules":
            for rule in doc.get("rules") or []:
                t = rule.get("type", "?")
                params = rule.get("parameters")
                if params:
                    walk(f"rules.{t}", params)
                else:
                    flat[f"rules.{t}"] = "present"
        else:
            walk(key, doc.get(key))
    return flat

def fmt(v):
    if v is None:
        return "absent"
    if isinstance(v, list) and v and all(isinstance(x, dict) and "context" in x for x in v):
        return ", ".join(x["context"] for x in v)
    if isinstance(v, (dict, list)):
        return json.dumps(v, sort_keys=True, separators=(",", ":"))
    return str(v)

record = {"reporting": {"enabled": None, "ok": False}, "rulesets": [], "live_only": [], "rate_limit_waits": []}

# Req 9.3: the reporting channel SECURITY.md names is switched on.
try:
    enabled = bool(get(f"repos/{repo}/private-vulnerability-reporting").get("enabled"))
    record["reporting"] = {"enabled": enabled, "ok": enabled}
    if not enabled:
        error("private vulnerability reporting is disabled (Req 9.3): the channel SECURITY.md names is off")
    reporting_word = "enabled" if enabled else "DISABLED"
except Exception as e:  # noqa: BLE001
    error(f"private vulnerability reporting: unreadable ({e})")
    reporting_word = "unreadable"

# Req 9.9: committed against live, by name, both directions.
committed = {}
for path in sorted(glob.glob(os.path.join(rulesets_dir, "*.json"))):
    with open(path) as f:
        doc = json.load(f)
    committed[doc["name"]] = doc

live = None
try:
    live = get(f"repos/{repo}/rulesets")
    if not isinstance(live, list):
        raise ValueError("the list is not a JSON array")
except Exception as e:  # noqa: BLE001
    error(f"rulesets: unreadable ({e})")

differences = 0
if live is not None:
    by_name = {}
    for r in live:
        by_name.setdefault(r.get("name"), []).append(r)
    for name, doc in committed.items():
        entry = {"name": name, "ok": True, "live_id": None, "differences": []}
        record["rulesets"].append(entry)
        matches = by_name.get(name, [])
        if not matches:
            entry["ok"] = False
            error(f"committed ruleset {name}: no active live counterpart")
            continue
        if len(matches) > 1:
            entry["ok"] = False
            error(f"committed ruleset {name}: {len(matches)} live rulesets carry this name")
            continue
        entry["live_id"] = matches[0].get("id")
        try:
            detail = get(f"repos/{repo}/rulesets/{entry['live_id']}")
        except Exception as e:  # noqa: BLE001
            entry["ok"] = False
            error(f"ruleset {name} (id {entry['live_id']}): unreadable ({e})")
            continue
        want = flatten(canon({k: doc.get(k) for k in COMPARED}))
        have = flatten(canon({k: detail.get(k) for k in COMPARED}))
        for key in sorted(set(want) | set(have)):
            if want.get(key) != have.get(key):
                entry["ok"] = False
                entry["differences"].append({"path": key, "committed": want.get(key), "live": have.get(key)})
                differences += 1
                error(f"ruleset {name}: {key}: committed {fmt(want.get(key))}, live {fmt(have.get(key))}")
    for r in live:
        if r.get("name") in committed:
            continue
        if r.get("target") == "branch" and r.get("enforcement") == "active":
            record["live_only"].append({"name": r.get("name"), "id": r.get("id")})
            error(f"live ruleset {r.get('name')} (id {r.get('id')}): no committed counterpart")

with open(out_path, "w") as f:
    json.dump(record, f, indent=1)
    f.write("\n")

print(f"governance: private vulnerability reporting {reporting_word}, "
      f"{len(committed)} committed ruleset(s) compared, {differences} difference(s), "
      f"{len(record['live_only'])} live-only ruleset(s)")
sys.exit(1 if failures else 0)
PY
