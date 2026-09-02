#!/usr/bin/env bash
# verify-catalogue.sh <root> <enumeration.tsv> <report-out.json>
#
# The daily admission proof (task 9.6, Req 2.24): the rendered policy
# (policies/verify-catalogue-images.yaml, from catalogue-policy.yaml's
# verification section) applied by the kyverno CLI against the live
# registry must ADMIT every digest a catalogue tag references, and must
# REJECT the declared unsigned control. Anything else fails the run by name.
#
# Why both halves: a policy that admits everything looks exactly like one
# that works until something it should reject gets through, so the control
# (catalogue-policy.yaml verification.control, a digest under a catalogue
# repository that carries no signature) is applied on every run. Why the
# tag-referenced INDEX digest: that is what a consumer's tag resolves to and
# where the release arm puts signature, SPDX and OpenVEX (spec amended
# 2026-09-02); a consumer pinning a platform digest gets the recursive
# signature and per-manifest attestations, verified by the same policy the
# same way, which the control also exercises from the other side.
#
# Why here rather than `kyverno test` fixtures: the set of digests it must
# admit changes daily. The CLI reaches the registry with --registry and
# uses the job's docker login, which is the point: admission is what a
# pulling consumer experiences. Its report comes back as JSON
# (`-p --output-format json`: a ClusterReport with one result per resource;
# measured on kyverno 1.18.2, which prints a text preamble first).
#
# Verdicts per resource: pass, fail, or error (the tool could not verify:
# registry, Rekor or Fulcio unreachable). An error on any resource fails the
# proof by name: not verified is not admitted. A missing enumeration or an
# undeclared control refuses (exit 2) rather than passing vacuously.
set -euo pipefail

err() { printf '::error::verify-catalogue: %s\n' "$1" >&2; }

if [ "$#" -ne 3 ]; then
  err "usage: verify-catalogue.sh <root> <enumeration.tsv> <report-out.json>"
  exit 2
fi
ROOT="$1"; ENUM="$2"; OUT="$3"
POLICY="$ROOT/policies/verify-catalogue-images.yaml"

[ -f "$ENUM" ] || { err "enumeration ${ENUM} does not exist; refusing a vacuous pass (Req 2.24 binds to the enumeration)"; exit 2; }
[ -f "$POLICY" ] || { err "rendered policy ${POLICY} does not exist"; exit 2; }

CONTROL=$(python3 - "$ROOT/catalogue-policy.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
print((doc.get("verification") or {}).get("control") or "")
PY
)
if [ -z "$CONTROL" ]; then
  err "catalogue-policy.yaml declares no verification.control; without a must-reject control the proof cannot tell a working policy from an empty one"
  exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# One Pod per unique tag-referenced digest (platform rows and tags sharing a
# digest collapse), plus the control. A DNS-1123 name per Pod; the mapping
# back to repository, digest and tags is what failures are named with.
# The if-form, not a ternary on the assignment: mawk creates the assigned
# element before evaluating the right-hand side, so `key in tags` reads true
# on first sight and every tag list started with a stray comma (measured
# 2026-09-02 in the live rehearsal).
cut -f1,2,3 "$ENUM" | LC_ALL=C sort -u \
  | awk -F'\t' '{ key=$1"@"$3; if (key in tags) tags[key]=tags[key]","$2; else tags[key]=$2 } END { for (k in tags) print k"\t"tags[k] }' \
  | LC_ALL=C sort > "$WORK/digests"
[ -s "$WORK/digests" ] || { err "the enumeration lists no tag-referenced digest; nothing to prove"; exit 2; }

: > "$WORK/pods.yaml"; : > "$WORK/map"
i=0
while IFS=$'\t' read -r ref tags; do
  i=$((i + 1)); name=$(printf 'admit-%03d' "$i")
  printf '%s\t%s\t%s\n' "$name" "$ref" "$tags" >> "$WORK/map"
  cat >> "$WORK/pods.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
spec:
  containers:
    - name: c
      image: ${ref}
---
EOF
done < "$WORK/digests"
printf '%s\t%s\t%s\n' "control-must-reject" "$CONTROL" "(declared control)" >> "$WORK/map"
cat >> "$WORK/pods.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: control-must-reject
spec:
  containers:
    - name: c
      image: ${CONTROL}
EOF

# kyverno exits non-zero whenever anything fails, and the control MUST fail,
# so its exit status is not a signal here; the report is.
kyverno apply "$POLICY" --resource "$WORK/pods.yaml" --registry -p --output-format json \
  > "$WORK/raw" 2>"$WORK/kyverno.err" || true

python3 - "$WORK/raw" "$WORK/map" "$OUT" "$WORK/kyverno.err" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
starts = [k for k in (raw.find("{"), raw.find("[")) if k >= 0]
if not starts:
    print("::error::verify-catalogue: kyverno produced no policy report; stderr: " + open(sys.argv[4]).read().strip()[:500], file=sys.stderr)
    sys.exit(1)
doc = json.loads(raw[min(starts):])
docs = doc if isinstance(doc, list) else [doc]
verdict = {}
for d in docs:
    for r in d.get("results", []):
        for res in r.get("resources", []):
            n = res.get("name")
            # the worst verdict per resource wins: error > fail > pass
            rank = {"error": 3, "fail": 2, "pass": 1}
            cur = verdict.get(n, ("none", ""))
            if rank.get(r.get("result"), 0) >= rank.get(cur[0], 0):
                verdict[n] = (r.get("result"), (r.get("message") or "")[:200])
rows = [line.rstrip("\n").split("\t") for line in open(sys.argv[2])]
failures = []
admitted = 0
for name, ref, tags in rows:
    result, msg = verdict.get(name, ("missing", "no result for this resource in the report"))
    if name.startswith("control"):
        if result == "fail":
            print(f"verify-catalogue: control rejected as required: {ref}")
        elif result == "pass":
            failures.append(f"the CONTROL was ADMITTED: {ref}; the policy admits an unsigned digest and proves nothing (Req 2.24)")
        else:
            failures.append(f"control {ref}: {result} ({msg}); not a rejection")
    else:
        if result == "pass":
            admitted += 1
        elif result == "fail":
            # kyverno reports an unverifiable image (no roots, no registry)
            # as "fail" too, so the label claims only what is known: the
            # digest was NOT ADMITTED, and the message says why.
            failures.append(f"NOT ADMITTED: tag-referenced digest {ref} (tags: {tags}): {msg}")
        else:
            failures.append(f"{result.upper()} on {ref} (tags: {tags}): {msg}; not verified is not admitted")
json.dump({"control": rows[-1][1], "resources": [{"name": n, "ref": ref, "tags": tags, "result": verdict.get(n, ("missing", ""))[0]} for n, ref, tags in rows],
           "failures": failures}, open(sys.argv[3], "w"), indent=2)
for f in failures:
    print(f"::error::verify-catalogue: {f}", file=sys.stderr)
if failures:
    print(f"::error::verify-catalogue: {len(failures)} admission-proof failure(s) over {len(rows) - 1} tag-referenced digest(s) (Req 2.24)", file=sys.stderr)
    sys.exit(1)
print(f"verify-catalogue: {admitted} admitted, control rejected; the admission policy holds over every tag-referenced digest (Req 2.24)")
PY
