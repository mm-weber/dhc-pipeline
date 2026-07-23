package rescan

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// ---- image refs used across tests (full ArtifactName form) ----
const (
	grafanaRef = "ghcr.io/mm-weber/dhc/grafana:0.1.0-alpine3.23"
	valkeyRef  = "ghcr.io/mm-weber/dhc/valkey:8.1.3-alpine3.23"
	alphaRef   = "ghcr.io/mm-weber/dhc/alpha:1.0.0"
	bravoRef   = "ghcr.io/mm-weber/dhc/bravo:1.0.0"
	charlieRef = "ghcr.io/mm-weber/dhc/charlie:1.0.0"
	deltaRef   = "ghcr.io/mm-weber/dhc/delta:1.0.0"
)

// ---- tiny builders / lookups ----

func vuln(id, pkg, installed, fixed, sev, title, url string) TrivyVuln {
	return TrivyVuln{
		VulnerabilityID:  id,
		PkgName:          pkg,
		InstalledVersion: installed,
		FixedVersion:     fixed,
		Severity:         sev,
		Title:            title,
		PrimaryURL:       url,
	}
}

func rep(artifact string, vulns ...TrivyVuln) TrivyReport {
	return TrivyReport{
		ArtifactName: artifact,
		Results:      []TrivyResult{{Target: artifact, Vulnerabilities: vulns}},
	}
}

func findFinding(fs []Finding, cve string) (Finding, bool) {
	for _, f := range fs {
		if f.CVE == cve {
			return f, true
		}
	}
	return Finding{}, false
}

func findIssue(is []Issue, cve string) (Issue, bool) {
	for _, i := range is {
		if i.CVE == cve {
			return i, true
		}
	}
	return Issue{}, false
}

func findingCVEs(fs []Finding) []string {
	out := []string{}
	for _, f := range fs {
		out = append(out, f.CVE)
	}
	return out
}

func issueCVEs(is []Issue) []string {
	out := []string{}
	for _, i := range is {
		out = append(out, i.CVE)
	}
	return out
}

// -----------------------------------------------------------------------------
// Aggregate
// -----------------------------------------------------------------------------

func TestAggregate_MergesImagesAndMaxSeverity(t *testing.T) {
	reports := []TrivyReport{
		rep(grafanaRef, vuln("CVE-2024-1111", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "HIGH", "openssl issue", "https://x/1111")),
		rep(valkeyRef,
			vuln("CVE-2024-1111", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "CRITICAL", "openssl issue", "https://x/1111"),
			vuln("CVE-2024-2222", "libssl3", "3.1.4-r5", "3.1.4-r6", "HIGH", "tls issue", "https://x/2222"),
		),
	}

	got := Aggregate(reports)

	a, ok := findFinding(got, "CVE-2024-1111")
	if !ok {
		t.Fatalf("expected a Finding for CVE-2024-1111, got findings for %v", findingCVEs(got))
	}
	if a.Severity != "CRITICAL" {
		t.Errorf("CVE-2024-1111 severity = %q, want CRITICAL (max across images)", a.Severity)
	}
	wantImages := []string{grafanaRef, valkeyRef} // sorted ascending, unique
	if !reflect.DeepEqual(a.Images, wantImages) {
		t.Errorf("CVE-2024-1111 images = %v, want %v", a.Images, wantImages)
	}

	b, ok := findFinding(got, "CVE-2024-2222")
	if !ok {
		t.Fatalf("expected a Finding for CVE-2024-2222, got findings for %v", findingCVEs(got))
	}
	if b.Severity != "HIGH" {
		t.Errorf("CVE-2024-2222 severity = %q, want HIGH", b.Severity)
	}
	if !reflect.DeepEqual(b.Images, []string{valkeyRef}) {
		t.Errorf("CVE-2024-2222 images = %v, want %v", b.Images, []string{valkeyRef})
	}
}

func TestAggregate_IgnoresLowerSeverities(t *testing.T) {
	reports := []TrivyReport{
		rep(grafanaRef,
			vuln("CVE-2024-1111", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "HIGH", "keep me", "https://x/1111"),
			vuln("CVE-2024-5000", "zlib", "1.3-r0", "1.3-r1", "MEDIUM", "drop me", "https://x/5000"),
			vuln("CVE-2024-6000", "ncurses", "6.4-r0", "", "LOW", "drop me", "https://x/6000"),
			vuln("CVE-2024-7000", "musl", "1.2.4-r0", "1.2.4-r1", "UNKNOWN", "drop me", "https://x/7000"),
		),
	}

	got := Aggregate(reports)

	if _, ok := findFinding(got, "CVE-2024-1111"); !ok {
		t.Fatalf("expected HIGH finding CVE-2024-1111 to be kept, got %v", findingCVEs(got))
	}
	for _, dropped := range []string{"CVE-2024-5000", "CVE-2024-6000", "CVE-2024-7000"} {
		if _, ok := findFinding(got, dropped); ok {
			t.Errorf("non HIGH/CRITICAL %s must be ignored, but it appears in %v", dropped, findingCVEs(got))
		}
	}
}

func TestAggregate_DeterministicOrder(t *testing.T) {
	reports := []TrivyReport{
		rep(grafanaRef,
			vuln("CVE-2024-0009", "p1", "1", "2", "CRITICAL", "c", "https://x/9"),
			vuln("CVE-2024-0008", "p2", "1", "2", "HIGH", "h", "https://x/8"),
			vuln("CVE-2024-0002", "p3", "1", "2", "CRITICAL", "c", "https://x/2"),
			vuln("CVE-2024-0003", "p4", "1", "2", "HIGH", "h", "https://x/3"),
		),
	}

	got := Aggregate(reports)

	// CRITICAL findings first (id ascending), then HIGH findings (id ascending).
	want := []string{"CVE-2024-0002", "CVE-2024-0009", "CVE-2024-0003", "CVE-2024-0008"}
	if !reflect.DeepEqual(findingCVEs(got), want) {
		t.Errorf("deterministic order = %v, want %v", findingCVEs(got), want)
	}
}

// -----------------------------------------------------------------------------
// BuildIssues
// -----------------------------------------------------------------------------

func TestBuildIssues_ExcludesExisting(t *testing.T) {
	in := Inputs{
		Reports: []TrivyReport{
			rep(grafanaRef,
				vuln("CVE-2024-0001", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "CRITICAL", "keep", "https://x/1"),
				vuln("CVE-2024-9999", "busybox", "1.36.1-r0", "1.36.1-r1", "HIGH", "already open", "https://x/9999"),
			),
		},
		EPSS:     map[string]EPSSScore{},
		KEV:      map[string]bool{},
		Existing: map[string]bool{"CVE-2024-9999": true},
	}

	got := BuildIssues(in)

	if _, ok := findIssue(got, "CVE-2024-0001"); !ok {
		t.Fatalf("new CVE-2024-0001 must produce an issue, got %v", issueCVEs(got))
	}
	if _, ok := findIssue(got, "CVE-2024-9999"); ok {
		t.Errorf("already-tracked CVE-2024-9999 must be excluded, but it appears in %v", issueCVEs(got))
	}
}

func TestBuildIssues_EnrichesEPSSAndKEV(t *testing.T) {
	in := Inputs{
		Reports: []TrivyReport{
			rep(grafanaRef,
				vuln("CVE-2024-0001", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "CRITICAL", "both maps", "https://x/1"),
				vuln("CVE-2024-0002", "libxml2", "2.11.5-r0", "", "HIGH", "no epss", "https://x/2"),
			),
			rep(valkeyRef,
				vuln("CVE-2024-0003", "libssl3", "3.1.4-r5", "3.1.4-r6", "CRITICAL", "no kev", "https://x/3"),
			),
		},
		EPSS: map[string]EPSSScore{
			"CVE-2024-0001": {Score: 0.1234, Percentile: 0.5678},
			"CVE-2024-0003": {Score: 0.9900, Percentile: 0.9900},
		},
		KEV:      map[string]bool{"CVE-2024-0001": true}, // 0002 and 0003 absent
		Existing: map[string]bool{},
	}

	got := BuildIssues(in)

	both, ok := findIssue(got, "CVE-2024-0001")
	if !ok {
		t.Fatalf("expected issue for CVE-2024-0001, got %v", issueCVEs(got))
	}
	wantEPSS := fmt.Sprintf("%.4f (%.1f pct)", 0.1234, 0.5678*100) // "0.1234 (56.8 pct)"
	if !strings.Contains(both.Body, wantEPSS) {
		t.Errorf("CVE-2024-0001 body missing formatted EPSS %q\n---body---\n%s", wantEPSS, both.Body)
	}
	if !strings.Contains(both.Body, "yes") {
		t.Errorf("CVE-2024-0001 in KEV must render the KEV cell as yes\n---body---\n%s", both.Body)
	}

	noEPSS, ok := findIssue(got, "CVE-2024-0002")
	if !ok {
		t.Fatalf("expected issue for CVE-2024-0002, got %v", issueCVEs(got))
	}
	if !strings.Contains(noEPSS.Body, "n/a") {
		t.Errorf("CVE-2024-0002 absent from EPSS map must render EPSS cell as n/a\n---body---\n%s", noEPSS.Body)
	}

	noKEV, ok := findIssue(got, "CVE-2024-0003")
	if !ok {
		t.Fatalf("expected issue for CVE-2024-0003, got %v", issueCVEs(got))
	}
	// Absent from the KEV map -> KEV cell is "no"; the distinctive "yes" token
	// must not appear anywhere in the body.
	if strings.Contains(noKEV.Body, "yes") {
		t.Errorf("CVE-2024-0003 absent from KEV must render the KEV cell as no (no \"yes\" token)\n---body---\n%s", noKEV.Body)
	}
}

func TestBuildIssues_BodyHasMarkerAndRequiredSections(t *testing.T) {
	// Same CVE in two images with two different packages: one fixed, one not.
	in := Inputs{
		Reports: []TrivyReport{
			rep(grafanaRef, vuln("CVE-2024-0001", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "CRITICAL",
				"openssl: buffer overflow", "https://avd.aquasec.com/nvd/cve-2024-0001")),
			rep(valkeyRef, vuln("CVE-2024-0001", "libxml2", "2.11.5-r0", "", "CRITICAL",
				"openssl: buffer overflow", "https://avd.aquasec.com/nvd/cve-2024-0001")),
		},
		EPSS:     map[string]EPSSScore{"CVE-2024-0001": {Score: 0.5, Percentile: 0.9}},
		KEV:      map[string]bool{"CVE-2024-0001": true},
		Existing: map[string]bool{},
	}

	iss, ok := findIssue(BuildIssues(in), "CVE-2024-0001")
	if !ok {
		t.Fatalf("expected an issue for CVE-2024-0001")
	}
	body := iss.Body

	mustContain := []string{
		"## CVE-2024-0001 — CRITICAL",        // header
		"<!-- rescan-cve: CVE-2024-0001 -->", // marker
		"CRITICAL",                           // severity
		grafanaRef,                           // full image refs
		valkeyRef,                            //
		"`libcrypto3`",                       // fixed package rendered with backticks
		"→ fixed in 3.1.4-r6",                // fixed package line
		"`libxml2`",                          // unfixed package
		"no fix available",                   // unfixed package line
		"openssl: buffer overflow",           // Details: Title
		"https://avd.aquasec.com/nvd/cve-2024-0001", // Details: URL
		"### Triage",     // triage section
		"exploitability", // checklist item 1
		"triage/vex/",    // checklist item 2 (OpenVEX)
		"triage/LOG.md",  // checklist item 2 (LOG)
		"version-bump",   // checklist item 3
	}
	for _, want := range mustContain {
		if !strings.Contains(body, want) {
			t.Errorf("body missing %q\n---body---\n%s", want, body)
		}
	}
}

func TestBuildIssues_TitleAndLabels(t *testing.T) {
	in := Inputs{
		Reports: []TrivyReport{
			// two-image case (real tags exercise the :tag strip)
			rep(grafanaRef, vuln("CVE-2024-1000", "libcrypto3", "3.1.4-r5", "3.1.4-r6", "CRITICAL", "t", "https://x/1000")),
			rep(valkeyRef, vuln("CVE-2024-1000", "libssl3", "3.1.4-r5", "3.1.4-r6", "CRITICAL", "t", "https://x/1000")),
			// four-image case exercises the cap-at-3 + "+N more"
			rep(alphaRef, vuln("CVE-2024-4444", "p", "1", "2", "CRITICAL", "t", "https://x/4444")),
			rep(bravoRef, vuln("CVE-2024-4444", "p", "1", "2", "CRITICAL", "t", "https://x/4444")),
			rep(charlieRef, vuln("CVE-2024-4444", "p", "1", "2", "CRITICAL", "t", "https://x/4444")),
			rep(deltaRef, vuln("CVE-2024-4444", "p", "1", "2", "CRITICAL", "t", "https://x/4444")),
		},
		EPSS:     map[string]EPSSScore{},
		KEV:      map[string]bool{},
		Existing: map[string]bool{},
	}

	got := BuildIssues(in)

	two, ok := findIssue(got, "CVE-2024-1000")
	if !ok {
		t.Fatalf("expected issue for CVE-2024-1000, got %v", issueCVEs(got))
	}
	if want := "CVE-2024-1000: CRITICAL in grafana, valkey"; two.Title != want {
		t.Errorf("title = %q, want %q", two.Title, want)
	}
	wantLabels := []string{"security", "cve", "severity:critical"}
	if !reflect.DeepEqual(two.Labels, wantLabels) {
		t.Errorf("labels = %v, want %v", two.Labels, wantLabels)
	}

	four, ok := findIssue(got, "CVE-2024-4444")
	if !ok {
		t.Fatalf("expected issue for CVE-2024-4444, got %v", issueCVEs(got))
	}
	if want := "CVE-2024-4444: CRITICAL in alpha, bravo, charlie, +1 more"; four.Title != want {
		t.Errorf("title = %q, want %q", four.Title, want)
	}
	if !reflect.DeepEqual(four.Labels, wantLabels) {
		t.Errorf("labels = %v, want %v", four.Labels, wantLabels)
	}
}

func TestBuildIssues_OrderByCritThenEPSSThenID(t *testing.T) {
	in := Inputs{
		Reports: []TrivyReport{
			rep(grafanaRef,
				vuln("CVE-2024-0100", "p", "1", "2", "CRITICAL", "t", "https://x/100"),
				vuln("CVE-2024-0200", "p", "1", "2", "CRITICAL", "t", "https://x/200"),
				vuln("CVE-2024-0300", "p", "1", "2", "CRITICAL", "t", "https://x/300"),
				vuln("CVE-2024-0400", "p", "1", "2", "HIGH", "t", "https://x/400"),
				vuln("CVE-2024-0500", "p", "1", "2", "HIGH", "t", "https://x/500"),
			),
		},
		EPSS: map[string]EPSSScore{
			"CVE-2024-0100": {Score: 0.10, Percentile: 0.1},
			"CVE-2024-0200": {Score: 0.90, Percentile: 0.9},
			"CVE-2024-0300": {Score: 0.90, Percentile: 0.9}, // ties 0200 -> id asc
			"CVE-2024-0400": {Score: 0.50, Percentile: 0.5},
			"CVE-2024-0500": {Score: 0.50, Percentile: 0.5}, // ties 0400 -> id asc
		},
		KEV:      map[string]bool{},
		Existing: map[string]bool{},
	}

	got := BuildIssues(in)

	// CRITICAL block first (EPSS desc, id asc on ties), even though a HIGH has a
	// higher EPSS (0.50) than a CRITICAL (0.10). Then HIGH block.
	want := []string{
		"CVE-2024-0200", "CVE-2024-0300", "CVE-2024-0100", // criticals
		"CVE-2024-0400", "CVE-2024-0500", // highs
	}
	if !reflect.DeepEqual(issueCVEs(got), want) {
		t.Errorf("issue order = %v, want %v", issueCVEs(got), want)
	}
}

// -----------------------------------------------------------------------------
// Parse* helpers
// -----------------------------------------------------------------------------

func TestParseEPSS(t *testing.T) {
	data := []byte(`{"status":"OK","data":[
		{"cve":"CVE-2024-0001","epss":"0.008450000","percentile":"0.512300000"},
		{"cve":"CVE-2024-0003","epss":"0.923400000","percentile":"0.998700000"}
	]}`)

	got, err := ParseEPSS(data)
	if err != nil {
		t.Fatalf("ParseEPSS error: %v", err)
	}

	s, ok := got["CVE-2024-0001"]
	if !ok {
		t.Fatalf("ParseEPSS missing CVE-2024-0001, got keys %v", keys(got))
	}
	if math.Abs(s.Score-0.00845) > 1e-9 {
		t.Errorf("CVE-2024-0001 Score = %v, want 0.00845", s.Score)
	}
	if math.Abs(s.Percentile-0.5123) > 1e-9 {
		t.Errorf("CVE-2024-0001 Percentile = %v, want 0.5123", s.Percentile)
	}

	s3 := got["CVE-2024-0003"]
	if math.Abs(s3.Score-0.9234) > 1e-9 {
		t.Errorf("CVE-2024-0003 Score = %v, want 0.9234", s3.Score)
	}
}

func keys(m map[string]EPSSScore) []string {
	out := []string{}
	for k := range m {
		out = append(out, k)
	}
	return out
}

func TestParseKEV(t *testing.T) {
	data := []byte(`{"vulnerabilities":[{"cveID":"CVE-2024-0003"},{"cveID":"CVE-2024-1234"}]}`)

	got, err := ParseKEV(data)
	if err != nil {
		t.Fatalf("ParseKEV error: %v", err)
	}
	for _, want := range []string{"CVE-2024-0003", "CVE-2024-1234"} {
		if !got[want] {
			t.Errorf("ParseKEV set missing %s (got %v)", want, got)
		}
	}
	if got["CVE-2024-9999"] {
		t.Errorf("ParseKEV set must not contain CVE-2024-9999")
	}
}

func TestParseExisting(t *testing.T) {
	data := []byte(`["CVE-2024-9999","CVE-2024-0001"]`)

	got, err := ParseExisting(data)
	if err != nil {
		t.Fatalf("ParseExisting error: %v", err)
	}
	for _, want := range []string{"CVE-2024-9999", "CVE-2024-0001"} {
		if !got[want] {
			t.Errorf("ParseExisting set missing %s (got %v)", want, got)
		}
	}
	if got["CVE-2024-0002"] {
		t.Errorf("ParseExisting set must not contain CVE-2024-0002")
	}
}

// -----------------------------------------------------------------------------
// Golden
// -----------------------------------------------------------------------------

func TestBuildIssues_Golden(t *testing.T) {
	grafana := mustParseTrivy(t, "trivy-grafana.json")
	valkey := mustParseTrivy(t, "trivy-valkey.json")

	epss, err := ParseEPSS(mustRead(t, "epss.json"))
	if err != nil {
		t.Fatalf("ParseEPSS: %v", err)
	}
	kev, err := ParseKEV(mustRead(t, "kev.json"))
	if err != nil {
		t.Fatalf("ParseKEV: %v", err)
	}
	existing, err := ParseExisting(mustRead(t, "existing.json"))
	if err != nil {
		t.Fatalf("ParseExisting: %v", err)
	}

	got := BuildIssues(Inputs{
		Reports:  []TrivyReport{grafana, valkey},
		EPSS:     epss,
		KEV:      kev,
		Existing: existing,
	})

	type summary struct {
		CVE      string
		Severity string
		Title    string
		Labels   []string
		Images   []string
	}
	sums := make([]summary, 0, len(got))
	for _, i := range got {
		sums = append(sums, summary{
			CVE:      i.CVE,
			Severity: i.Severity,
			Title:    i.Title,
			Labels:   i.Labels,
			Images:   i.Images,
		})
	}

	want := []summary{
		{
			CVE:      "CVE-2024-0003",
			Severity: "CRITICAL",
			Title:    "CVE-2024-0003: CRITICAL in valkey",
			Labels:   []string{"security", "cve", "severity:critical"},
			Images:   []string{valkeyRef},
		},
		{
			CVE:      "CVE-2024-0001",
			Severity: "CRITICAL",
			Title:    "CVE-2024-0001: CRITICAL in grafana, valkey",
			Labels:   []string{"security", "cve", "severity:critical"},
			Images:   []string{grafanaRef, valkeyRef},
		},
		{
			CVE:      "CVE-2024-0002",
			Severity: "HIGH",
			Title:    "CVE-2024-0002: HIGH in grafana",
			Labels:   []string{"security", "cve", "severity:high"},
			Images:   []string{grafanaRef},
		},
	}

	if !reflect.DeepEqual(sums, want) {
		t.Errorf("golden summary mismatch\n got: %#v\nwant: %#v", sums, want)
	}

	// Body is not golden-matched (too brittle) — only the stable marker is.
	for _, i := range got {
		marker := fmt.Sprintf("<!-- rescan-cve: %s -->", i.CVE)
		if !strings.Contains(i.Body, marker) {
			t.Errorf("issue %s body missing marker %q\n---body---\n%s", i.CVE, marker, i.Body)
		}
	}
}

func mustRead(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return b
}

func mustParseTrivy(t *testing.T, name string) TrivyReport {
	t.Helper()
	r, err := ParseTrivy(mustRead(t, name))
	if err != nil {
		t.Fatalf("ParseTrivy %s: %v", name, err)
	}
	return r
}
