package rescan

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// ---- builders for the status tests ----

const (
	grafanaRepo = "ghcr.io/mm-weber/dhc/grafana"
	valkeyRepo  = "ghcr.io/mm-weber/dhc/valkey"
	grafanaIdx  = "sha256:837727cbdb7058ee72e8a67c78cd2110677746127cc4da969abc2733ec514569"
	valkeyIdx   = "sha256:505b98c4b31828bb25b20d2ca56047b127e6bfc480857fecd65f3089fb8ac714"
	compatIdx   = "sha256:6e080491a512c7e8aee6d6ae0e5df9b9aefccf5522059a61a2cd86773d6c9029"
)

func stmt(cve, status, ts string) VEXStatement {
	return VEXStatement{Vulnerability: VEXVulnerability{Name: cve}, Status: status, Timestamp: ts,
		Products: []VEXProduct{{ID: "pkg:oci/x@" + grafanaIdx}}}
}
func affected(cve, ts, decidedAt string) VEXStatement {
	s := stmt(cve, "affected", ts)
	s.ActionStatementTimestamp = decidedAt
	return s
}
func doc(sts ...VEXStatement) *VEXDocument {
	return &VEXDocument{ID: "https://openvex.dev/docs/test", Statements: sts}
}

// present builds one report listing the given CVEs, reported or suppressed alike.
func present(createdAt string, reported []TrivyVuln, suppressed []TrivyVuln) TrivyReport {
	mods := make([]TrivyModified, 0, len(suppressed))
	for _, v := range suppressed {
		mods = append(mods, TrivyModified{Type: "vulnerability", Status: "ignored", Finding: v})
	}
	return TrivyReport{CreatedAt: createdAt, ArtifactName: "ghcr.io/mm-weber/dhc/x@sha256:manifest",
		Results: []TrivyResult{{Target: "bin", Vulnerabilities: reported, ExperimentalModifiedFindings: mods}}}
}
func high(cve string) TrivyVuln {
	return TrivyVuln{VulnerabilityID: cve, PkgName: "stdlib", Severity: "HIGH"}
}
func critical(cve string) TrivyVuln {
	return TrivyVuln{VulnerabilityID: cve, PkgName: "stdlib", Severity: "CRITICAL"}
}

func policyInputs(today string) StatusInputs {
	return StatusInputs{
		Today:      today,
		Run:        "https://github.com/mm-weber/dhc-pipeline/actions/runs/1",
		Aperture:   []string{"CRITICAL", "HIGH"},
		Ceilings:   map[string]int{"CRITICAL": 30, "HIGH": 90},
		KEVCeiling: 14,
		KEV:        map[string]bool{},
	}
}

func clock(t *testing.T, s StatusData, repo, cve string) FindingClock {
	t.Helper()
	for _, f := range s.Findings {
		if f.Repository == repo && f.ID == cve {
			return f
		}
	}
	t.Fatalf("no clock for %s %s in %+v", repo, cve, s.Findings)
	return FindingClock{}
}
func days(n int) *int { return &n }

// -----------------------------------------------------------------------------
// Req 6.46: the clocks are read from the attested statements
// -----------------------------------------------------------------------------

func TestBuildStatus_ClocksFromStatements(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.KEV["CVE-2026-00005"] = true
	in.Digests = []SupportedDigest{{
		Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13.1.5-alpine3.23"},
		Document: doc(
			affected("CVE-2026-00001", "2026-09-03T20:37:32.637857634Z", "2026-09-03T00:00:00Z"),
			stmt("CVE-2026-00002", "not_affected", "2026-07-26T00:00:00Z"),
			stmt("CVE-2026-00003", "under_investigation", "2026-08-20T06:00:00Z"),
			stmt("CVE-2026-00004", "under_investigation", "2026-07-01T06:00:00Z"),
			stmt("CVE-2026-00005", "under_investigation", "2026-08-15T06:00:00Z"),
		),
		Reports: []TrivyReport{present("2026-09-05T06:20:00Z",
			[]TrivyVuln{high("CVE-2026-00003"), critical("CVE-2026-00004"), high("CVE-2026-00005")},
			[]TrivyVuln{high("CVE-2026-00001"), high("CVE-2026-00002")})},
	}}
	s := BuildStatus(in)

	a := clock(t, s, grafanaRepo, "CVE-2026-00001")
	if a.Status != "decided" || a.Decision != "affected" || a.FirstSeen != "2026-09-03T20:37:32.637857634Z" || a.Decided != "2026-09-03T00:00:00Z" {
		t.Errorf("affected: decided from action_statement_timestamp, first seen from timestamp; got %+v", a)
	}
	if a.DaysToDecision == nil || *a.DaysToDecision != 0 || a.AgeDays != nil {
		t.Errorf("a decided finding has days_to_decision and no age; got %+v", a)
	}
	b := clock(t, s, grafanaRepo, "CVE-2026-00002")
	if b.Status != "decided" || b.Decision != "not_affected" || b.Decided != "2026-07-26T00:00:00Z" {
		t.Errorf("not_affected: decided from the statement timestamp; got %+v", b)
	}
	c := clock(t, s, grafanaRepo, "CVE-2026-00003")
	if c.Status != "undecided" || c.AgeDays == nil || *c.AgeDays != 16 || c.CeilingDays == nil || *c.CeilingDays != 90 || c.OverCeiling {
		t.Errorf("under_investigation HIGH: age 16 against 90; got %+v", c)
	}
	d := clock(t, s, grafanaRepo, "CVE-2026-00004")
	if d.Severity != "CRITICAL" || d.AgeDays == nil || *d.AgeDays != 66 || *d.CeilingDays != 30 || !d.OverCeiling {
		t.Errorf("under_investigation CRITICAL: age 66 over 30; got %+v", d)
	}
	e := clock(t, s, grafanaRepo, "CVE-2026-00005")
	if !e.KEV || *e.CeilingDays != 14 || *e.AgeDays != 21 || !e.OverCeiling {
		t.Errorf("KEV-listed: the KEV ceiling whatever the severity; got %+v", e)
	}
	if got := clock(t, s, grafanaRepo, "CVE-2026-00001").Digests; !reflect.DeepEqual(got, []string{grafanaIdx}) {
		t.Errorf("digests carrying the finding today: %v", got)
	}
}

func TestBuildStatus_ApertureAndSeverityAcrossDigests(t *testing.T) {
	in := policyInputs("2026-09-05")
	medium := TrivyVuln{VulnerabilityID: "CVE-2026-00009", PkgName: "x", Severity: "MEDIUM"}
	in.Digests = []SupportedDigest{
		{Repository: valkeyRepo, Digest: valkeyIdx, Tags: []string{"9.1.2-alpine3.23"},
			Document: doc(stmt("CVE-2026-00007", "under_investigation", "2026-09-01T00:00:00Z")),
			Reports:  []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00007"), medium}, nil)}},
		{Repository: valkeyRepo, Digest: compatIdx, Tags: []string{"9.1.2-alpine3.23-compat"},
			Document: doc(stmt("CVE-2026-00007", "under_investigation", "2026-09-02T00:00:00Z")),
			Reports:  []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{critical("CVE-2026-00007")}, nil)}},
	}
	s := BuildStatus(in)
	if len(s.Findings) != 1 {
		t.Fatalf("MEDIUM is outside the aperture and one finding spans both digests; got %+v", s.Findings)
	}
	f := s.Findings[0]
	if f.Severity != "CRITICAL" || !reflect.DeepEqual(f.Digests, []string{valkeyIdx, compatIdx}) || f.FirstSeen != "2026-09-01T00:00:00Z" {
		t.Errorf("severity is the max across digests, first seen the earliest; got %+v", f)
	}
}

func TestBuildStatus_TwoDigestsDecideTogether(t *testing.T) {
	in := policyInputs("2026-09-05")
	plain := SupportedDigest{Repository: valkeyRepo, Digest: valkeyIdx,
		Document: doc(affected("CVE-2026-00008", "2026-08-01T00:00:00Z", "2026-09-01T00:00:00Z")),
		Reports:  []TrivyReport{present("2026-09-05T06:00:00Z", nil, []TrivyVuln{high("CVE-2026-00008")})}}
	compat := SupportedDigest{Repository: valkeyRepo, Digest: compatIdx,
		Document: doc(stmt("CVE-2026-00008", "under_investigation", "2026-08-01T00:00:00Z")),
		Reports:  []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00008")}, nil)}}
	in.Digests = []SupportedDigest{plain, compat}
	if f := clock(t, BuildStatus(in), valkeyRepo, "CVE-2026-00008"); f.Status != "undecided" || f.Decided != "" {
		t.Errorf("one supported digest still under investigation keeps the finding undecided; got %+v", f)
	}
	compat.Document = doc(affected("CVE-2026-00008", "2026-08-01T00:00:00Z", "2026-09-03T00:00:00Z"))
	compat.Reports = plain.Reports
	in.Digests = []SupportedDigest{plain, compat}
	f := clock(t, BuildStatus(in), valkeyRepo, "CVE-2026-00008")
	if f.Status != "decided" || f.Decided != "2026-09-03T00:00:00Z" || f.DaysToDecision == nil || *f.DaysToDecision != 33 {
		t.Errorf("decided when the last supported digest carrying it was decided; got %+v", f)
	}
}

// -----------------------------------------------------------------------------
// Req 6.46: fixed is the first day absent, carried forward from the previous status data
// -----------------------------------------------------------------------------

func previousWith(findings ...FindingClock) *StatusData {
	return &StatusData{SchemaVersion: 1, GeneratedAt: "2026-09-04", Findings: findings}
}

func TestBuildStatus_FixedIsTheFirstDayAbsent(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.Previous = previousWith(FindingClock{Repository: grafanaRepo, ID: "CVE-2026-00010", Severity: "HIGH",
		Status: "undecided", FirstSeen: "2026-08-01T00:00:00Z"})
	in.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx,
		Document: doc(), Reports: []TrivyReport{present("2026-09-05T06:00:00Z", nil, nil)}}}
	f := clock(t, BuildStatus(in), grafanaRepo, "CVE-2026-00010")
	if f.Status != "fixed" || f.Fixed != "2026-09-05" || f.DaysToFix == nil || *f.DaysToFix != 35 || f.AgeDays != nil {
		t.Errorf("absent from every supported digest of its repository today: fixed today, 35 days after first seen; got %+v", f)
	}

	// the day after, the date stands
	in.Today = "2026-09-06"
	in.Previous = previousWith(f)
	g := clock(t, BuildStatus(in), grafanaRepo, "CVE-2026-00010")
	if g.Fixed != "2026-09-05" || *g.DaysToFix != 35 {
		t.Errorf("a fix date is carried forward, not recomputed; got %+v", g)
	}

	// and a finding that comes back is back, with its original first seen
	in.Today = "2026-09-07"
	in.Previous = previousWith(g)
	in.Digests[0].Document = doc(stmt("CVE-2026-00010", "under_investigation", "2026-09-07T06:00:00Z"))
	in.Digests[0].Reports = []TrivyReport{present("2026-09-07T06:00:00Z", []TrivyVuln{high("CVE-2026-00010")}, nil)}
	h := clock(t, BuildStatus(in), grafanaRepo, "CVE-2026-00010")
	if h.Status != "undecided" || h.Fixed != "" || h.FirstSeen != "2026-08-01T00:00:00Z" || *h.AgeDays != 37 {
		t.Errorf("a returning finding clears fixed and keeps first seen; got %+v", h)
	}
}

func TestBuildStatus_NoReportInventsNoAbsence(t *testing.T) {
	in := policyInputs("2026-09-05")
	prev := FindingClock{Repository: valkeyRepo, ID: "CVE-2026-00011", Severity: "HIGH",
		Status: "undecided", FirstSeen: "2026-08-20T00:00:00Z", AgeDays: days(15), CeilingDays: days(90)}
	in.Previous = previousWith(prev)
	in.Digests = []SupportedDigest{{Repository: valkeyRepo, Digest: valkeyIdx, Document: nil, Reports: nil}}
	f := clock(t, BuildStatus(in), valkeyRepo, "CVE-2026-00011")
	if f.Status != "undecided" || f.Fixed != "" || f.AgeDays == nil || *f.AgeDays != 16 {
		t.Errorf("a repository not scanned today carries its rows forward, ages advance, nothing is declared absent; got %+v", f)
	}
}

func TestBuildStatus_FirstSeenNeverMovesLater(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.Previous = previousWith(FindingClock{Repository: grafanaRepo, ID: "CVE-2026-00012", Severity: "HIGH",
		Status: "undecided", FirstSeen: "2026-07-01T00:00:00Z"})
	in.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx,
		Document: doc(stmt("CVE-2026-00012", "under_investigation", "2026-09-04T00:00:00Z")),
		Reports:  []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00012")}, nil)}}}
	if f := clock(t, BuildStatus(in), grafanaRepo, "CVE-2026-00012"); f.FirstSeen != "2026-07-01T00:00:00Z" {
		t.Errorf("first seen is the earliest of the statement and the published data; got %+v", f)
	}
}

func TestBuildStatus_PresentWithoutStatementIsUndecided(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx, Document: doc(),
		Reports: []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00013")}, nil)}}}
	f := clock(t, BuildStatus(in), grafanaRepo, "CVE-2026-00013")
	if f.Status != "undecided" || f.FirstSeen != "2026-09-05T06:00:00Z" || *f.AgeDays != 0 {
		t.Errorf("a reported finding no statement names is undecided, first seen from the report; got %+v", f)
	}
}

// -----------------------------------------------------------------------------
// Aggregates and the published forms (Req 6.47)
// -----------------------------------------------------------------------------

func TestBuildStatus_Aggregates(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.Previous = previousWith(
		FindingClock{Repository: grafanaRepo, ID: "CVE-2026-00020", Severity: "HIGH", Status: "fixed",
			FirstSeen: "2026-08-01T00:00:00Z", Fixed: "2026-08-11", DaysToFix: days(10)},
		FindingClock{Repository: grafanaRepo, ID: "CVE-2026-00021", Severity: "HIGH", Status: "undecided",
			FirstSeen: "2026-08-15T00:00:00Z"})
	in.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx,
		Document: doc(
			affected("CVE-2026-00022", "2026-08-01T00:00:00Z", "2026-08-05T00:00:00Z"),
			affected("CVE-2026-00023", "2026-08-01T00:00:00Z", "2026-08-21T00:00:00Z"),
			stmt("CVE-2026-00024", "under_investigation", "2026-05-01T00:00:00Z"),
		),
		Reports: []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{critical("CVE-2026-00024")},
			[]TrivyVuln{high("CVE-2026-00022"), high("CVE-2026-00023")})}}}
	s := BuildStatus(in)
	ag := s.Aggregates
	if ag.Findings != 5 || ag.Undecided != 1 || ag.OverCeiling != 1 || ag.Decided != 2 || ag.Fixed != 2 {
		t.Errorf("counts: 5 findings, 1 undecided (over its 30-day ceiling), 2 decided, 2 fixed (one today); got %+v", ag)
	}
	if ag.OldestUndecidedDays == nil || *ag.OldestUndecidedDays != 127 {
		t.Errorf("oldest undecided: 127 days; got %+v", ag.OldestUndecidedDays)
	}
	if ag.MedianDaysToDecision == nil || *ag.MedianDaysToDecision != 12 {
		t.Errorf("median days to decision of 4 and 20 is 12; got %v", ag.MedianDaysToDecision)
	}
	if ag.MedianDaysToFix == nil || *ag.MedianDaysToFix != 15.5 {
		t.Errorf("median days to fix of 10 and 21 is 15.5; got %v", ag.MedianDaysToFix)
	}
	if s.Policy.KEVCeiling != 14 || s.Policy.Ceilings["HIGH"] != 90 || !reflect.DeepEqual(s.Policy.Aperture, []string{"CRITICAL", "HIGH"}) {
		t.Errorf("the policy numbers travel with the data; got %+v", s.Policy)
	}
	if len(s.Repositories) != 1 || s.Repositories[0].Repository != grafanaRepo || len(s.Repositories[0].Digests) != 1 || !s.Repositories[0].Digests[0].Scanned {
		t.Errorf("the supported set is listed per repository; got %+v", s.Repositories)
	}
}

func TestBuildStatus_DeterministicOrder(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.Digests = []SupportedDigest{
		{Repository: valkeyRepo, Digest: valkeyIdx, Document: doc(stmt("CVE-2026-00002", "under_investigation", "2026-09-01T00:00:00Z")),
			Reports: []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00002")}, nil)}},
		{Repository: grafanaRepo, Digest: grafanaIdx, Document: doc(
			stmt("CVE-2026-00003", "under_investigation", "2026-09-01T00:00:00Z"),
			stmt("CVE-2026-00001", "under_investigation", "2026-09-01T00:00:00Z")),
			Reports: []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00003"), high("CVE-2026-00001")}, nil)}},
	}
	s := BuildStatus(in)
	got := []string{}
	for _, f := range s.Findings {
		got = append(got, shortName(f.Repository)+" "+f.ID)
	}
	want := []string{"grafana CVE-2026-00001", "grafana CVE-2026-00003", "valkey CVE-2026-00002"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("findings sorted by repository then id: got %v want %v", got, want)
	}
}

func TestRenderStatusIssue_RoundTrip(t *testing.T) {
	in := policyInputs("2026-09-05")
	in.KEV["CVE-2026-00031"] = true
	in.Previous = previousWith(FindingClock{Repository: grafanaRepo, ID: "CVE-2026-00033", Severity: "HIGH",
		Status: "fixed", FirstSeen: "2026-08-01T00:00:00Z", Fixed: "2026-08-11", DaysToFix: days(10)})
	in.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13-alpine3.23", "13.1.5-alpine3.23"},
		Document: doc(
			affected("CVE-2026-00030", "2026-09-03T20:37:32Z", "2026-09-03T00:00:00Z"),
			stmt("CVE-2026-00031", "under_investigation", "2026-08-01T00:00:00Z")),
		Reports: []TrivyReport{present("2026-09-05T06:00:00Z", []TrivyVuln{high("CVE-2026-00031")}, []TrivyVuln{high("CVE-2026-00030")})}}}
	s := BuildStatus(in)
	body := RenderStatusIssue(s)

	if !strings.Contains(body, StatusMarker) {
		t.Errorf("the body carries the hidden marker the workflow finds the issue by")
	}
	for _, want := range []string{"| grafana | CVE-2026-00031 | HIGH | yes | undecided |", "35 / 14", "| grafana | CVE-2026-00030 | HIGH | no | decided (affected) |", "2026-09-03", "fixed (1)"} {
		if !strings.Contains(body, want) {
			t.Errorf("table row missing %q in:\n%s", want, body)
		}
	}
	raw, ok := ExtractFencedJSON(body)
	if !ok {
		t.Fatalf("no fenced json block in:\n%s", body)
	}
	back, err := ParseStatus(raw)
	if err != nil {
		t.Fatalf("fenced block does not parse: %v", err)
	}
	want, _ := json.Marshal(s)
	got, _ := json.Marshal(back)
	if string(want) != string(got) {
		t.Errorf("the fenced block is the metrics JSON verbatim:\n%s\n!=\n%s", got, want)
	}
	if !strings.Contains(body, "over ceiling: 1") {
		t.Errorf("aggregates are in the prose: %s", body)
	}
}

func TestExtractFencedJSON_TakesTheBlockAfterTheMarker(t *testing.T) {
	body := "intro\n```json\n{\"decoy\": true}\n```\n" + StatusMarker + "\ntext\n```json\n{\"schema_version\": 1}\n```\n"
	raw, ok := ExtractFencedJSON(body)
	if !ok || strings.TrimSpace(string(raw)) != `{"schema_version": 1}` {
		t.Errorf("got %q ok=%v", raw, ok)
	}
	if _, ok := ExtractFencedJSON("no block here"); ok {
		t.Errorf("no block, no data")
	}
}

func TestParseVEX_VulnerabilityAsObjectOrString(t *testing.T) {
	obj := `{"@id":"x","statements":[{"vulnerability":{"name":"CVE-1"},"status":"affected","timestamp":"2026-01-01T00:00:00Z","action_statement_timestamp":"2026-01-02T00:00:00Z","products":[{"@id":"pkg:oci/x@sha256:1","subcomponents":[{"@id":"pkg:golang/stdlib@v1"}]}]}]}`
	d, err := ParseVEX([]byte(obj))
	if err != nil || d.Statements[0].Vulnerability.Name != "CVE-1" || d.Statements[0].ActionStatementTimestamp != "2026-01-02T00:00:00Z" {
		t.Errorf("object form: %v %+v", err, d)
	}
	str := `{"@id":"x","statements":[{"vulnerability":"CVE-2","status":"not_affected","timestamp":"2026-01-01T00:00:00Z"}]}`
	d, err = ParseVEX([]byte(str))
	if err != nil || d.Statements[0].Vulnerability.Name != "CVE-2" {
		t.Errorf("string form: %v %+v", err, d)
	}
}

func TestParseTrivy_ReadsSuppressedFindings(t *testing.T) {
	data := `{"CreatedAt":"2026-09-05T06:00:00Z","ArtifactName":"a","Results":[{"Target":"t","Vulnerabilities":[{"VulnerabilityID":"CVE-1","Severity":"HIGH"}],"ExperimentalModifiedFindings":[{"Type":"vulnerability","Status":"ignored","Source":"triage/accepted-risk/grafana.yaml","Finding":{"VulnerabilityID":"CVE-2","Severity":"HIGH"}}]}]}`
	r, err := ParseTrivy([]byte(data))
	if err != nil || r.CreatedAt != "2026-09-05T06:00:00Z" || len(r.Results[0].ExperimentalModifiedFindings) != 1 || r.Results[0].ExperimentalModifiedFindings[0].Finding.VulnerabilityID != "CVE-2" {
		t.Errorf("suppressed findings travel with the report (Req 6.55): %v %+v", err, r)
	}
}

func TestStatusWorkDirName(t *testing.T) {
	if got := StatusWorkDirName(valkeyRepo, compatIdx); got != "valkey__6e080491a512" {
		t.Errorf("the rescan's naming, <name>__<12 hex>: got %q", got)
	}
}

// -----------------------------------------------------------------------------
// Fixture attestations: the document attested to grafana 13.1.5 on 2026-09-04
// and that digest's amd64 report (trimmed to the fields the tool reads), with a
// prior status JSON in the shape the issue carries.
// -----------------------------------------------------------------------------

func TestBuildStatus_FixtureAttestations(t *testing.T) {
	read := func(name string) []byte {
		t.Helper()
		data, err := os.ReadFile(filepath.Join("testdata", "status", name))
		if err != nil {
			t.Fatal(err)
		}
		return data
	}
	document, err := ParseVEX(read("grafana.openvex.json"))
	if err != nil {
		t.Fatal(err)
	}
	report, err := ParseTrivy(read("grafana__837727cbdb70__linux-amd64.json"))
	if err != nil {
		t.Fatal(err)
	}
	previous, err := ParseStatus(read("previous.json"))
	if err != nil {
		t.Fatal(err)
	}
	in := policyInputs("2026-09-05")
	in.Previous = &previous
	in.Digests = []SupportedDigest{{Repository: grafanaRepo, Digest: grafanaIdx,
		Tags: []string{"13-alpine3.23", "13.1-alpine3.23", "13.1.5-alpine3.23"}, Document: &document, Reports: []TrivyReport{report}}}
	s := BuildStatus(in)

	if s.Aggregates.Findings != 14 || s.Aggregates.Decided != 13 || s.Aggregates.Fixed != 1 || s.Aggregates.Undecided != 0 {
		t.Errorf("13 suppressed findings, all decided, plus one the previous data knew and today's report does not list: %+v", s.Aggregates)
	}
	// an exception: decided at decided_at, first seen never later than published before
	e := clock(t, s, grafanaRepo, "CVE-2026-33818")
	if e.Status != "decided" || e.Decision != "affected" || e.Decided != "2026-09-03T00:00:00Z" || e.FirstSeen != "2026-08-16T06:03:58Z" || *e.DaysToDecision != 18 {
		t.Errorf("exception clock: %+v", e)
	}
	// a fixed statement from triage/vex: decided at its own timestamp
	f := clock(t, s, grafanaRepo, "CVE-2026-21728")
	if f.Decision != "fixed" || f.Decided != "2026-08-05T00:00:00Z" || f.FirstSeen != "2026-08-05T00:00:00Z" {
		t.Errorf("fixed statement clock: %+v", f)
	}
	// the finding the previous data tracked that no supported grafana digest lists today
	g := clock(t, s, grafanaRepo, "CVE-2026-42504")
	if g.Status != "fixed" || g.Fixed != "2026-09-05" || *g.DaysToFix != 31 {
		t.Errorf("absent today, fixed today: %+v", g)
	}
	if len(s.Repositories) != 1 || !s.Repositories[0].Digests[0].Scanned || !s.Repositories[0].Digests[0].Document {
		t.Errorf("the supported digest is listed as scanned with a document: %+v", s.Repositories)
	}
}
