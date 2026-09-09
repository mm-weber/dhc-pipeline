package rescan

import (
	"strings"
	"testing"
)

// The catalogue page (Req 6.61; task 15.8): one card per definition drawn
// from the status data, the clocks, revocations and support statement
// beneath. Every number on it is the JSON's or a count over it.

// The status test's repository and digest constants are reused; the compat
// digest is the one the valkey chart's variant publishes beside it.
const pageValkey = valkeyRepo

func pageStatus() StatusData {
	yes, no := true, false
	return StatusData{
		SchemaVersion: 1, GeneratedAt: "2026-09-09", Run: "https://github.com/mm-weber/dhc-pipeline/actions/runs/7",
		Policy: StatusPolicy{Aperture: []string{"CRITICAL", "HIGH"}, Ceilings: map[string]int{"CRITICAL": 30, "HIGH": 90}, KEVCeiling: 14},
		Repositories: []RepoStatus{
			{Repository: grafanaRepo, Digests: []DigestStatus{
				{Digest: grafanaIdx, Tags: []string{"13-alpine3.23", "13.1.5-alpine3.23"}, Platforms: []string{"linux/amd64", "linux/arm64"}, Scanned: true, Document: true, Admitted: &yes}}},
			{Repository: pageValkey, Digests: []DigestStatus{
				{Digest: valkeyIdx, Tags: []string{"9-alpine3.23"}, Platforms: []string{"linux/amd64"}, Scanned: true, Document: true, Admitted: &no},
				{Digest: compatIdx, Tags: []string{"9-alpine3.23-compat"}, Platforms: []string{"linux/amd64"}, Scanned: false, Document: true}}},
		},
		Findings: []FindingClock{
			{Repository: grafanaRepo, ID: "CVE-2026-1", Severity: "HIGH", Digests: []string{grafanaIdx}, Status: "undecided", FirstSeen: "2026-09-01T00:00:00Z", AgeDays: days(8), CeilingDays: days(90)},
			{Repository: grafanaRepo, ID: "CVE-2026-2", Severity: "CRITICAL", KEV: true, Digests: []string{grafanaIdx}, Status: "undecided", FirstSeen: "2026-08-01T00:00:00Z", AgeDays: days(39), CeilingDays: days(14), OverCeiling: true},
			{Repository: grafanaRepo, ID: "CVE-2026-3", Severity: "HIGH", Digests: []string{grafanaIdx}, Status: "decided", Decision: "affected", FirstSeen: "2026-09-01T00:00:00Z", Decided: "2026-09-03T00:00:00Z", DaysToDecision: days(2)},
			{Repository: grafanaRepo, ID: "CVE-2026-4", Severity: "HIGH", Status: "fixed", FirstSeen: "2026-08-01T00:00:00Z", Fixed: "2026-08-11", DaysToFix: days(10)},
			{Repository: pageValkey, ID: "CVE-2026-5", Severity: "HIGH", Digests: []string{compatIdx}, Status: "decided", Decision: "not_affected", FirstSeen: "2026-09-01T00:00:00Z", Decided: "2026-09-01T00:00:00Z", DaysToDecision: days(0)},
			{Repository: pageValkey, ID: "CVE-2026-6", Severity: "HIGH", Status: "decided", Decision: "affected", FirstSeen: "2026-09-01T00:00:00Z", Decided: "2026-09-02T00:00:00Z", DaysToDecision: days(1)},
		},
		Aggregates:     StatusAggregates{Findings: 5, Undecided: 2, OverCeiling: 1, Decided: 2, Fixed: 1, OldestUndecidedDays: days(39)},
		Revocations:    []Revocation{{Image: pageValkey, Digest: "sha256:" + strings.Repeat("c", 64), Reason: "withdrawn <b>", Replacement: "none", Withdrawal: "delete-version", Advisory: "https://github.com/mm-weber/dhc-pipeline/security/advisories/GHSA-1111-2222-3333", Date: "2026-09-07"}},
		Support:        &SupportStatement{SupportedSet: "the digests each definition's current tags: reference", Superseded: "scanned and attested daily; outside issue scope"},
		SupersededTags: 3,
	}
}

func pageDefinitions() []Definition {
	return []Definition{
		{Name: "grafana", Active: true, Repository: grafanaRepo, Tags: []string{"13-alpine3.23", "13.1.5-alpine3.23"}},
		{Name: "valkey", Active: true, Repository: pageValkey, Tags: []string{"9-alpine3.23"}},
		{Name: "valkey-compat", Active: false, Repository: pageValkey, Tags: []string{"9-alpine3.23-compat", "9.1-alpine3.23-compat"}},
	}
}

func TestBuildPage_OneCardPerDefinition(t *testing.T) {
	p := BuildPage(pageStatus(), pageDefinitions(), []Expiry{
		{Definition: "grafana", Message: "CVE-2026-3 expires in 9 days (2026-09-18)"},
		{Definition: "valkey-compat", Lapsed: true, Message: "CVE-2026-9 expired_at 2026-09-01 is in the past"},
	})
	if len(p.Cards) != 3 || p.Cards[0].Name != "grafana" || p.Cards[2].Name != "valkey-compat" {
		t.Fatalf("one card per definition, declared order: %+v", p.Cards)
	}
	g := p.Cards[0]
	if !g.Active || len(g.Digests) != 1 || g.Digests[0].Digest != grafanaIdx || len(g.Digests[0].Platforms) != 2 || g.Digests[0].Admitted == nil || !*g.Digests[0].Admitted {
		t.Errorf("the card carries the repository's digests its tags reference, with platforms and the admission verdict: %+v", g.Digests)
	}
	if len(g.Severities) != 2 || g.Severities[0].Severity != "CRITICAL" || g.Severities[0].Count != 1 || g.Severities[0].OverCeiling != 1 ||
		g.Severities[1].Severity != "HIGH" || g.Severities[1].Count != 2 || g.Severities[1].Undecided != 1 {
		t.Errorf("findings by aperture severity, fixed ones left out, undecided and over-ceiling counted: %+v", g.Severities)
	}
	if g.Undecided != 2 || g.OverCeiling != 1 || g.Fixed != 1 {
		t.Errorf("the card's totals: %+v", g)
	}
	if len(g.Expiries) != 1 || g.Expiries[0].Message != "CVE-2026-3 expires in 9 days (2026-09-18)" {
		t.Errorf("lapsing exceptions attributed by the exception file's name: %+v", g.Expiries)
	}
	// The shared repository: the compat card carries only the digest its own
	// tags reference, and only the findings on that digest.
	v, c := p.Cards[1], p.Cards[2]
	if len(v.Digests) != 1 || v.Digests[0].Digest != valkeyIdx || v.Digests[0].Admitted == nil || *v.Digests[0].Admitted {
		t.Errorf("valkey's card: its own digest, not admitted today: %+v", v.Digests)
	}
	if len(c.Digests) != 1 || c.Digests[0].Digest != compatIdx || c.Digests[0].Admitted != nil || c.Digests[0].Scanned {
		t.Errorf("valkey-compat's card: its own digest, admission not checked, not scanned: %+v", c.Digests)
	}
	if c.Active || len(c.Unpublished) != 1 || c.Unpublished[0] != "9.1-alpine3.23-compat" {
		t.Errorf("inactive, with the declared tag no digest carries today listed: %+v", c)
	}
	if v.Severities[1].Count != 1 || c.Severities[1].Count != 2 || c.Fixed != 0 {
		t.Errorf("findings attributed by digest; one naming no digest is the repository's and shows on both cards: valkey %+v, compat %+v", v.Severities, c.Severities)
	}
	if len(c.Expiries) != 1 || !c.Expiries[0].Lapsed {
		t.Errorf("a lapsed exception is carried as lapsed: %+v", c.Expiries)
	}
}

func TestRenderCataloguePage_ShowsTheDataAndNothingElse(t *testing.T) {
	s := pageStatus()
	html := RenderCataloguePage(BuildPage(s, pageDefinitions(), []Expiry{{Definition: "grafana", Message: "CVE-2026-3 expires in 9 days (2026-09-18) <script>x</script>"}}))
	for _, want := range []string{
		"<!doctype html>",
		"<title>dhc catalogue</title>",
		"generated 2026-09-09",
		`href="https://github.com/mm-weber/dhc-pipeline/actions/runs/7"`,
		"The supported set is the digests each definition&#39;s current tags: reference",
		"scanned and attested daily; outside issue scope",
		"3 superseded tag",
		`<h2 id="grafana">grafana</h2>`, "active", `<h2 id="valkey-compat">valkey-compat</h2>`, "inactive",
		"13-alpine3.23", "13.1.5-alpine3.23", "sha256:837727cbdb70", "linux/amd64, linux/arm64",
		"scanned", "attested", "admitted by the verification policy", "not admitted", "admission not checked",
		"CRITICAL 1", "HIGH 2", "undecided 2", "over ceiling 1", "fixed 1",
		"CVE-2026-3 expires in 9 days (2026-09-18) &lt;script&gt;x&lt;/script&gt;",
		`declared, no digest today: <span class="mono">9.1-alpine3.23-compat</span>`,
		"<td>CVE-2026-2</td>", "39 / 14",
		"withdrawn &lt;b&gt;", "GHSA-1111-2222-3333",
		`href="metrics.json"`,
		"aperture CRITICAL, HIGH", "CRITICAL 30 days", "HIGH 90 days", "KEV 14 days",
	} {
		if !strings.Contains(html, want) {
			t.Errorf("page lacks %q", want)
		}
	}
	if strings.Contains(html, "<script") {
		t.Errorf("the page runs no code and every message is escaped")
	}
	if strings.Contains(html, "http://") || strings.Count(html, "https://") != strings.Count(html, `href="https://`) {
		t.Errorf("the page loads nothing from anywhere: every https:// is a link, not a resource")
	}
}

func TestRenderCataloguePage_NoDefinitionsIsNamed(t *testing.T) {
	html := RenderCataloguePage(BuildPage(pageStatus(), nil, nil))
	if !strings.Contains(html, "no definitions were listed") {
		t.Errorf("an empty definitions list is named on the page, not an empty grid")
	}
}
