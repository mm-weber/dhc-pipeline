# Requirement 6, criteria numbered 1 to 30 only

Read at commit b8f18441f873115a7c43f720a2b27989e3bc7e84, from the files on disk. Live criteria in range: 6.1, 6.3, 6.4, 6.5, 6.7 to 6.17, 6.19, 6.20, 6.22, 6.25 to 6.30 (retired and skipped: 6.2, 6.6, 6.18, 6.21, 6.23, 6.24). Negative paths were probed on copies under /tmp (`/tmp/r6a-probe`, `/tmp/r6a-arr`, `/tmp/r6a-ti`), never on the tree.

## Criteria

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 6.1 | HELD | `build.yml:503-562` (compile, then `scan-image.sh`), `scan-image.sh:67-76` (`--severity` from the declared aperture, `--exit-code 0`), `build.yml:569-571` (count), `build.yml:896-916` (fails naming each finding) | Both SHALLs hold: Trivy scans, every reported finding (the report holds the aperture only) fails the leg. Note: the "Trivy is the declared authoritative consumer" refusal (`triage-policy.sh:142-143`) runs on a pull request only inside the `continue-on-error` portability step (`build.yml:737-747`); validate never asks, the rescan smoke test does (`consumer-smoke.sh:55`). A PR changing only the gate's scripts or the policy builds nothing (`build.yml:103-151`), so the gate is not exercised on its own change; outside this criterion's WHEN |
| 6.3 | PARTIAL | `rescan.yml:142-218` (scan, supported set into `$OUT/trivy`), `:597-616` (enrich), `:618-635` (dedup), `:637-651` (reporter), `:667-689` (file); `report.go:248-301` (severity, EPSS, KEV, affected images) | EPSS outage is swallowed and the issue is filed with "n/a"; a KEV file that downloads but does not parse files every issue as "KEV: no"; a failed supported-manifest scan files nothing and leaves the run green; the reporter has no VEX-unresolved fence. r6a.1 |
| 6.4 | HELD | `triage/vex/*.openvex.json`; attached on release `build.yml:1060-1076,1113,1125`; re-attested by the rescan `rescan.yml:293` with `reattest.sh` | Shape held by `lint-vex-product.sh`; the "WHEN a decision concludes" half is the maintainer's |
| 6.5 | PARTIAL | the bump lanes (Renovate, `renovate.json5`); the gate's error text names it (`build.yml:914`) | Process criterion: nothing links a recorded fix decision to a pull request. r6a.2 |
| 6.7 | HELD | `lint-accepted-risk.sh:58-69,124-136` (treatment, owner, ref, blocked, decided_at, expired_at, paths), `:152-154` (transfer names an issue), `:221-225` with `lint-log-anchors.sh:79-101` (ref resolves to a LOG heading); `validate.yml:79-80` | |
| 6.8 | HELD | `compile-vex.sh:431-438` (an exception compiles only to `affected`), `lint-vex-product.sh:130-133` (source lane admits only not_affected/fixed) | Structural: two lanes, two formats. A human could still write an acceptance as not_affected in triage/vex/; that is review |
| 6.9 | HELD | Trivy's `expired_at` on `--ignorefile` (`scan-image.sh:53-54`), counted at `build.yml:570-571,904`; `lint-accepted-risk.sh:180-183` also reddens validate | Trivy drops the entry from midnight UTC of the expiry day, a day earlier than the lint and compiler (LOG.md:3473-3489, live-evidence.md:150); conservative for this criterion. Third-party behaviour, no repository test |
| 6.10 | PARTIAL | `rescan.yml:570-595` reusing `lint-accepted-risk.sh:180-186`; window from `triage-policy.sh . expiry-warning` | The step cannot fail: a lint that cannot run prints "_none_ ✓" and exits 0 (probed). r6a.3 |
| 6.11 | HELD | `lint-accepted-risk.sh:124-136` (each field, paths), `:171-178` (span over the largest ceiling from `decided_at`), ceiling from `triage-policy.sh:76-77`; `validate.yml:79-80` | |
| 6.12 | PARTIAL | `lint-accepted-risk.sh:36-42` | Detection is by the name `.trivyignore*` only, and any directory named `temp` or `node_modules` is pruned at any depth (probed). r6a.4 |
| 6.13 | PARTIAL | `build.yml:772-857`, `govulncheck-report.sh:51-81` | `continue-on-error: true`: a tool that did not run leaves the PR green; files under 1 MiB are never candidates; `docker export ... \|\| true` hides a partial filesystem. r6a.5 |
| 6.14 | NOT HELD | rendered only: `govulncheck-report.sh:16-18`, `build.yml:849-850` | No code compares a govulncheck result with `triage/vex/`; the govulncheck JSON is not uploaded (`build.yml:919-927` uploads trivy.json and grype.txt). Design Decision 7 (`design.md:447-451`) assigns it to the maintainer at review. r6a.6 |
| 6.15 | PARTIAL | `lint-log-anchors.sh:103-127` (every statement cites a LOG heading that exists) | The lint checks that a citation resolves, not that the cited entry holds a symbol/package-level govulncheck result or an entrypoint argument; six statements carry `vulnerable_code_not_in_execute_path`. r6a.7 |
| 6.16 | PARTIAL | `govulncheck-report.sh:53,60-62,73-74` (module level renders "not measured", most-resolved finding wins) | The "treat as unmeasured" half is rendered; "SHALL NOT cite it" is unchecked. r6a.8 |
| 6.17 | HELD | `lint-vex-product.sh:92-122` (purl, type oci), `:153-157` (a definition publishes that name), `:182-207` (repository_url equals the published repository); `validate.yml:192-193` | |
| 6.19 | HELD | `lint-vex-product.sh:210-221` | |
| 6.20 | HELD | `lint-vex-product.sh:170-178` (version is a declared tag of a definition publishing the name), `:137-139` (fixed needs a version), `:146-148` (versionless needs `version-independent:` in status_notes) | |
| 6.22 | NOT HELD | none; convention only (`triage/README.md:352-357`) | No lint, test or compiler rule checks that an earlier statement was retained or that the superseding one is later. r6a.9 |
| 6.25 | HELD | `lint-accepted-risk.sh:111-146` (per file, (id, path) seen twice fails) | |
| 6.26 | PARTIAL | `accepted-risk-report.sh:76-91`, called at `build.yml:624` | An entry counts as live when any suppression carries its id and its statement text; two entries with one id and one statement mask a dead one (probed). r6a.10 |
| 6.27 | HELD | `accepted-risk-report.sh:52-74` (Target per suppression), `build.yml:616-624` | PR gate only, which is the criterion's subject |
| 6.28 | HELD | `build.yml:555,562` (`.vexscan`), `:987-992` (`.vexrelease`); `rescan.yml:191-200`; `scan-image.sh:46-51` reads only the directory it is given | `triage/vex/` is never handed to a scanner |
| 6.29 | HELD | `compile-vex.sh:104,264-267,387,433`; manifests supplied `build.yml:987,1073`, `rescan.yml:191`; PR digest `build.yml:498-500` | |
| 6.30 | HELD | `compile-vex.sh:249-258` | Dropped per product: a statement with one in-scope and one out-of-scope product keeps the in-scope one. Tested (`validate.yml:211-212`) |

## Findings

**r6a.1 (6.3, medium): a filed issue can carry no EPSS score, or a wrong KEV status, and a new finding can go unfiled on a green run.**
The sentence: an issue containing severity, EPSS score, KEV status and affected images, for every new finding in a supported digest. The code:
1. EPSS: `rescan.yml:612-613` replaces a failed fetch with `{"data":[]}`; `report.go:251-254` then writes "n/a". The step stays green, and dedup (`rescan.yml:630-634`) means the issue is never re-enriched. GHSA findings always get "n/a" (only `^CVE-` ids are sent, `rescan.yml:216-217,602`).
2. KEV: the enrich step checks only that the file is non-empty (`rescan.yml:607`); `cmd/rescan-report/main.go:62-67` turns an unparseable file into an empty set with a warning, so every issue says "CISA KEV: no". The run is red (`check-exceptions.sh:57-61` refuses at `rescan.yml:423`), but the issue bodies stay wrong.
3. A supported manifest whose scan fails is skipped with a warning (`rescan.yml:200-205`). Nothing fails the run on `failed > 0`: only the summary reads it (`rescan.yml:954`). Its new findings get no issue that day.
4. A failed compile is ignored (`rescan.yml:192` `|| true`) and the scan goes on without VEX. The status and lifecycle tools are fenced by `--vex-reports`, but the reporter is not (`rescan.yml:645-648`), so findings a not_affected statement covers can be filed as new issues.
Affected: the owner's triage queue and anyone reading the issue. Severity medium: the content is wrong for good, and only case 2 turns the run red.

**r6a.2 (6.5, low): a "fix" decision is not linked to a pull request by anything.** Process criterion; the lanes exist (Renovate, `renovate.json5`; the gate's text `build.yml:914`). Affected: the owner's audit trail.

**r6a.3 (6.10, medium): the daily expiry report cannot fail, and a lint that does not run reports "none".** `rescan.yml:580` runs `lint-accepted-risk.sh ... || true` and greps for `expires in|is in the past` (`:581`). Probe: with `triage.expiry_warning` removed from a copy of the policy, the lint stops at `lint-accepted-risk.sh:31` and the step's logic printed "_none_ ✓" with exit 0. The same happens on a PyYAML install failure (`rescan.yml:579`, no `-e`). Two more silent skips, both blocked by validate on a pull request: entries in a file with no matching `image/<name>/image.yaml` (`lint-accepted-risk.sh:201-205`), and an entry with an unparseable `decided_at`, skipped before the expiry test (`:167-170`). Affected: the owner's view, and the page reads the same `accepted-risk.txt` (`rescan.yml:855`). Severity medium.

**r6a.4 (6.12, low): only files named `.trivyignore*` count as Trivy ignore files.** `lint-accepted-risk.sh:40-42` matches by name and prunes every `temp` and `node_modules` directory at any depth. Probe: `image/grafana/temp/.trivyignore` and a Trivy-YAML-shaped `docs/suppress.yaml` passed; `image/.trivyignore` was caught. `temp/` is gitignored (`.gitignore`), so committing there needs `git add -f`. Today no workflow passes another file as `--ignorefile`, and no `trivy.yaml` exists to name one. Severity low.

**r6a.5 (6.13, medium): govulncheck can fail to run and the pull request stays green, and some Go binaries are never looked at.** `build.yml:775` `continue-on-error: true`: the step goes red by name (`:792-796,854-856`), but the leg and the build gate pass. Candidates are files over 1 MiB only (`:824`). `docker export ... || true` (`:804-805`) lets a partial filesystem through without a word. The criterion asks for every Go binary and a per-finding report, not a gate, so the gap is that "did not run" exits 0. Affected: a reviewer relying on the evidence for 6.14 and 6.15. Severity medium.

**r6a.6 (6.14, medium): no mechanism stops a not_affected / vulnerable_code_not_in_execute_path statement on a binary whose symbol govulncheck reported reachable.** The prohibition is printed (`build.yml:849-850`, `govulncheck-report.sh:16-18`). The govulncheck JSON is not kept as an artifact (`build.yml:919-927`), and nothing reads it against `triage/vex/`. Design Decision 7 (`design.md:447-451`) assigns the criterion to the maintainer at review. Affected: a consumer, whose scanner would suppress a reachable finding. Severity medium (it takes a reviewer's error, but nothing else catches it).

**r6a.7 (6.15, low): the citation is checked for existence, not for its evidence.** `lint-log-anchors.sh:103-118` requires some `LOG.md#slug` or `LOG.md <date>` in a statement's text fields and checks that it resolves. It does not read the cited entry for a govulncheck result at symbol or package level, or for an entrypoint argument. Six statements carry the justification (`triage/vex/CVE-2026-100349,100351,100352,100353,42151,84445`). Severity low.

**r6a.8 (6.16, low): "never cite a module-level result" is unenforced.** The rendering is right (`govulncheck-report.sh:53,73-74`); the citation half rests on review. Severity low.

**r6a.9 (6.22, medium): supersession has no mechanism.** A grep of `scripts/` and `.github/workflows/` for "supersed" finds only superseded *digests*. Nothing fails when a statement is deleted or edited in place, and `compile-vex.sh:235-275` merges every surviving statement with no order check. Affected: a consumer reading the attested history, and Trivy's choice between conflicting statements. The documents claim the rule is lint-enforced (r6a.13). Severity medium.

**r6a.10 (6.26, low): a dead exception is not reported when a live sibling has the same id and statement text.** `accepted-risk-report.sh:79-86` keys "applied" on (id, statement). Probe (`/tmp/r6a-arr`): two CVE-1 entries, paths `usr/bin/a` and `usr/bin/b`, one statement, only `a` suppressed: nothing reported. With distinct statements the dead `b` entry was named. Every statement in today's `grafana.yaml` is unique per (id, statement), so this is latent. Severity low.

**r6a.11 (document, low): "starts empty".** `triage/README.md:15-16` says `vex/` "starts empty"; `triage/accepted-risk/README.md:7-8` says "Starts empty, and that is the correct default". The tree holds 12 documents under `triage/vex/` and 16 entries in `triage/accepted-risk/grafana.yaml`. Confirms the known input.

**r6a.12 (document, low): the gate is said to consume `triage/vex/`.** `triage/README.md:119-121` ("consuming `triage/vex/` via `--vex`") and `:172` ("honouring `triage/vex/`"). The scan gets only the compiled copy (`build.yml:555,562`; `scan-image.sh:50`), as the same README says at `:298`.

**r6a.13 (document, medium): the supersession rule is listed as lint-enforced.** `triage/README.md:361` ("The product-identifier rules, all lint-enforced") includes the 6.22 row at `:370`, and `docs/user-manual.md:1004` repeats "(all lint-enforced)". No lint holds it (r6a.9; `lint-vex-product.sh:1-11` lists 6.17, 6.19, 6.20, 6.39 only).

**r6a.14 (document, low): "Scan and feed failures soft-fail".** `triage/README.md:214-216`. A KEV outage fails the run (`rescan.yml:422-428`) and withholds the issue set (`:607`), as the README itself says at `:69-70`. Only scan and EPSS failures soft-fail. Confirms the known input.

**r6a.15 (document, low): "one issue per CVE".** `triage/README.md:195-197` and `docs/user-manual.md:799`. The reporter aggregates by the scanner's id (`report.go:131`), and the dedup marker carries GHSA ids too (`rescan.yml:625-629`). `docs/lanes.md:864` ("one issue per new finding") is right. Confirms the known input.

**r6a.16 (document, medium): an expiry reddens every pull request, not only the affected one.** `triage/README.md:221-223` and the comment at `rescan.yml:562-566` say the rescan raises expiry because "reddening whichever PR happens to run that day would blame the wrong change". `docs/user-manual.md:1057-1058` says "the next affected PR goes red". But validate runs `lint-accepted-risk.sh` on every pull request and every push to main (`validate.yml:79-80`), and the lint errors on any past `expired_at` (`lint-accepted-risk.sh:180-183`). Measured on 2026-10-27: `docs/live-evidence.md:150`, validate run 40500526721 red at that lint. Affected: the owner's reading of a red validate.

**r6a.17 (document, low): "one implementation of expired, the notice can never disagree with the gate".** `triage/README.md:218-220`, `docs/lanes.md:849`, `rescan.yml:568-569`. The gate's expiry is Trivy's (from midnight UTC of the expiry day); the notice's is the lint's (`lint-accepted-risk.sh:180-186`, live through that day), as is the compiler's (`compile-vex.sh:312-315`). On the expiry day the gate counts the finding while the notice says "expires in 0 days"; recorded in `triage/LOG.md:3473-3489` and `docs/live-evidence.md:176`.

**r6a.18 (document, low): "over every Go binary in the image".** `triage/README.md:154`. Candidates are files over 1 MiB (`build.yml:824`).

**r6a.19 (document, low): the manual's scan-gate list lacks the exception-tiers step.** `docs/user-manual.md:342-399` lists eight items and has no KEV/tier step. `build.yml:883-894` runs `check-exceptions.sh gate` with a fresh KEV fetch before the gate, failing closed (Req 6.50, 6.59). `docs/lanes.md:355,383` draws it. Confirms the known input.

**r6a.20 (document, medium): the error table says a Trivy outage on the rescan "soft-fails with issue".** `.specs/dhc-catalogue-mvp/design.md:1697`. A failed scan is warned and counted (`rescan.yml:200-205`), no issue is filed for it, and no step fails the run on the count (`:954` only prints it). Affected: the owner, who expects an issue. Confirms the known input.

**r6a.21 (document, medium): "no issue set is built on a KEV status nobody evaluated".** `docs/lanes.md:877`; `docs/user-manual.md:575-577` ("a KEV feed outage still withholds ... the issue set"). True for a failed download. A file that downloads but does not parse passes the `-s` test (`rescan.yml:607`), and `cmd/rescan-report/main.go:62-67` builds and files the issue set with an empty KEV set (r6a.1 case 2). Confirms the known input for its 6.3 half.

## Known input

In scope (6.1 to 6.30, the gate and rescan issue lanes, the listed documents):
- **"A KEV file that downloads but does not parse still yields an issue set (Req 6.60)": CONFIRMED** for the issue set, which is 6.3's output. `rescan.yml:422-423` keeps the file after a successful curl. `check-exceptions.sh:57-61` refuses, so the invariants step goes red. `rescan.yml:607` checks only that the file is non-empty. `main.go:62-67` degrades to an empty KEV set, and `rescan.yml:667-689` files the issues with "CISA KEV: no". 6.60 itself (the run fails) holds here, but 6.60 is outside this range. r6a.1, r6a.21.
- **"A pull request changing only the gate's scripts builds nothing": CONFIRMED.** `build.yml:103-151` adds legs only for `image/*/image.yaml`, `triage/vex/`, `triage/accepted-risk/` and `build.yml` itself. A change to `scripts/scan-image.sh`, `compile-vex.sh`, `check-exceptions.sh`, `accepted-risk-report.sh`, `triage-policy.sh` or `catalogue-policy.yaml` builds no image, so the gate never runs on its own change; only the unit suites in validate run. Not a breach of 6.1 (its WHEN is "a pull request builds an image"), but the gate is untested end to end on its own change. The test/go.mod half is e2e scope, not read here.
- **"The manual's scan gate list lacks the KEV tiers step": CONFIRMED.** r6a.19.
- **"design.md's error table files an issue on a Trivy outage (none is filed)": CONFIRMED.** r6a.20.
- **"triage/README.md says feed failures soft-fail (KEV fails the run)": CONFIRMED.** r6a.14.
- **"one issue per CVE (GHSA ids too)": CONFIRMED.** r6a.15.
- **"vex/ and accepted-risk/ start empty": CONFIRMED** (12 documents, 16 entries). r6a.11.

Outside this range, not ruled on here: renovate.json5:416 refresh task keyed on github-tags (Req 3); render-verification.sh pipefail (Req 9.13); the tag step order build.yml:1229-1238 (Req 2.7); rescan.yml:102-104 malformed switch (Req 7.7; seen in passing: `echo "page=$(...)"` does exit 0 on a refusal, as docs/lanes.md:755 records); build portability and consumers.gating (Req 9.12); main_sec.json (Req 9.8); e2e on test/go.mod (Req 5); Req 2.5 vs fail-fast; Decisions 2, 6, 10; the manual's cron table, tag line and smoke summary; SECURITY.md.

## Counts

HELD 14 (6.1, 6.4, 6.7, 6.8, 6.9, 6.11, 6.17, 6.19, 6.20, 6.25, 6.27, 6.28, 6.29, 6.30), PARTIAL 8 (6.3, 6.5, 6.10, 6.12, 6.13, 6.15, 6.16, 6.26), NOT HELD 2 (6.14, 6.22), OWNER-SIDE 0; document findings 11 (r6a.11 to r6a.21).
