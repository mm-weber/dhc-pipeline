# Requirement 6, criteria numbered 31 and above only

Read at commit b8f18441f873115a7c43f720a2b27989e3bc7e84 (`/workspace/repos/dhc-pipeline/req-reading`), 2026-11-22. Method: the review of 2026-09-09: the code is the evidence; comments, docs and ledgers are claims. Retired numbers in this range skipped: 6.31, 6.36, 6.48. Live criteria read: 29.

Probes were run on copies under /tmp/r6b-probe (never the tree): check-exceptions.sh with a KEV file of {} and of <html>; rescan-report with an unparseable KEV file; compile-vex.sh with a malformed source and with a CVE covered for one package and excepted or reported for another; bash's handling of echo "x=$(failing command)" under set -euo pipefail.

## Criteria

| # | Verdict | Mechanism (file:line) | Gap or note |
|---|---|---|---|
| 6.32 | HELD | scripts/compile-vex.sh:218-229 (every drop recorded with kind, cve, product, reason), :474-483 (report: digest, digests, tags, drops) when COMPILE_VEX_REPORT is set; every caller sets it (rescan.yml:191, reattest.sh:202, build.yml:1075) | A compile that fails writes no report (compile-vex.sh:474 is reached only on success), which breaks a rescan claim (r6b.12), not this criterion: nothing was compiled. |
| 6.33 | HELD | rescan.yml:971-1003 (per-image counts; tag-scoped drops listed by statement), rescan.yml:1023-1029 uploads rescan-out/, which holds every vex/*.report.json with all drops | The summary lists by name only kind "tag" drops. "malformed" drops are counted under "belonging to other images" (rescan.yml:999-1000), which is a wording slip. |
| 6.34 | HELD | Release: build.yml:1060-1076 compiles for DIGEST and every manifest, then build.yml:1099,1113,1125 attests that file. Rescan: reattest.sh:201-205,233-236 | |
| 6.35 | HELD | The gate counts only .Vulnerabilities (build.yml:570-571), and Trivy suppresses only not_affected and fixed. Source statements can be only not_affected or fixed (lint-vex-product.sh:130-132), and the gate's compile gets no scan reports, so it emits no affected or under_investigation (build.yml:555). | |
| 6.37 | PARTIAL | reattest.sh:201-205 gives the compile the source, the exceptions (default path), today's reports (attested in step 1), the verified previous document and the issue map | When the issue-map read fails, an empty map {} is used in its place (rescan.yml:280-282), and the compile runs as if no issue were open (r6b.5). |
| 6.38 | PARTIAL | compile-vex.sh:398-446 (affected per suppressed finding with a live entry; action statement :325-337; action_statement_timestamp from decided_at :439-441; first seen via carry_forward :184-191) | "No source statement covers" is decided per CVE id, not per finding and package (:272-273, :409). A not_affected statement for package A suppresses the affected statement for an exception on package B (r6b.1, probe). Latent: for valkey-compat digests the rescan reads valkey.yaml (r6b.10). |
| 6.39 | HELD | lint-vex-product.sh:130-132 names the file, CVE, product and status; run by validate.yml:193 | A statement with no products is never status-checked, but it compiles to nothing (compile-vex.sh:268). |
| 6.40 | PARTIAL | compile-vex.sh:145-201 (keeps timestamp; last_updated on a change of status, action statement, subcomponents or issue links) | When the verified read of the previous document fails, the run treats it as "no previous document": first seen resets to today's report time and the replaced document is re-attested, with the run green (reattest.sh:178-187,231; r6b.2). |
| 6.41 | PARTIAL | compile-vex.sh:312-315 (expired), :413-414 (no affected from an expired entry), :376-384 (under_investigation with the lapse note, first seen carried) | Same per-CVE skip as 6.38: if any source statement covers the CVE for another package, the lapsed finding gets no statement (:364; r6b.1). Latent valkey-compat keying (r6b.10). |
| 6.42 | PARTIAL | reattest.sh:142-163 (cosign attest --type vuln --replace per manifest, before the compile at :205) | A digest whose scan failed is skipped whole (reattest.sh:134-140) and does not fail the step (:276 counts only "failed"). The scan step itself exits 0 (rescan.yml:200-218). The run is green while that digest's attested report stays the last successful one (r6b.4). |
| 6.43 | HELD | reattest.sh:214-244 (statement-set comparison against the verified document; count read from .att for the index and each manifest; --replace on the digest and each manifest; a failure is counted and exits 1) | |
| 6.44 | OWNER-SIDE | Registry state. Asserted daily by check-attestation-count.sh (rescan.yml:432) after the repair in reattest.sh:225-236 | The release attests OpenVEX without --replace (build.yml:1113,1125). A second release attest on one digest would leave two until the next rescan repairs it. |
| 6.45 | HELD | check-attestation-count.sh:35-59 (n != 1 fails, named) feeding rc in rescan.yml:432,439 | A crane read failure counts as 0 (:26-27). That fails closed but under the wrong name. |
| 6.46 | PARTIAL | status.go:309-353 (first seen and decided from the statement), :474-479 (first seen never later than published), :489-505 (fixed = first day absent when the repository was fully scanned), previous body rescan.yml:742-761 | The previous-status lookup swallows a GitHub failure (rescan.yml:752-753, "or true"). The clocks then start fresh, dropping fixed rows and the earlier first-seen times, silently (r6b.3). The step is skipped when any re-attestation fails (rescan.yml:744; r6b.13). A finding's decision can come from a statement about another package (r6b.1). |
| 6.47 | PARTIAL | status.go:624-761 (table and fenced JSON), decision.go:44-76 (status, justification, statement, notes, links), rescan.yml:866-890 (issue and catalogue-status artifact), page via rescan.yml:895-900 | "One status issue": the same swallowed lookup creates a second "Catalogue status" issue (rescan.yml:874-880; r6b.3). Skipped on any re-attestation failure (r6b.13). The body grows without bound toward GitHub's body limit (r6b.14). |
| 6.49 | HELD | catalogue-policy.yaml:167-220 (aperture, ceilings, kev_ceiling, expiry_warning, support statement with both sentences); triage-policy.sh:62-119 refuses holes | |
| 6.50 | HELD | build.yml:883-894 to check-exceptions.sh gate, :109-130 (KEV tier, else the severity in the report, else the largest ceiling; names file, id, span and tier) | Depends on a valid KEV set. A well-formed but empty feed is r6b.6 (6.59). |
| 6.51 | PARTIAL | rescan.yml:422-423 to check-exceptions.sh rescan, :97-101,114-130 | Reports are found by "exception file name + __*.json" (:101), but rescan reports are named by repository (rescan.yml:176,198). An image with no reports today (failed scan, r6b.4) or a definition publishing under another name (valkey-compat, r6b.10) is tiered by the largest ceiling, and a severity breach passes silently. |
| 6.52 | HELD | lifecycle.go:345-386 (close when no in-aperture report, no incomplete digest, at least one examined), closeAbsent :495-515 names every examined digest and the scanner and DB versions (rescan.yml:246); applied after re-attestation rescan.yml:311-355 | |
| 6.53 | HELD | lifecycle.go:374-386, closeCovered :442-487 (coverage = ignored, not_affected or fixed in the report; each covering artifact named) | |
| 6.54 | HELD | Inputs are today's reports (attested before the apply, rescan.yml:325-332), SBOMs read through verification (fetch-sboms.sh:51-55) and triage/vex. Lifecycle writes no triage artifact. | |
| 6.55 | HELD | scan-image.sh:74 --show-suppressed; fill-scanner-db.sh:35-87 (DB origin and UpdatedAt, refusing when absent) in both arms (build.yml:1051, reattest.sh:155-157); TRIVY_DB_REPOSITORY set (build.yml:51, rescan.yml:54) | |
| 6.56 | HELD | lifecycle.go:442-456 (accepted, then not_affected, else fixed), :495-623 (SBOMs of the named images' repositories only; removed; absent; no image means all) | Packages are matched by name only (lifecycle.go:589). Not probed against live SBOMs. |
| 6.57 | HELD | lifecycle.go:389-412 (lowest-numbered closed issue, no open twin, reported in aperture), rescan.yml:356-365 | Closed issues past --limit 2000 only raise a warning (rescan.yml:240-243). |
| 6.58 | HELD | reattest.sh:178-183 (cosign verify-attestation --type openvex per declared role identity and issuer); SBOMs via fetch-sboms.sh:49-55. Scan reports are never read back from the registry. | |
| 6.59 | PARTIAL | build.yml:889-894 (a failed fetch is named, exit 1); check-exceptions.sh:57-61 (an unparseable file exits 2) | A response that parses as JSON but holds no "vulnerabilities" key ({}) is evaluated as an empty KEV set and passes (check-exceptions.sh:58; probe rc=0). r6b.6. |
| 6.60 | PARTIAL | rescan.yml:422-428 (fetch failure gives rc=1, named), :423 (unparseable file exits 2, so rc=1), rescan.yml:607, rescan-status main.go:142-150 | {} passes as in 6.59 (r6b.6). An unparseable file fails the run, but the issue set is still built and filed with "KEV: no" (rescan.yml:607 checks only -s; rescan-report main.go:62-67 warns and continues; probe). r6b.7. |
| 6.61 | PARTIAL | rescan.yml:805-858 (status data, enumeration, admission proof, expiry report into --out-html), page.go:72-168, page.html.tmpl:39-89, upload rescan.yml:895-900, deploy :1040-1054 | "Attested that day" is drawn from whether a compiled document exists (page.html.tmpl:55, status.go:207,403, inputs.go:69-83), not whether the attestation succeeded (reattest.sh:205-241; r6b.9). A malformed page switch leaves the page off without a failure (r6b.11). |
| 6.62 | PARTIAL | rescan.yml:1043 (the job runs only when status produced a date), deploy failure (Pages off) fails the job, read-back rescan.yml:1059-1078 | The read-back compares generated_at, a calendar date (status.go:548), not a run identity. A second run the same day whose deployment did not take passes on the first run's data (r6b.8). |

## Findings

**r6b.1 A source statement for one package hides the compiled statements for another package with the same CVE id (6.38, 6.41; status 6.46). Severity: high (latent: needs one CVE id on two packages of one image).**
- *The sentence:* 6.38 adds an affected statement for every unexpired exception "naming a finding ... that no source statement under triage/vex/ covers". 6.41 records under_investigation "for each finding it named that that digest's attested scan report lists".
- *The code:* compile-vex.sh:272-273 adds the CVE id to "covered" for any not_affected or fixed source statement, whatever its subcomponents. :364 (reported findings) and :409 (ignorefile suppressions) then skip every finding with that id.
- *Probe:* a not_affected statement scoped to pkg:golang/pkgA, plus an exception or a reported finding on pkg:golang/pkgB, compiled to the not_affected statement alone. Trivy still reports or ignores pkgB, but the document says nothing about it.
- *Knock-on:* status.go:316-345 reads the CVE's decision from any statement with that id, so the status shows pkgB as "decided (not_affected)" while it is uncovered or excepted.
- *Who is affected:* a consumer reading the attested document, and the status clocks.

**r6b.2 A failed verified read of the previous OpenVEX document resets first seen and replaces the attested document, with the run green (6.40; 6.38 and 6.41 first-seen clauses). Severity: high.**
- *The code:* reattest.sh:178-181 runs "cosign verify-attestation ... || true", with no retry, unlike fetch-sboms.sh:48-61. A Sigstore or registry blip gives previous_n=0, then previous="" (:184-187), so COMPILE_VEX_PREVIOUS is unset (:203). compile-vex.sh:189-190 then stamps today's report time as first seen. "differs" is true when no previous document is given (:222), so the document is re-attested with --replace (:229-236) and counts as a success.
- *Why it sticks:* the next day's previous document is the reset one, so the loss is permanent.
- *Signals that exist:* the record shows it (previous_documents 0 while openvex_before.index.openvex is 1), but nothing fails on that mismatch. The status's first seen survives only through status.go:474-479.
- *Who is affected:* every consumer of the attested document's timestamps.

**r6b.3 The previous-status lookup swallows GitHub errors: the clock history is lost and a second status issue is created (6.46, 6.47). Severity: high.**
- *The code:* rescan.yml:752-753 runs number=$(gh issue list ... || true). On an API failure the number is empty, previous.md is empty (:758), and rescan-status only warns and starts from today's evidence (main.go:173-174).
- *What is lost:* findings absent today (fixed rows and their days-to-fix) drop out of the data entirely (status.go:489-505 needs Previous), and the earlier first-seen protection is gone.
- *The duplicate:* status_publish then creates a new "Catalogue status" issue (rescan.yml:877-880). From then on the lookup takes "first" of the open matches (:753), so which history continues is down to search order. The old issue stays open and stale.
- *Who is affected:* the published status and page, and the owner's view. Nothing fails.

**r6b.4 A failed scan of a platform manifest leaves the rescan green, and that digest goes un-re-attested (6.42; 6.51). Severity: medium.**
- *The code:* the scan step warns and counts (rescan.yml:200-206) and ends on an echo (:218), so it exits 0. reattest.sh:134-140 skips the digest, and :276 fails only on "failed", not "skipped". Nothing downstream fails on it: the lifecycle keeps the issues open (lifecycle.go:264-274); the status marks the digest unscanned; check-exceptions.sh rescan tiers that image's exceptions by the largest ceiling (:101,125-126).
- *What is wrong as a result:* the digest's attested scan report and OpenVEX stay at the last successful day, and every cve close in the catalogue is blocked, with only a warning annotation and a summary count.
- *Claims the code contradicts:* rescan.yml:321-324 ("The run is red by the digest's name either way"). rescan.yml:18-20 and docs/lanes.md:731 describe skip-and-count accurately.

**r6b.5 A failed read of the open-issue map is replaced by {} and the compile runs on it (6.37; 6.40 noise). Severity: medium.**
- *The code:* rescan.yml:280-282 ("... > issues.json || echo '{}' > issues.json"). The reattest guard only checks that the file is non-empty (:300-302), so it passes.
- *Effect:* the compile writes statements without their "tracked in" links. Links are part of the change shape (compile-vex.sh:197), so last_updated is stamped and the documents are re-attested, and again the next day when the links return.
- *Same pattern outside scope:* the dedup step (rescan.yml:630, 6.3) re-files every open finding on a gh failure.

**r6b.6 A KEV response that parses but is empty ({}, or a JSON error body) is evaluated as "nothing is KEV-listed" in both arms (6.59, 6.60). Severity: medium.**
- *The code:* check-exceptions.sh:58 reads .get("vulnerabilities") or [], and ParseKEV (report.go:367-377) returns an empty map too. The fetch only checks HTTP success (build.yml:890, rescan.yml:422), not shape or size.
- *Probe:* {} gives exit 0 in both gate and rescan modes, with every exception tiered by severity or the largest ceiling. <html> correctly gives exit 2.
- *Effect:* tiers, issue KEV fields and the status's KEV ceilings all silently read "not listed".

**r6b.7 An unparseable KEV file fails the rescan but still files the day's issues with "KEV: no" (6.60, and 6.3 outside scope). Severity: medium.** Known input, confirmed.
- *The code:* the run is red by name, through check-exceptions.sh exit 2 giving rc=1 (rescan.yml:423), and the status refuses (rescan-status main.go:147-148). But enrich only checks -s (rescan.yml:607), and rescan-report warns and continues with an empty KEV map (main.go:62-67).
- *Probe:* three issues with "KEV | no |", exit 0. The KEV field is fixed at filing.
- *Document claims the code contradicts:* docs/lanes.md:877 ("no issue set is built on a KEV status nobody evaluated") and the comment at rescan.yml:603-606.

**r6b.8 The page read-back is keyed on a date, not on the run (6.62). Severity: medium.**
- *The code:* generated_at is todayStr, a YYYY-MM-DD date (status.go:364,548; rescan.yml:864). The read-back compares only that (rescan.yml:1068-1069).
- *The miss:* a second run on the same day, a dispatch or a kev-synthetic drill (which publishes, see r6b.17), passes on the morning run's data if its own deployment did not take. The data already carries "run" (status.go:137), which would identify the run.
- *Document claim the code contradicts:* docs/user-manual.md:942-943 ("until its generated_at is the run's").

**r6b.9 "Attested" on the page means a document was compiled, not that it was attested (6.61; also 6.47's "as attested"). Severity: low.**
- *The code:* "Document: d.Document != nil" (status.go:403) is set from the presence of reattest/<work>/out/*.openvex.json (inputs.go:69-83), and drawn as "attested" (page.html.tmpl:55). reattest.sh:205-241 compiles and then may fail to attest, so the page says "attested" for that digest. The run is red that day.
- *Document claim the code contradicts:* docs/user-manual.md:851-852 ("Only the attested document is read"). The decision column is read from the same compiled file.

**r6b.10 The rescan keys exceptions and reports by the repository's last segment, not the definition (6.38, 6.41, 6.51). Severity: medium, latent.**
- *The code:* rescan.yml:176 sets name to the repository's last path segment and passes it as the definition to compile-vex.sh (:192) and scan-image.sh (:200). So a valkey-compat digest (image .../valkey, image/valkey-compat/image.yaml:18) is scanned and compiled against triage/accepted-risk/valkey.yaml. The release path uses valkey-compat.yaml (build.yml:555,562,1076 with matrix.name), which the lint accepts (lint-accepted-risk.sh:201-202). check-exceptions.sh rescan looks for valkey-compat__*.json (:101), which never exists.
- *Effect once such a file exists:* the release document carries affected statements that the next rescan drops; the finding is reported and filed; the tiers fall to the largest ceiling. No such file exists today.

**r6b.11 A malformed page (or provenance) switch does not fail the switches step (6.61's WHERE clause; Req 7.7). Severity: low.** Known input, confirmed.
- *The code:* rescan.yml:103-104 runs echo "page=$(scripts/release-policy.sh . page)". Under set -euo pipefail the substitution's exit 2 is lost to echo.
- *Probe:* "page=" printed, exit 0. page is then empty, so the page upload and job are skipped and the run stays green, apart from the reader's ::error annotation.
- *Claim the code contradicts:* the comment at rescan.yml:97-98 ("a malformed switch fails here by name"). docs/lanes.md:755 records the gap correctly.

**r6b.12 The "scanned without its VEX" fence cannot trigger. Severity: low.**
- *The code:* VEXUnresolved is set only when a compile report exists with an empty digest (inputs.go:97-106, findings.go:51-53). But the scan step always passes the enumeration's digest (rescan.yml:192), and a failed compile writes no report (compile-vex.sh:474-483 runs only on success; probe: no report file). Its "|| true" (rescan.yml:192) then lets the scan run without --vex, and nothing marks that digest.
- *Claims the code contradicts:* rescan.yml:189-190 ("every path writes a report"); triage/README.md:193 and docs/user-manual.md:825 ("scanned without its VEX, blocks every close"); docs/user-manual.md:564 and :1748 (an "unresolved, no VEX applied" row). The summary branch at rescan.yml:976-977 is dead.
- *Why low:* the validate lints make a failing compile unlikely.

**r6b.13 Status, issue and page are withheld whole when any one digest's re-attestation fails (6.46, 6.47, 6.61). Severity: low.**
- *The code:* rescan.yml:744 runs status_previous only when steps.reattest.outcome is success, and every status step chains from it. One Rekor failure on one digest suppresses the day's status and page for all definitions. A step skipped because an earlier one failed is a gap by the method.
- *Mitigation:* the choice is stated in design.md:305-306 and named in the run.

**r6b.14 The status issue body grows without bound (6.47). Severity: low, latent.**
- *The code:* fixed findings are carried forward for ever (status.go:489-505), and the body embeds the full JSON with every attested note and link (status.go:756-759). Past GitHub's issue-body limit, gh issue edit fails (rescan.yml:875) every day.
- *Effect:* this fails by name, not silently, and the persisted record (6.46) then stops advancing.

**r6b.15 Document: triage/README.md:214-215 says "Scan and feed failures soft-fail (skip + warn)". Severity: low.**
- *The code:* a KEV feed failure fails the run (rescan.yml:422-428, Req 6.60). Only scans and EPSS (rescan.yml:612-613) soft-fail.
- The README's own :67-70 says the KEV case right. Known input, confirmed.

**r6b.16 Document: design.md:1697 says a Trivy DB outage means the "daily rescan soft-fails with issue". Severity: low.**
- *The code:* no issue is filed on a scan or DB failure. Each manifest is skipped with a warning (rescan.yml:200-206). The run is red only if another step trips over the outage, such as the smoke test's own trivy run (rescan.yml:552). See r6b.4. Known input, confirmed.

**r6b.17 Document: design.md:1744 says "A drill run is red by name and publishes attestations only: the issue set, the status and the page wait for the next scheduled run". Severity: low.**
- *The code:* with kev-synthetic the substituted feed is fetched like the real one (rescan.yml:415-423), and enrich, report, file, status and page all run. docs/user-manual.md:628-631 describes this correctly. Only kev-outage matches design.md.

**r6b.18 Document: the manual's scan-gate steps (docs/user-manual.md:342-399, steps 1 to 8) omit the step "exception tiers against KEV (Req 6.50)" (build.yml:883-894). Severity: low.**
- That step fails a pull request on an over-tier exception or a KEV outage (6.50, 6.59). The list also writes the aperture as a fixed HIGH,CRITICAL (:380). Known input, confirmed.

**r6b.19 Document: docs/user-manual.md:859-860 says "A Pages dashboard, if one is ever wanted, is presentation over that JSON". Severity: low (wording).**
- The page exists and is deployed daily (rescan.yml:892-900,1040-1078).

## Known input

The items in scope:

- **rescan.yml:102-104 cannot fail on a malformed switch: CONFIRMED.** Bash probe: echo "page=$(failing)" under set -euo pipefail exits 0. The page is silently off, and the comment at rescan.yml:97-98 claims otherwise (r6b.11).
- **A KEV file that downloads but does not parse still yields an issue set (Req 6.60): CONFIRMED.**
  - The run does go red (check-exceptions.sh:57-61 exit 2, then rescan.yml:423) and the status refuses (rescan-status main.go:147-148).
  - But rescan.yml:607 checks only that the file is non-empty, and rescan-report main.go:62-67 continues without KEV. Probe: three issues built with "KEV: no".
  - Wider than reported: a file that parses as {} passes everything silently in both arms (r6b.6).
- **design.md's error table files an issue on a Trivy outage: CONFIRMED** (design.md:1697 vs rescan.yml:200-206; r6b.16).
- **triage/README.md says feed failures soft-fail (KEV fails the run): CONFIRMED** (triage/README.md:214-215 vs rescan.yml:422-428; r6b.15).
- **The manual's scan gate list lacks the KEV tiers step: CONFIRMED** (docs/user-manual.md:342-399 vs build.yml:883-894; r6b.18).

Out of scope here (Req 2, 3, 6.3 to 6.7, 7, 9): not read for a verdict. These are the refresh-definition and Actions keying, the verify recipe's pipefail, the tag step order, portability and consumers.gating, main_sec.json, PR path filters, Req 2.5, Decisions 2, 6 and 10, the manual's cron, tag and smoke lines, "one issue per CVE", empty vex/ and accepted-risk/, and SECURITY.md. One related thing was seen in passing: the dedup step's "|| true" (rescan.yml:630) would re-file every open finding on a gh failure (6.3).

## Counts

HELD 16, PARTIAL 12, NOT HELD 0, OWNER-SIDE 1; document findings 5 standalone (r6b.15 to r6b.19), plus 10 further document or comment claims contradicted inside the code findings:

1. rescan.yml:321-324 (r6b.4)
2. lanes.md:877 (r6b.7)
3. rescan.yml:603-606 (r6b.7)
4. user-manual.md:942-943 (r6b.8)
5. user-manual.md:851-852 (r6b.9)
6. rescan.yml:97-98 (r6b.11)
7. rescan.yml:189-190 (r6b.12)
8. triage/README.md:193 (r6b.12)
9. user-manual.md:825 (r6b.12)
10. user-manual.md:564,1748 (r6b.12)
