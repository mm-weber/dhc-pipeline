<!-- One logical change per PR (docs/CONVENTIONS.md). Definition bumps and
     chart changes do not mix unless the bump forces the chart change. -->

## TL;DR

<!-- Three to five lines a reader can merge from: what this PR ships, as of
     its head commit. Updated whenever a review comes in: each finding's
     disposition (fixed in <commit>, accepted, re-decided by the owner), or
     "Reviews: none yet". The body answers the threads, not the other way
     round (docs/CONVENTIONS.md, rule of 2026-10-16). -->

## What

<!-- Which kind of change: definition bump / new definition / chart adaptation /
     policy / triage decision / infra. One sentence on what and why. -->

## Requirement references

<!-- Req IDs from .specs/dhc-catalogue-mvp/requirements.md this PR serves,
     e.g. "Req 3.2, Req 4.7". CVE fix-forwards: link the triage issue. -->

## Convention compliance (docs/CONVENTIONS.md)

- [ ] Every image/base reference digest-pinned; sources pinned by ref + checksum
- [ ] Chart deltas live only in `config/values-hardened.yaml`; upstream untouched
- [ ] Deviations documented in the chart README (what → why → link)
- [ ] Runtime workloads non-root (65532)
- [ ] Test evidence included for behavior claims

## Notes for review

<!-- Compat-variant decisions, upgrade risks, anything to scrutinize. -->
