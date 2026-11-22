# Open items

The live task list: what is still open, one decision each, the owner's.
Closed items and the older plans are archived in
[docs/archive/todo-until-2026-11-21.md](../docs/archive/todo-until-2026-11-21.md)
(the file as it stood on 2026-11-21); each piece of work runs as a conductor
track (`conductor/tracks.md`).

## Carried from the SLSA track (task group 18, closed 2026-11-20)

- [ ] CARRIED, a read: the first scheduled release read: it waits for the first day
      a scheduled rebuild differs from the released digest (the
      scheduled build of 2026-11-19, run 44538564027, found all
      seven unchanged and published nothing)
- [ ] CARRIED, a read: the first scheduled rescan in the mode `report`
      after #426, its status line "21 of 21" (FR-3's last criterion;
      its smoke test is also the provenance step's first daily run)
- [ ] CARRIED, the owner's: remove the spike's scratch package
      `ghcr.io/mm-weber/slsa-spike` (the workspace token cannot), close
      #401 unmerged, delete the branch `slsa-spike` (ADR 0005 and the LOG
      keep the record). Its condition, Kyverno's read of the first
      released digest through the spike workflow, is met (spike run
      44411812054).
- [ ] Candidate, the owner's idea of 2026-11-13, not started: reshape
      the pipeline into local composite actions where a group of steps
      is one unit (the provenance trio a first candidate). Its own
      track: the lints (`lint-release-steps.sh`,
      `lint-workflow-policy.sh`) read `build.yml`'s steps and would
      have to follow a `uses: ./...` step into the action first.

## Open items

- [ ] The documentation consolidated, task group 19 (opened 2026-11-20, conductor
      track docs-consolidation_20261120): the owner's calls of that day, Mermaid
      graphs in the Markdown, working notes to `docs/archive/`,
      overlapping documents merged into fewer, the SLSA lane drawn first.
      Seven pull requests by the plan; phase 0 is the track itself.
- [ ] The comment on line 4 of `image/valkey-compat/image.yaml` still names
      `docs/concepts.md`, merged into the manual's Part VI on 2026-11-22
      ("The variant taxonomy"). Repoint it with that definition's next real
      change: a change to a definition file alone rebuilds and republishes
      its image.
- [ ] The requirements checked against the code (the owner's call of
      2026-11-21): a track of its own, right after task group 19. A
      read-only review holds every criterion of
      `.specs/dhc-catalogue-mvp/requirements.md` against the code and the
      ledger and lists what it finds; each fix is its own decision and pull
      request, code test-first. It reads the consolidated documents and
      lands before the successor is seeded (task 12.1).
      Input already found while the lanes were drawn (phase 5 of the
      documentation track, 2026-11-22; each read in the code, none yet in
      a run; docs/lanes.md draws what the code does today):
      - The code: the refresh-definition.sh task is keyed on the
        github-tags datasource only (renovate.json5:416), which the
        github-actions manager also uses, so an Actions bump would run it
        on .github/workflows and fail; no Actions bump pull request has
        ever opened, and the Dependency Dashboard (#5) holds ten Actions
        updates under "Other Branches"; the one read, actions/checkout,
        has no branch. The published
        verify recipe has no pipefail, so a failed cosign|jq pipe exits 0
        for a consumer (render-verification.sh; the smoke test adds
        pipefail itself). The tag step writes every tag before checking
        any (build.yml:1229-1238). rescan.yml:102-104 cannot fail on a
        malformed switch. A KEV file that downloads but does not parse
        still yields an issue set (Req 6.60). The build portability step
        and consumers.gating can stay green on a failed consumer. No
        workflow step checks that main_sec.json requires the gates
        (Req 9.8). A pull request changing only the gate's scripts builds
        nothing; one changing only test/go.mod runs no e2e leg.
      - The documents: Req 2.5 ("no artifacts from that run") against
        fail-fast: false; Decision 2 and CONVENTIONS.md say every built-in
        Renovate manager is off (two are on); Decision 6's --recursive
        attest and its retired Req citations; Decision 10 names the
        manual's recipe (the README's runs); the manual's scan gate list
        lacks the KEV tiers step, its cron table names one publish reason
        of five, its tag line says a mismatch leaves tags untouched, its
        smoke summary claims exit codes; design.md's error table files an
        issue on a Trivy outage (none is filed); triage/README.md says
        feed failures soft-fail (KEV fails the run), "one issue per CVE"
        (GHSA ids too) and that vex/ and accepted-risk/ start empty;
        SECURITY.md says no digest has been revoked (the drill entry,
        2026-11-05) and dates its advisory line 2026-09-07.
- [ ] Kyverno's `kyverno.io/v1` ClusterPolicy is deprecated (seen by 18.2,
      2026-11-11): Kyverno 1.19.2 prints on every `kyverno apply` that the
      kind "will be removed in a future release" in favour of its newer
      policy kinds (ImageValidatingPolicy for image verification). The four
      published policies, the rendered verification policy among them, are
      of that kind, and ADR 0005 measured the 2.28 rule in that kind only.
      No removal version is named; the day a Kyverno bump drops it,
      the render, the drift check and the daily must-reject proof all
      change. One decision: when to migrate, and whether the 2.28 rule of
      task 18.5 is written in the old kind or the new one.
- [ ] A rebuilt digest's statements restart their clock (seen by 16.9,
      2026-10-28): the release-time compile in build.yml reads no previous
      document, so the document of a rebuilt digest carries the release
      scan's time as every statement's `timestamp`, while the status carries
      the finding's first-seen date across the definition's digests from its
      own data (drill-app: 2026-10-28T11:43:23Z in the document, 2026-10-18
      on the status). Req 6.40 names the timestamp as first seen for life;
      either hand the previous digest's attested document to the release
      compile or state that the document's clock is per digest; the owner's
      call.
- [ ] One ceiling, three readers (found by 16.5, 2026-10-27):
      `triage.ceilings` is the clock undecided findings are measured against
      (status, Req 6.47), the tier every unexpired exception's span must fit
      (`check-exceptions.sh`, Req 6.50, 6.51) and the lint's outer bound
      (`lint-accepted-risk.sh`, Req 6.11), so the decision clock cannot be
      tightened without re-tiering every standing exception (grafana's nine
      transfers run 60 days). Either declare a separate decision ceiling per
      severity for the status, or accept the coupling and say so in the
      policy file's comment; a requirements amendment either way, the owner's
      call.
- [ ] The two expiry clocks (found by 16.3, seen live by 16.4 on
      2026-10-26): Trivy drops an ignore entry at midnight UTC of its
      `expired_at`; `lint-accepted-risk.sh`, `check-exceptions.sh` and
      `compile-vex.sh` keep the entry live through that day. For one day the
      gate and the scan count the finding while the lint warns `0 days`, the
      page says lapsing and the attested document carries the generic
      uncovered note instead of the lapse note (run 40328859055). Either
      align the three scripts to Trivy's clock (the expiry date is the first
      day without coverage) or document the expiry day as such in the
      exception lane's notes; test-first, its own pull request, the owner's
      call.
- [ ] Req 7.4 messages in the log only (found by 16.15, 2026-10-26): the
      revocation record's schema check (yamale) and the chart gate (kyverno
      apply) fail their step and print what they refused to the log, with no
      GitHub annotation; wrap their output in `::error::` lines naming the
      entry, the field or the policy. Small; its own pull request. Also
      noted: the pin lint does not read a chart's split repository/tag/digest
      values (its scope note says so); the Renovate manager fixture step
      refused the two malformed chart pins instead.
- [ ] The e2e runner pin (2026-11-02): `e2e.yml`'s suite job runs on
      `ubuntu-24.04` while GitHub moves `ubuntu-latest` to 26.04 (Docker 29,
      the containerd image store), whose `docker save` kind 0.33.0's
      `load docker-image` cannot import (kind issue 3795): the probe load
      failed on every chart-deploying run from 2026-10-28 04:57Z, last pass
      2026-10-27 20:33Z, nothing in the repo changed between. A label pins
      the OS line, not the image (no hash exists for a hosted runner), so
      `scripts/check-runner-image-store.sh` runs before the load: it names
      the image the job got (`ImageOS`/`ImageVersion`) in a notice and the
      step summary, and fails by name on the containerd image store. Lift
      the pin when a kind release loads from that store, or move the step
      to `docker save --platform linux/amd64` + `kind load image-archive`
      (verified locally to produce a single-manifest archive); its own pull
      request, the owner's call.
- [ ] The status keeps a retired definition's rows (found by 16.16,
      2026-11-08): drill-app's three finding rows and the HIGH's clock
      (21 / 90) stay in the status issue and the page, carried from the
      previous data, after the definition left the catalogue. Drop or mark
      rows whose repository no definition declares; its own pull request.
- [ ] The 13.1.9 repackage bump (2026-11-10): unlimited on the dependency
      dashboard, so Renovate creates it on its next run. It fixes the server's
      toolchain finding and retires the first entry of the 2026-11-10 round.
      Renovate must supply the per-build tarball URL and both per-arch
      checksums, which this environment cannot fetch.
- [ ] Grafana's 2026-12-12 sitting (set 2026-11-10): sixteen entries come due
      at once, the nine of 2026-10-13 and the seven of 2026-11-10. With one
      finding fixable only outside the lane and two resting on prebuilt plugin
      binaries nobody here can rebuild, the question is whether this image keeps
      its tags or takes a step down the retirement table. The owner's call.
- [ ] Transient external failures need a human to re-run (three on 2026-11-10):
      a GitHub release-asset 504, a buildx cache 503 on the valkey build of
      #349, and a CISA KEV feed outage on the grafana build of #394 each failed
      a run that nothing in the change had caused. The rerun-failed-jobs
      endpoint answers 403 to this repository's token, so each one needs the
      owner, and an empty commit does not re-trigger a pull request's checks:
      GitHub registered no synchronize for one on 2026-11-10. Read what the KEV
      fetch's retry actually does before adding another (Req 6.59, 6.60), and
      decide whether a documented re-run path or a narrower retry is the answer.
      Its own pull request.
- [ ] The tool-pin lane stalls silently (found 2026-11-10): a pinned-executable
      bump needs a hand-added checksum commit, which Renovate reads as an edit
      and stops rebasing, so the pull request sits behind main until someone
      ticks its rebase box. Four had sat since 2026-10-31 and nothing surfaced
      it. Options: have the refresh tooling record the checksum so the branch
      stays Renovate's, or report stalled bumps in the daily run. Its own pull
      request.
- [ ] Grafana reactivated, the follow-ups (track
      `reactivate-grafana_20261110`, 2026-11-10): the first active day read
      (the rebuild's package-set comparison, the digest and tags it publishes,
      the release-time scan's uncovered count, the end-to-end suite's grafana
      component and its `http-health` probe); the bot's bump to the current
      13.1.x and the finding set its gate reports, which is the evidence the
      three undecided findings wait on (#300, #338 go-jose 4.1.6, #375 x/net
      0.62.0); the nine transfers of 2026-10-13 re-decided on 2026-12-12 with
      their exit restored, the stdlib halves fixed by a 13.1.9 build and the
      plugin halves whatever that tarball bundles. What a 13.1.9 tarball
      carries in its two prebuilt plugin binaries is unmeasured here: the
      download host is outside the allowlist, the gate is the measurement.
- [ ] Dashboard usability amendment (owner liked the direction, parked on
      2026-10-08): a legend for the four statuses; on fixed rows, the version
      and component change that fixed them; a release line per definition;
      "fix available upstream" on open transfers; the superseded set as a
      table; header with expiring-soon and scanner versions. Spec amendment
      first (Req 6.61 criteria, one design decision, tasks), then one pull
      request per section.
- [ ] Upstream valkey-helm: PR 263 rebased onto their main (head 10854ee,
      mergeable, DCO green) awaiting sgissi's answer on the three-point
      Sentinel plan; #264 fixed by their #266 (unreleased, Chart.yaml still
      0.12.0); the chart.yaml comment beside our pin and the check script
      verify the fix when the 0.13 bump arrives. Nothing goes to valkey-io
      without the owner's explicit approval.
- [ ] The TL;DR rule's enforcement: `docs/CONVENTIONS.md` and the pull
      request template (#278) state it; no lint enforces it, and Renovate's
      pull requests would need an exemption first. The owner's call.

## Calendar (owner-side)

- 2026-10-20 07:26Z: `.keys/90d_dhc_classic_readpackages.txt` expires (a
  classic PAT, read:packages). No script or workflow reads it and every dhc
  package answers anonymous reads: let it lapse or delete the file.
  `.keys/90d_hardened-app.txt` (2026-07-19) expired on 2026-10-19; nothing
  reads it either, the hardened-app clone uses its own key (below). Dates
  measured 2026-10-19 from the API's expiry header, never from a token.
- 2026-10-22: register row M5, re-measure cosign v3 with the current kyverno
  and trivy.
- 2026-10-29: the valkey-helm fork PAT expires (`/workspace/repos/valkey-helm/.keys/fork.pat`).
- 2026-11-21: register row M6, re-verify the DHI terms memo.
- 2026-11-24: the valkey compat decision's review-by date (4.8 lapses the day
  after unless renewed).
- 2026-12-05: the hardened-app clone's PAT expires
  (`/workspace/repos/hardened-app/.keys/90d_hardened_app.pat`).
- 2026-12-12: the nine grafana transfers of 2026-10-13 re-decided; grafana
  inactive, no 13.1.8 build will fix them: accept, or level two.
- 2027-01-13: the drill-app clone's PAT expires
  (`/workspace/repos/drill-app/.keys/90d_drill_app.pat`).
- 2027-01-14: the ninety-day clocks of the five kin-openapi findings in
  grafana 13.1.7, all decided not affected (#274, #276 and #287 on
  2026-10-21, closed on evidence 2026-10-22; #275 and #277 recorded
  2026-10-23, closed on evidence the same day by run 39959263177).
- 2027-01-19: the ninety-day clock of CVE-2026-111943 (#300) runs out on all
  six images, grafana included.
- 2027-01-17: `.keys/90d-pat.txt` expires (extended 2026-10-19; the agent's
  git and gh access); rotate and replace the file. RENOVATE_TOKEN was
  regenerated on 2026-10-19 after expiring that day (Renovate down from
  04:02Z to 21:17Z, two runs failed at startup). DHI_TOKEN stopped being
  accepted on 2026-10-20 (the nightly 39402331027 failed at every dhi.io
  login, nothing built); rotated by the owner the same day, the re-run of
  20:45Z green. The new expiries are unknown here (secrets API 403): note
  them beside this line.

## Working rules the owner set (apply in every session)

- One decision at a time, framed as pull requests; state the goal before the
  mechanism; ask one question, then stop. Plain language with one example per
  concept in conversation; the formal register stays inside repo artifacts.
- Amend the spec before implementing (EARS validator:
  `node .claude/skills/ears-notation/scripts/ears-validator.js .specs/dhc-catalogue-mvp/requirements.md`);
  criteria never reuse retired numbers. Each piece of work is a conductor
  track (`conductor/workflow.md`): an EARS spec, a phased plan, progress in
  the plan, one pull request per phase.
- TDD: the failing test first, watched red; RED and GREEN as separate agents,
  the orchestrator commits; every script has a `_test.sh` and both are
  enumerated in validate.yml (the completeness check).
- Every triage call is the owner's; reach order mitigate, not_affected,
  transfer, accept, avoid; one finding at a time, evidence first.
- Every pull request body opens with a `## TL;DR` section, updated whenever a
  review comes in with each finding's disposition (rule of 2026-10-16,
  `docs/CONVENTIONS.md`); the pull request text is part of the change.
- Nothing to upstream projects without the owner's explicit approval; fork
  commits carry no `#N` (cross-references the parent's issue).
- No em dashes anywhere; no session URLs in pull requests or commits; tokens
  only in `.keys/` files; `gh` runs with `GH_TOKEN=$(cat .keys/90d-pat.txt)`.
- GitHub quirks learned: the PAT has Actions read only, so `gh run rerun`
  reports "cannot be rerun; its workflow file may be broken" (a 403); re-runs
  are the owner's from the Actions tab. "The job was not acquired by Runner of
  type hosted" is GitHub's runner capacity, not the workflow. Local gh 2.23.0
  mangles `\u` escapes in JSON; read issue bodies with curl. grype's database
  host is outside the devcontainer allowlist (trivy's is on ghcr.io); the
  cisa.gov KEV feed is blocked too (github.com/cisagov/kev-data mirrors it).
  The ruleset puts every open pull request "behind" after each merge: rebase
  with `--force-with-lease`, the rebase re-signs.

## Regenerating the ledger's evidence (if the seed is ever questioned)

- Steps per run: `gh api repos/mm-weber/dhc-pipeline/actions/runs/<id>/jobs`
  (job and step names with conclusions); tally first success and first
  failure per step over all runs of build.yml and rescan.yml.
- Which step refused a pull request, and when first:
  `.../actions/workflows/<wf>/runs?event=pull_request&status=failure` then the
  jobs of each; the earliest runs need `&created=2026-07-18..2026-07-31`
  because listings cap at the newest runs.
- Automerges: a merge whose timestamp falls inside a Renovate run's
  `created_at..updated_at` window (`.../workflows/renovate.yml/runs?created=<date>`).
- Registry state: `cosign verify`, `verify-attestation --type openvex|vuln|spdxjson`
  with `--trusted-root trusted_root.json --offline` (the root from
  `repos/sigstore/root-signing/contents/targets/trusted_root.json`), on the
  platform manifest digests (scan reports and VEX are attested per manifest).

---
