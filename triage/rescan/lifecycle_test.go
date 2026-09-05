package rescan

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

// ---- builders for the lifecycle tests ----

const (
	cmRepo     = "ghcr.io/mm-weber/dhc/cert-manager-controller"
	cmIdx      = "sha256:e613128f45259adc0e192367fce5a76c2a39a704b33fe745332f21c6e6775707"
	cmAmd      = "sha256:42a9c93208a95fab3c78dbecf68b4f4a505da1ef05fc4deb2d0aaaaaaaaaaaaa"
	grafanaAmd = "sha256:cc46dc5b6979328a9cadc135f3877d1b1ee15b5eb1d7f085557853329d898170"
	valkeyAmd  = "sha256:7df46601ea372c1f16f65821915dabfacbab547fc759794e5b700828e5ee6524"
)

func issueBody(id string, images []string, pkgs ...string) string {
	var b strings.Builder
	b.WriteString("## " + id + " — HIGH\n\n<!-- rescan-cve: " + id + " -->\n\n| Field | Value |\n|---|---|\n")
	b.WriteString("| Affected images | " + strings.Join(images, ", ") + " |\n\n### Package(s)\n\n")
	for _, p := range pkgs {
		b.WriteString("- " + p + "\n")
	}
	b.WriteString("\n### Details\n")
	return b.String()
}

// report builds one platform manifest's report: reported (uncovered) findings,
// and suppressed ones as (id, status, source, statement) quadruples.
func manifestReport(repo, manifest string, reported []TrivyVuln, suppressed ...[4]string) TrivyReport {
	mods := []TrivyModified{}
	for _, s := range suppressed {
		mods = append(mods, TrivyModified{Type: "vulnerability", Status: s[1], Source: s[2], Statement: s[3],
			Finding: TrivyVuln{VulnerabilityID: s[0], PkgName: "stdlib", InstalledVersion: "v1.26.4", Severity: "HIGH"}})
	}
	return TrivyReport{CreatedAt: "2026-09-05T06:20:00Z", ArtifactName: repo + "@" + manifest, Trivy: TrivyVersion{Version: "0.72.0"},
		Results: []TrivyResult{{Target: "bin", Vulnerabilities: reported, ExperimentalModifiedFindings: mods}}}
}
func exception(id string) [4]string {
	return [4]string{id, "ignored", "triage/accepted-risk/grafana.yaml", "transfer: waiting on a grafana release that bundles grafana-zipkin-datasource v12.4.7+"}
}
func vexed(id, status string) [4]string {
	return [4]string{id, status, "rescan-out/vex/grafana__837727c/grafana.openvex.json", "Commit ancestry against the pinned source"}
}
func comp(name, version string) SBOMComponent {
	return SBOMComponent{Name: name, Version: version, PURL: "pkg:golang/" + name + "@" + version}
}

func baseLifecycle() LifecycleInputs {
	grafana := SupportedDigest{Repository: grafanaRepo, Digest: grafanaIdx, Tags: []string{"13-alpine3.23", "13.1.5-alpine3.23"},
		Reports: []TrivyReport{manifestReport(grafanaRepo, grafanaAmd, nil)}}
	cm := SupportedDigest{Repository: cmRepo, Digest: cmIdx, Tags: []string{"1.21.1-alpine3.23"},
		Reports: []TrivyReport{manifestReport(cmRepo, cmAmd, nil)}}
	return LifecycleInputs{
		Aperture: []string{"CRITICAL", "HIGH"},
		Digests:  []SupportedDigest{grafana, cm},
		SBOMs: map[string][]SBOMComponent{
			grafanaAmd: {comp("stdlib", "go1.26.4"), comp("google.golang.org/grpc", "v1.82.1"), comp("google.golang.org/grpc", "v1.83.1")},
			cmAmd:      {comp("stdlib", "go1.27.0"), comp("golang.org/x/crypto", "v0.54.0")},
		},
		Scanner:    Scanner{Version: "0.72.0", DBUpdatedAt: "2026-09-04T13:08:55Z"},
		VEXSources: map[string][]string{"CVE-2026-21728": {"triage/vex/CVE-2026-21728.openvex.json"}},
	}
}

func closeFor(t *testing.T, a LifecycleActions, number int) CloseAction {
	t.Helper()
	for _, c := range a.Close {
		if c.Number == number {
			return c
		}
	}
	t.Fatalf("no close for #%d in %+v (kept: %+v)", number, a.Close, a.Kept)
	return CloseAction{}
}

// -----------------------------------------------------------------------------
// the issue template is our own, so it is read back exactly
// -----------------------------------------------------------------------------

func TestParseCVEIssue(t *testing.T) {
	body := issueBody("CVE-2026-27145", []string{"ghcr.io/mm-weber/dhc/grafana:13-alpine3.23"},
		"`stdlib` v1.26.3 → fixed in 1.25.11, 1.26.4", "`libssl3` 3.5.7-r1 → no fix available")
	is, ok := ParseCVEIssue(22, "OPEN", []string{"cve", "security"}, body)
	if !ok || is.Number != 22 || is.ID != "CVE-2026-27145" || is.State != "open" {
		t.Fatalf("parse: %v %+v", ok, is)
	}
	want := []Package{{Name: "stdlib", Installed: "v1.26.3", Fixed: "1.25.11, 1.26.4"}, {Name: "libssl3", Installed: "3.5.7-r1"}}
	if !reflect.DeepEqual(is.Packages, want) || !reflect.DeepEqual(is.Images, []string{"ghcr.io/mm-weber/dhc/grafana:13-alpine3.23"}) {
		t.Errorf("packages/images: %+v", is)
	}
	if _, ok := ParseCVEIssue(1, "OPEN", nil, "no marker here"); ok {
		t.Errorf("an issue without the marker is not ours")
	}
}

// -----------------------------------------------------------------------------
// Req 6.52, 6.56: absent everywhere, graded by the attested SBOMs
// -----------------------------------------------------------------------------

func TestLifecycle_AbsentEverywhere_FixedWhenThePackageBumped(t *testing.T) {
	in := baseLifecycle()
	in.Issues = []CVEIssue{{Number: 22, ID: "CVE-2026-27145", State: "open", Images: []string{grafanaRepo + ":13-alpine3.23"},
		Packages: []Package{{Name: "stdlib", Installed: "v1.26.3", Fixed: "1.26.4"}}}}
	a := Lifecycle(in)
	c := closeFor(t, a, 22)
	if c.Label != "resolved:fixed" {
		t.Errorf("stdlib v1.26.3 recorded, go1.26.4 and go1.27.0 in every supported SBOM carrying it: fixed; got %+v", c)
	}
	for _, want := range []string{"Req 6.52", "trivy 0.72.0", "2026-09-04T13:08:55Z", grafanaIdx[:19], cmIdx[:19], "`stdlib`", "v1.26.3", "go1.26.4", "resolved:fixed"} {
		if !strings.Contains(c.Comment, want) {
			t.Errorf("comment lacks %q:\n%s", want, c.Comment)
		}
	}
	if strings.Contains(strings.ToLower(c.Comment), "decid") && !strings.Contains(c.Comment, "not a decision") {
		t.Errorf("the comment must not read as a triage decision (Req 6.54):\n%s", c.Comment)
	}
}

func TestLifecycle_AbsentEverywhere_RemovedAndAbsentGrades(t *testing.T) {
	in := baseLifecycle()
	in.Issues = []CVEIssue{
		{Number: 30, ID: "GHSA-r277-6w6q-xmqw", State: "open", Packages: []Package{{Name: "github.com/gone/pkg", Installed: "v1.0.0"}}},
		{Number: 31, ID: "CVE-2026-00099", State: "open", Packages: []Package{{Name: "google.golang.org/grpc", Installed: "v1.82.1"}}},
		{Number: 32, ID: "CVE-2026-00098", State: "open"},
	}
	a := Lifecycle(in)
	if c := closeFor(t, a, 30); c.Label != "resolved:removed" {
		t.Errorf("the package left every supported SBOM: removed; got %+v", c)
	}
	c := closeFor(t, a, 31)
	if c.Label != "resolved:absent" || !strings.Contains(c.Comment, "v1.82.1") {
		t.Errorf("grpc v1.82.1 is still in a supported SBOM, only the scanner stopped reporting: absent, naming the version; got %+v", c)
	}
	if c := closeFor(t, a, 32); c.Label != "resolved:absent" {
		t.Errorf("no package recorded on the issue: nothing to prove a bump with, so absent; got %+v", c)
	}
}

func TestLifecycle_NoClaimWithoutCompleteEvidence(t *testing.T) {
	in := baseLifecycle()
	delete(in.SBOMs, cmAmd) // one scanned manifest without a verified SBOM
	in.Issues = []CVEIssue{{Number: 22, ID: "CVE-2026-27145", State: "open", Packages: []Package{{Name: "stdlib", Installed: "v1.26.3"}}}}
	if c := closeFor(t, Lifecycle(in), 22); c.Label != "resolved:absent" || !strings.Contains(c.Comment, cmAmd[:19]) {
		t.Errorf("a bump is proven only when every scanned manifest's SBOM was read: absent, naming the missing one; got %+v", c)
	}

	in = baseLifecycle()
	in.Digests[1].Reports = nil // a supported digest not scanned today
	in.Issues = []CVEIssue{{Number: 22, ID: "CVE-2026-27145", State: "open"}}
	a := Lifecycle(in)
	if len(a.Close) != 0 || len(a.Kept) != 1 || !strings.Contains(a.Kept[0].Reason, cmIdx[:19]) {
		t.Errorf("a supported digest without a report today blocks every close, by name; got %+v", a)
	}
}

// -----------------------------------------------------------------------------
// Req 6.53, 6.56: covered wherever listed, graded by the covering artifact
// -----------------------------------------------------------------------------

func TestLifecycle_CoveredWhereverListed(t *testing.T) {
	in := baseLifecycle()
	in.Digests[0].Reports = []TrivyReport{manifestReport(grafanaRepo, grafanaAmd, nil,
		exception("CVE-2026-39822"), vexed("CVE-2026-21728", "fixed"), vexed("CVE-2026-42151", "not_affected"), exception("CVE-2026-00077"), vexed("CVE-2026-00077", "not_affected"))}
	in.Issues = []CVEIssue{
		{Number: 26, ID: "CVE-2026-39822", State: "open", Images: []string{grafanaRepo + ":13-alpine3.23", cmRepo + ":1.21.0-alpine3.23"}, Packages: []Package{{Name: "stdlib", Installed: "v1.26.3"}}},
		{Number: 23, ID: "CVE-2026-21728", State: "open"},
		{Number: 25, ID: "CVE-2026-42151", State: "open"},
		{Number: 77, ID: "CVE-2026-00077", State: "open"},
	}
	a := Lifecycle(in)
	c := closeFor(t, a, 26)
	if c.Label != "resolved:accepted" {
		t.Errorf("an exception is the covering artifact: accepted; got %+v", c)
	}
	for _, want := range []string{"Req 6.53", "triage/accepted-risk/grafana.yaml", "transfer: waiting on a grafana release", grafanaAmd[:19], "cert-manager-controller"} {
		if !strings.Contains(c.Comment, want) {
			t.Errorf("comment lacks %q:\n%s", want, c.Comment)
		}
	}
	c = closeFor(t, a, 23)
	if c.Label != "resolved:fixed" || !strings.Contains(c.Comment, "triage/vex/CVE-2026-21728.openvex.json") {
		t.Errorf("a fixed statement covers it, the source file named; got %+v", c)
	}
	if c := closeFor(t, a, 25); c.Label != "resolved:not_affected" {
		t.Errorf("a not_affected statement covers it; got %+v", c)
	}
	if c := closeFor(t, a, 77); c.Label != "resolved:accepted" {
		t.Errorf("exception beside a statement: the weakest grade wins; got %+v", c)
	}
}

func TestLifecycle_ReportedAnywhereStaysOpen(t *testing.T) {
	in := baseLifecycle()
	in.Digests[0].Reports = []TrivyReport{manifestReport(grafanaRepo, grafanaAmd, []TrivyVuln{high("CVE-2026-39822")}, exception("CVE-2026-39822"))}
	in.Issues = []CVEIssue{{Number: 26, ID: "CVE-2026-39822", State: "open"}}
	a := Lifecycle(in)
	if len(a.Close) != 0 || len(a.Kept) != 1 || !strings.Contains(a.Kept[0].Reason, grafanaAmd[:19]) {
		t.Errorf("reported on one binary and covered on another is reported: open, naming where; got %+v", a)
	}
}

// -----------------------------------------------------------------------------
// Req 6.57: a returning finding reopens its issue, never a duplicate
// -----------------------------------------------------------------------------

func TestLifecycle_Reopen(t *testing.T) {
	in := baseLifecycle()
	in.Digests[1].Reports = []TrivyReport{manifestReport(cmRepo, cmAmd, []TrivyVuln{high("CVE-2026-56852")})}
	in.Digests[0].Reports = []TrivyReport{manifestReport(grafanaRepo, grafanaAmd, nil, exception("CVE-2026-33818"))}
	in.Issues = []CVEIssue{
		{Number: 39, ID: "CVE-2026-56852", State: "closed", Labels: []string{"cve", "resolved:fixed"}},
		{Number: 40, ID: "CVE-2026-56852", State: "closed", Labels: []string{"cve", "resolved:absent"}},
		{Number: 86, ID: "CVE-2026-33818", State: "closed", Labels: []string{"cve", "resolved:accepted"}},
	}
	a := Lifecycle(in)
	if len(a.Reopen) != 1 || a.Reopen[0].Number != 40 || !reflect.DeepEqual(a.Reopen[0].RemoveLabels, []string{"resolved:absent"}) {
		t.Fatalf("the latest closed issue for the finding reopens, its resolved label removed; got %+v", a.Reopen)
	}
	for _, want := range []string{"Req 6.57", cmIdx[:19], cmAmd[:19], "HIGH", "trivy 0.72.0"} {
		if !strings.Contains(a.Reopen[0].Comment, want) {
			t.Errorf("reopen comment lacks %q:\n%s", want, a.Reopen[0].Comment)
		}
	}
	// suppressed is not reported: #86 stays closed; and an open twin means no reopen
	in.Issues = append(in.Issues, CVEIssue{Number: 41, ID: "CVE-2026-56852", State: "open"})
	if a := Lifecycle(in); len(a.Reopen) != 0 {
		t.Errorf("an open issue already tracks the finding: no reopen; got %+v", a.Reopen)
	}
}

func TestLifecycle_ReopenNeedsNoCompleteScan(t *testing.T) {
	in := baseLifecycle()
	in.Digests[0].Reports = nil // grafana not scanned today
	in.Digests[1].Reports = []TrivyReport{manifestReport(cmRepo, cmAmd, []TrivyVuln{high("CVE-2026-56852")})}
	in.Issues = []CVEIssue{{Number: 39, ID: "CVE-2026-56852", State: "closed", Labels: []string{"resolved:fixed"}}}
	if a := Lifecycle(in); len(a.Reopen) != 1 {
		t.Errorf("positive evidence on one digest reopens, whatever the others' scans did; got %+v", a)
	}
}

func TestLifecycle_OrderAndVersions(t *testing.T) {
	in := baseLifecycle()
	in.Issues = []CVEIssue{
		{Number: 50, ID: "CVE-2026-00050", State: "open", Packages: []Package{{Name: "stdlib", Installed: "v1.26.3"}}},
		{Number: 49, ID: "CVE-2026-00049", State: "open", Packages: []Package{{Name: "libssl3", Installed: "3.5.7-r1"}}},
	}
	in.SBOMs[valkeyAmd] = []SBOMComponent{{Name: "libssl3", Version: "3.5.7-r1", PURL: "pkg:apk/alpine/libssl3@3.5.7-r1"}}
	in.Digests = append(in.Digests, SupportedDigest{Repository: valkeyRepo, Digest: valkeyIdx, Reports: []TrivyReport{manifestReport(valkeyRepo, valkeyAmd, nil)}})
	a := Lifecycle(in)
	if len(a.Close) != 2 || a.Close[0].Number != 49 || a.Close[1].Number != 50 {
		t.Fatalf("closes sorted by issue number; got %+v", a.Close)
	}
	if a.Close[0].Label != "resolved:absent" || a.Close[1].Label != "resolved:fixed" {
		t.Errorf("same apk version present: absent; go1.26.4 against v1.26.3: fixed; got %+v", a.Close)
	}
	if !sameVersion("v1.26.3", "go1.26.3") || sameVersion("v1.26.3", "go1.26.4") || !sameVersion("3.5.7-r1", "3.5.7-r1") {
		t.Errorf("versions compare without the go/v prefixes")
	}
}

// -----------------------------------------------------------------------------
// parsers for the I/O the command does
// -----------------------------------------------------------------------------

func TestParseCycloneDX(t *testing.T) {
	predicate := `{"bomFormat":"CycloneDX","components":[{"name":"stdlib","version":"go1.26.4","purl":"pkg:golang/stdlib@1.26.4","type":"library"}]}`
	cs, err := ParseCycloneDX([]byte(predicate))
	if err != nil || len(cs) != 1 || cs[0].Name != "stdlib" || cs[0].Version != "go1.26.4" {
		t.Errorf("predicate form: %v %+v", err, cs)
	}
	statement := `{"_type":"https://in-toto.io/Statement/v0.1","predicateType":"https://cyclonedx.org/bom","predicate":` + predicate + `}`
	if cs, err := ParseCycloneDX([]byte(statement)); err != nil || len(cs) != 1 {
		t.Errorf("in-toto statement form: %v %+v", err, cs)
	}
}

func TestParseScanner(t *testing.T) {
	s, err := ParseScanner([]byte(`{"Version":"0.72.0","VulnerabilityDB":{"Version":2,"UpdatedAt":"2026-09-04T13:08:55.575059601Z"}}`))
	if err != nil || s.Version != "0.72.0" || s.DBUpdatedAt != "2026-09-04T13:08:55.575059601Z" {
		t.Errorf("trivy version --format json: %v %+v", err, s)
	}
}

func TestParseIssuesJSON(t *testing.T) {
	data := `[{"number":22,"state":"OPEN","labels":[{"name":"cve"}],"body":"<!-- rescan-cve: CVE-2026-27145 -->\n| Affected images | a |\n- ` + "`stdlib`" + ` v1.26.3 → fixed in 1.26.4\n"},{"number":5,"state":"OPEN","labels":[],"body":"dashboard"}]`
	issues, err := ParseIssuesJSON([]byte(data))
	if err != nil || len(issues) != 1 || issues[0].ID != "CVE-2026-27145" || issues[0].Labels[0] != "cve" || issues[0].Packages[0].Installed != "v1.26.3" {
		t.Errorf("gh issue list --json number,state,body,labels: %v %+v", err, issues)
	}
}

func TestLifecycle_EmptyListsAreLists(t *testing.T) {
	data, err := json.Marshal(Lifecycle(baseLifecycle()))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"close":[]`, `"reopen":[]`, `"kept":[]`} {
		if !strings.Contains(string(data), want) {
			t.Errorf("the workflow iterates these with jq, so an empty list must be [] not null; got %s", data)
		}
	}
}
