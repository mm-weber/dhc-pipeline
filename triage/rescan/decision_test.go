package rescan

import (
	"strings"
	"testing"
)

// The decision beside the clock (Req 6.47 as amended; task 15.9): the
// statement a clock was read from carries the decision in its own words,
// and the published data keeps it.

func TestParseVEX_KeepsTheDecisionFields(t *testing.T) {
	d, err := ParseVEX([]byte(`{"@id":"x","statements":[{"vulnerability":{"name":"CVE-1"},"status":"affected",
	  "timestamp":"2026-09-08T09:44:19Z","action_statement_timestamp":"2026-09-03T00:00:00Z",
	  "action_statement":"transfer: waiting on a release. Upstream issue: https://github.com/grafana/grafana-zipkin-datasource/issues/94. Expires: 2026-11-02.",
	  "status_notes":"accepted-risk exception in grafana.yaml; real and shipped for a bounded time"},
	  {"vulnerability":{"name":"CVE-2"},"status":"not_affected","timestamp":"2026-07-26T00:00:00Z",
	  "justification":"vulnerable_code_not_in_execute_path","impact_statement":"The vulnerable API is never started."}]}`))
	if err != nil {
		t.Fatal(err)
	}
	a, b := d.Statements[0], d.Statements[1]
	if !strings.HasPrefix(a.ActionStatement, "transfer:") || a.StatusNotes == "" {
		t.Errorf("action statement and notes kept: %+v", a)
	}
	if b.Justification != "vulnerable_code_not_in_execute_path" || b.ImpactStatement == "" {
		t.Errorf("justification and impact statement kept: %+v", b)
	}
}

func decided(cve, status, ts string) VEXStatement {
	s := stmt(cve, status, ts)
	switch status {
	case "affected":
		s.ActionStatementTimestamp = "2026-09-03T00:00:00Z"
		s.ActionStatement = "transfer: waiting on a grafana release that bundles grafana-zipkin-datasource v12.4.7+ Upstream issue: https://github.com/grafana/grafana-zipkin-datasource/issues/94. Binaries: usr/share/grafana/data/plugins-bundled/zipkin/*. Expires: 2026-11-02."
		s.StatusNotes = "accepted-risk exception in grafana.yaml; real and shipped for a bounded time, not coverage (Req 6.8)"
	case "fixed":
		s.ImpactStatement = "Grafana 13.1.5 pins github.com/grafana/tempo at v1.5.1-0.20260427112133-525d1bab07e0, the same commit 13.1.1 pinned. The advisory's range sorts every v1-line pseudo-version below the fix, which is why scanners report this on a build that carries the remedy (GitHub compare: ahead_by 337, behind_by 0)."
		s.StatusNotes = "Commit ancestry against the pinned source, not a version comparison; see triage/LOG.md 2026-08-05."
	case "not_affected":
		s.Justification = "vulnerable_code_not_in_execute_path"
		s.ImpactStatement = "The vulnerability is in the Prometheus server's config API, which this image never starts."
	case "under_investigation":
		s.StatusNotes = "uncovered at release time in this digest's attested release-time scan report; awaiting a triage decision; tracked in https://github.com/mm-weber/dhc-pipeline/issues/186"
	}
	return s
}

func TestBuildStatus_CarriesTheAttestedDecision(t *testing.T) {
	in := policyInputs("2026-09-09")
	in.Digests = []SupportedDigest{{
		Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13.1.5-alpine3.23"},
		Document: doc(
			decided("CVE-2026-00001", "affected", "2026-09-08T09:44:19Z"),
			decided("CVE-2026-00002", "fixed", "2026-08-05T00:00:00Z"),
			decided("CVE-2026-00003", "not_affected", "2026-07-26T00:00:00Z"),
			decided("CVE-2026-00004", "under_investigation", "2026-09-09T11:33:11Z"),
		),
		Reports: []TrivyReport{present("2026-09-09T06:20:00Z",
			[]TrivyVuln{high("CVE-2026-00004")},
			[]TrivyVuln{high("CVE-2026-00001"), high("CVE-2026-00002"), high("CVE-2026-00003")})},
	}}
	s := BuildStatus(in)

	a := clock(t, s, grafanaRepo, "CVE-2026-00001").Attested
	if a == nil || a.Status != "affected" || a.Treatment != "transfer" || a.Expires != "2026-11-02" || !strings.HasPrefix(a.Statement, "transfer: waiting") || !strings.Contains(a.Notes, "exception in grafana.yaml") {
		t.Fatalf("an accepted risk: status, treatment, expiry, the action statement and the notes; got %+v", a)
	}
	if a.Summary != "transfer, accepted risk until 2026-11-02" {
		t.Errorf("the short form of an accepted risk: %q", a.Summary)
	}
	if len(a.Links) != 1 || a.Links[0].Label != "grafana-zipkin-datasource#94" || a.Links[0].URL != "https://github.com/grafana/grafana-zipkin-datasource/issues/94" {
		t.Errorf("the upstream issue, labelled repo#n, trailing period dropped: %+v", a.Links)
	}

	b := clock(t, s, grafanaRepo, "CVE-2026-00002").Attested
	if b == nil || b.Status != "fixed" || !strings.HasPrefix(b.Statement, "Grafana 13.1.5 pins") || b.Summary != "fixed: Grafana 13.1.5 pins github.com/grafana/tempo at v1.5.1-0.20260427112133-525d1bab07e0, the same commit 13.1.1 pinned" {
		t.Errorf("a fixed statement: its impact statement, the first sentence as the short form; got %+v", b)
	}

	c := clock(t, s, grafanaRepo, "CVE-2026-00003").Attested
	if c == nil || c.Justification != "vulnerable_code_not_in_execute_path" || c.Summary != "not affected: vulnerable code not in execute path" {
		t.Errorf("a not_affected statement: its justification, humanised in the short form; got %+v", c)
	}

	d := clock(t, s, grafanaRepo, "CVE-2026-00004").Attested
	if d == nil || d.Status != "under_investigation" || d.Summary != "undecided, awaiting a triage decision" || len(d.Links) != 1 || d.Links[0].Label != "dhc-pipeline#186" {
		t.Errorf("an undecided finding: its notes and the tracking issue; got %+v", d)
	}

	// The record round-trips, and a finding absent tomorrow keeps yesterday's decision.
	in2 := policyInputs("2026-09-10")
	in2.Previous = &s
	in2.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13.1.5-alpine3.23"},
		Document: doc(), Reports: []TrivyReport{present("2026-09-10T06:20:00Z", nil, nil)}}}
	s2 := BuildStatus(in2)
	f := clock(t, s2, grafanaRepo, "CVE-2026-00001")
	if f.Status != "fixed" || f.Attested == nil || f.Attested.Treatment != "transfer" {
		t.Errorf("fixed on the first day absent, the last attested decision carried: %+v", f)
	}
}

func TestDecisionLinks(t *testing.T) {
	links := decisionLinks("see https://github.com/acme/tool/issues/12, https://github.com/acme/tool/pull/13 and https://grafana.com/security/advisory/x). Twice: https://github.com/acme/tool/issues/12.", "https://github.com/mm-weber/dhc-pipeline/blob/main")
	want := []Link{
		{Label: "tool#12", URL: "https://github.com/acme/tool/issues/12"},
		{Label: "tool#13", URL: "https://github.com/acme/tool/pull/13"},
		{Label: "grafana.com", URL: "https://grafana.com/security/advisory/x"},
	}
	if len(links) != len(want) {
		t.Fatalf("labelled, deduplicated, punctuation dropped: %+v", links)
	}
	for i := range want {
		if links[i] != want[i] {
			t.Errorf("link %d: got %+v, want %+v", i, links[i], want[i])
		}
	}
}

func TestBuildStatus_LinksTheFilesTheNotesName(t *testing.T) {
	in := policyInputs("2026-09-09")
	in.SourceURL = "https://github.com/mm-weber/dhc-pipeline/blob/main"
	in.HandStatements = map[string]bool{"CVE-2026-00002": true}
	in.Digests = []SupportedDigest{{
		Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13.1.5-alpine3.23"},
		Document: doc(decided("CVE-2026-00001", "affected", "2026-09-08T09:44:19Z"), decided("CVE-2026-00002", "fixed", "2026-08-05T00:00:00Z")),
		Reports:  []TrivyReport{present("2026-09-09T06:20:00Z", nil, []TrivyVuln{high("CVE-2026-00001"), high("CVE-2026-00002")})},
	}}
	s := BuildStatus(in)
	a := clock(t, s, grafanaRepo, "CVE-2026-00001").Attested
	if len(a.Links) != 2 || a.Links[1].Label != "exception file" || a.Links[1].URL != "https://github.com/mm-weber/dhc-pipeline/blob/main/triage/accepted-risk/grafana.yaml" {
		t.Errorf("the exception file the notes name, after the statement's own links: %+v", a.Links)
	}
	b := clock(t, s, grafanaRepo, "CVE-2026-00002").Attested
	if len(b.Links) != 2 || b.Links[0].Label != "LOG" || b.Links[0].URL != "https://github.com/mm-weber/dhc-pipeline/blob/main/triage/LOG.md" ||
		b.Links[1].Label != "statement" || b.Links[1].URL != "https://github.com/mm-weber/dhc-pipeline/blob/main/triage/vex/CVE-2026-00002.openvex.json" {
		t.Errorf("the LOG the notes name and the hand-written statement on disk: %+v", b.Links)
	}
	in.SourceURL = ""
	s = BuildStatus(in)
	if got := clock(t, s, grafanaRepo, "CVE-2026-00002").Attested.Links; len(got) != 0 {
		t.Errorf("no source URL, no file links invented: %+v", got)
	}
}

func TestRenderStatusIssue_DecisionColumn(t *testing.T) {
	in := policyInputs("2026-09-09")
	in.Digests = []SupportedDigest{{
		Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13.1.5-alpine3.23"},
		Document: doc(decided("CVE-2026-00001", "affected", "2026-09-08T09:44:19Z"), decided("CVE-2026-00004", "under_investigation", "2026-09-09T11:33:11Z")),
		Reports:  []TrivyReport{present("2026-09-09T06:20:00Z", []TrivyVuln{high("CVE-2026-00004")}, []TrivyVuln{high("CVE-2026-00001")})},
	}}
	body := RenderStatusIssue(BuildStatus(in))
	for _, want := range []string{
		"| Age / ceiling | Decision |",
		"| transfer, accepted risk until 2026-11-02 ([grafana-zipkin-datasource#94](https://github.com/grafana/grafana-zipkin-datasource/issues/94)) |",
		"| undecided, awaiting a triage decision ([dhc-pipeline#186](https://github.com/mm-weber/dhc-pipeline/issues/186)) |",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("issue lacks %q in:\n%s", want, body)
		}
	}
}

func TestRenderCataloguePage_DecisionColumn(t *testing.T) {
	in := policyInputs("2026-09-09")
	in.SourceURL = "https://github.com/mm-weber/dhc-pipeline/blob/main"
	in.Digests = []SupportedDigest{{
		Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13.1.5-alpine3.23"},
		Document: doc(decided("CVE-2026-00001", "affected", "2026-09-08T09:44:19Z"), decided("CVE-2026-00002", "fixed", "2026-08-05T00:00:00Z")),
		Reports:  []TrivyReport{present("2026-09-09T06:20:00Z", nil, []TrivyVuln{high("CVE-2026-00001"), high("CVE-2026-00002")})},
	}}
	s := BuildStatus(in)
	html := RenderCataloguePage(BuildPage(s, []Definition{{Name: "grafana", Active: true, Repository: grafanaRepo, Tags: []string{"13.1.5-alpine3.23"}}}, nil))
	for _, want := range []string{
		"<th>Decision</th>",
		"transfer, accepted risk until 2026-11-02",
		`<a href="https://github.com/grafana/grafana-zipkin-datasource/issues/94">grafana-zipkin-datasource#94</a>`,
		`<a href="https://github.com/mm-weber/dhc-pipeline/blob/main/triage/accepted-risk/grafana.yaml">exception file</a>`,
		"<details><summary>the statement</summary>",
		"Binaries: usr/share/grafana/data/plugins-bundled/zipkin/*. Expires: 2026-11-02.",
		"real and shipped for a bounded time, not coverage (Req 6.8)",
		"fixed: Grafana 13.1.5 pins github.com/grafana/tempo",
		`<a href="https://github.com/mm-weber/dhc-pipeline/blob/main/triage/LOG.md">LOG</a>`,
	} {
		if !strings.Contains(html, want) {
			t.Errorf("page lacks %q", want)
		}
	}
}
