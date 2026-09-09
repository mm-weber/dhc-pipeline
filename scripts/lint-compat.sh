#!/usr/bin/env bash
# lint-compat.sh [root]
#
# The compat decision and its clock (Req 4.5, 4.8; task 11.4, review D7). A
# chart that deploys a compat variant records the decision in
# chart/<name>/chart.yaml under `compat:` (reason, the upstream ask,
# decided_at, review_by). Its shape is yamale's job (chart/chart.schema.yaml);
# this lint asks the questions a static schema cannot:
# - Is the record bound to the trigger? A chart whose `deploys:` names a
#   definition declaring `variant: compat` must carry a `compat:` block
#   naming that variant, and a `compat:` block must name a compat variant
#   the chart deploys (Req 4.5). Before review D7 the schema marked the
#   block optional and nothing correlated the two, so a second compat
#   variant could have shipped undecided.
# - Has review_by passed? If it has, validate fails until a dated
#   re-decision lands, the same pattern as an accepted-risk entry's
#   expired_at (lint-accepted-risk.sh): a decision without a date it must be
#   revisited by is indistinguishable from a decision nobody is making. A
#   review_by before decided_at is a clock running backwards (Req 4.8).
# DHC_TODAY is the test seam.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
today="${DHC_TODAY:-$(date -u +%F)}"

python3 - "$ROOT" "$today" <<'PY'
import datetime, glob, os, sys, yaml

root, today = sys.argv[1], datetime.date.fromisoformat(sys.argv[2])
errors = 0
charts = 0

def as_date(v):
    if isinstance(v, datetime.datetime):
        return v.date()
    if isinstance(v, datetime.date):
        return v
    try:
        return datetime.date.fromisoformat(str(v)[:10])
    except ValueError:
        return None

for path in sorted(glob.glob(os.path.join(root, "chart", "*", "chart.yaml"))):
    rel = os.path.relpath(path, root)
    try:
        doc = yaml.safe_load(open(path, encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        print(f"::error file={rel}::compat decision (Req 4.8): not valid YAML: {exc}")
        errors += 1
        continue
    compat = doc.get("compat")
    # Req 4.5, the trigger: which of the definitions this chart deploys are
    # compat variants (image/<name>/image.yaml declares variant: compat).
    deploys = doc.get("deploys") if isinstance(doc.get("deploys"), list) else []
    variants = {}
    for name in deploys:
        image = os.path.join(root, "image", str(name), "image.yaml")
        if not os.path.isfile(image):
            print(f"::error file={rel}::compat decision (Req 4.5): deploys: names {name}, but image/{name}/image.yaml does not exist")
            errors += 1
            continue
        try:
            variants[str(name)] = str((yaml.safe_load(open(image, encoding="utf-8")) or {}).get("variant", ""))
        except yaml.YAMLError as exc:
            print(f"::error file=image/{name}/image.yaml::compat decision (Req 4.5): not valid YAML: {exc}")
            errors += 1
    compat_deployed = sorted(n for n, v in variants.items() if v == "compat")
    if compat is None:
        for name in compat_deployed:
            print(f"::error file={rel}::compat decision (Req 4.5): deploys: names the compat variant {name} but records no decision for it; add a compat: block (variant, reason, issue, decided_at, review_by)")
            errors += 1
        continue
    charts += 1
    if not isinstance(compat, dict):
        print(f"::error file={rel}::compat decision (Req 4.5): compat: must be a mapping")
        errors += 1
        continue
    named = str(compat.get("variant", ""))
    if named not in variants:
        print(f"::error file={rel}::compat decision (Req 4.5): compat.variant names {named or '(nothing)'}, which deploys: does not list")
        errors += 1
        continue
    if variants[named] != "compat":
        print(f"::error file={rel}::compat decision (Req 4.5): compat.variant names {named}, which is not a compat variant (image/{named}/image.yaml declares variant: {variants[named] or '(none)'})")
        errors += 1
        continue
    for name in compat_deployed:
        if name != named:
            print(f"::error file={rel}::compat decision (Req 4.5): deploys: names the compat variant {name} but the decision is about {named}; one block decides one variant")
            errors += 1
    review = as_date(compat.get("review_by")) if compat.get("review_by") is not None else None
    decided = as_date(compat.get("decided_at")) if compat.get("decided_at") is not None else None
    if review is None:
        print(f"::error file={rel}::compat decision (Req 4.8): review_by is missing or not a YYYY-MM-DD date, so the decision can never be revisited")
        errors += 1
        continue
    if decided is None:
        print(f"::error file={rel}::compat decision (Req 4.5): decided_at is missing or not a YYYY-MM-DD date, so the clock has no start")
        errors += 1
        continue
    if review < decided:
        print(f"::error file={rel}::compat decision (Req 4.8): review_by {review} is before decided_at {decided}, a clock running backwards")
        errors += 1
        continue
    if review < today:
        print(f"::error file={rel}::compat decision (Req 4.8): review_by {review} has passed (today {today}); record a dated re-decision (a new decided_at and review_by) or retire the variant")
        errors += 1
        continue
    print(f"lint-compat: {rel}: compat decision decided {decided}, review by {review} ({(review - today).days} day(s) ahead)")

if errors:
    print(f"lint-compat: {errors} problem(s)")
    sys.exit(1)
print(f"lint-compat: {charts} compat decision(s), every review-by date ahead, every deployed compat variant decided")
PY
