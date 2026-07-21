<!-- One logical change per PR (docs/CONVENTIONS.md). Definition bumps and
     chart changes do not mix unless the bump forces the chart change. -->

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
