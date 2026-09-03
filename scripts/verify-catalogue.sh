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
# registry, Rekor or Fulcio unreachable). A rejection in the batch is
# re-applied alone: measured 2026-09-03 on kyverno 1.18.2, three runs, the
# first ten pods of a nineteen-pod batch were rejected with the same
# attestation shapes as the nine admitted after them. A digest the policy
# admits alone is admitted and the batch artefact is named (::warning,
# recorded); one rejected alone as well fails the proof by name: not
# verified is not admitted. A missing enumeration or an undeclared control
# refuses (exit 2) rather than passing vacuously.
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

python3 - "$WORK/raw" "$WORK/map" "$OUT" "$WORK/kyverno.err" "$POLICY" "$WORK" "$ENUM" "$ROOT/catalogue-policy.yaml" <<'PY'
import json, shutil, subprocess, sys, yaml
def verdicts(raw):
    """name -> (result, message) from a kyverno JSON report; the worst verdict
    per resource wins: error > fail > pass."""
    starts = [k for k in (raw.find("{"), raw.find("[")) if k >= 0]
    if not starts:
        return None
    doc = json.loads(raw[min(starts):])
    out = {}
    for d in (doc if isinstance(doc, list) else [doc]):
        for r in d.get("results", []):
            for res in r.get("resources", []):
                n = res.get("name")
                rank = {"error": 3, "fail": 2, "pass": 1}
                cur = out.get(n, ("none", ""))
                if rank.get(r.get("result"), 0) >= rank.get(cur[0], 0):
                    # The whole reason, not its first line: Kyverno names the
                    # attestation type, the counts and the subject it received,
                    # and the first live run (2026-09-03) cut off exactly the
                    # part that said why. Capped only where GitHub would.
                    out[n] = (r.get("result"), (r.get("message") or "")[:4000])
    return out
verdict = verdicts(open(sys.argv[1]).read())
if verdict is None:
    print("::error::verify-catalogue: kyverno produced no policy report; stderr: " + open(sys.argv[4]).read().strip()[:500], file=sys.stderr)
    sys.exit(1)
policy, work = sys.argv[5], sys.argv[6]
rows = [line.rstrip("\n").split("\t") for line in open(sys.argv[2])]
# One pod per document in the batch file, by name, so a rejected digest can be
# re-applied alone. Measured 2026-09-03 on kyverno 1.18.2 across three runs:
# exactly the first ten pods of a nineteen-pod batch were rejected, with the
# same attestation shapes on both sides of the line. Req 2.24 is a claim
# about the policy over each digest, so a digest the policy admits alone is
# admitted, and the batch artefact is named rather than silently absorbed.
pods = {}
for chunk in open(f"{work}/pods.yaml").read().split("\n---\n"):
    for line in chunk.splitlines():
        if line.strip().startswith("name: "):
            pods[line.split("name: ", 1)[1].strip()] = chunk.strip() + "\n"
            break
# The cosign second opinion (task 9.6 follow-up, 2026-09-03): Kyverno's
# rejection reasons are terse, cosign's are not. For a digest the policy
# rejects alone, ask cosign the same questions the policy asks, one per role
# and type, on the index and on every platform manifest the enumeration lists,
# and keep every answer. Identities come from the policy file, as the rendered
# policy's did; a policy file without roles, or a runner without cosign, is
# recorded as "not asked", never as a pass.
enum_path, policy_yaml = sys.argv[7], sys.argv[8]
pol = (yaml.safe_load(open(policy_yaml)) or {}).get("verification") or {}
roles = pol.get("roles") or {}
required = pol.get("required") or {}
issuer = pol.get("issuer") or ""
manifests_of = {}
for line in open(enum_path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) >= 5 and parts[0]:
        key = f"{parts[0]}@{parts[2]}"
        m = f"{parts[0]}@{parts[4]}"
        if parts[4] and m != key and m not in manifests_of.setdefault(key, []):
            manifests_of[key].append(m)
def cosign_says(args):
    r = subprocess.run(["cosign"] + args, capture_output=True, text=True)
    if r.returncode == 0:
        return "ok"
    first = next((l for l in (r.stderr or r.stdout).splitlines() if l.strip()), "failed")
    return first.strip().removeprefix("Error: ")[:300]
def second_opinion(ref):
    if not (shutil.which("cosign") and issuer and roles and required.get("signature")):
        return {"not asked": "cosign or the policy file's verification roles are not available"}
    answers = {}
    for target in [ref] + manifests_of.get(ref, []):
        sig_id = roles.get(required["signature"], {}).get("identity", "")
        a = {"signature": cosign_says(["verify", "--certificate-oidc-issuer", issuer, "--certificate-identity", sig_id, target])}
        for alias, who in (required.get("attestations") or {}).items():
            for role in who:
                a[f"{alias} by {role}"] = cosign_says(["verify-attestation", "--type", alias, "--certificate-oidc-issuer", issuer,
                                                       "--certificate-identity", roles.get(role, {}).get("identity", ""), target])
        answers[target] = a
    return answers
def describe(ref, answers):
    parts = []
    for target, a in answers.items():
        label = "index" if target == ref else f"manifest {target.split('@', 1)[1]}"
        for k, v in a.items():
            parts.append(f"{label} {k}: {v}")
    return "; ".join(parts)
def alone(name):
    path = f"{work}/alone-{name}.yaml"
    open(path, "w").write(pods[name])
    r = subprocess.run(["kyverno", "apply", policy, "--resource", path, "--registry", "-p", "--output-format", "json"],
                       capture_output=True, text=True)
    v = verdicts(r.stdout) or {}
    return v.get(name, ("missing", "no result for this resource in the report"))
failures, warnings, notices = [], [], []
admitted = flakes = 0
record = {}
for name, ref, tags in rows:
    result, msg = verdict.get(name, ("missing", "no result for this resource in the report"))
    entry = {"name": name, "ref": ref, "tags": tags, "result": result, "message": msg}
    if name.startswith("control"):
        if result == "fail":
            print(f"verify-catalogue: control rejected as required: {ref}")
        elif result == "pass":
            failures.append(f"the CONTROL was ADMITTED: {ref}; the policy admits an unsigned digest and proves nothing (Req 2.24)")
        else:
            failures.append(f"control {ref}: {result} ({msg}); not a rejection")
    elif result == "pass":
        admitted += 1
    else:
        a_result, a_msg = alone(name)
        entry["alone"] = {"result": a_result, "message": a_msg}
        if a_result == "pass":
            admitted += 1; flakes += 1
            entry["batch_flake"] = True
            warnings.append(f"admitted alone, rejected in the batch of {len(rows) - 1}: {ref} (tags: {tags}); the batch said: {msg}")
        else:
            entry["cosign"] = second_opinion(ref)
            notices.append(f"cosign on {ref}: {describe(ref, entry['cosign'])}")
            if result == "fail" and a_result == "fail":
                # kyverno reports an unverifiable image (no roots, no registry)
                # as "fail" too, so the label claims only what is known: the
                # digest was NOT ADMITTED, and the message says why.
                failures.append(f"NOT ADMITTED (alone as well): tag-referenced digest {ref} (tags: {tags}): {a_msg}")
            else:
                failures.append(f"{a_result.upper()} on {ref} (tags: {tags}), alone as well: {a_msg}; not verified is not admitted")
    record[name] = entry
json.dump({"control": rows[-1][1], "resources": [record[n] for n, _, _ in rows],
           "batch_flakes": flakes, "failures": failures, "warnings": warnings}, open(sys.argv[3], "w"), indent=2)
for n in notices:
    print(f"::notice::verify-catalogue: {n}", file=sys.stderr)
for w in warnings:
    print(f"::warning::verify-catalogue: {w}", file=sys.stderr)
for f in failures:
    print(f"::error::verify-catalogue: {f}", file=sys.stderr)
if failures:
    print(f"::error::verify-catalogue: {len(failures)} admission-proof failure(s) over {len(rows) - 1} tag-referenced digest(s) (Req 2.24)", file=sys.stderr)
    sys.exit(1)
note = f" ({flakes} admitted alone after a batch rejection)" if flakes else ""
print(f"verify-catalogue: {admitted} admitted{note}, control rejected; the admission policy holds over every tag-referenced digest (Req 2.24)")
PY
