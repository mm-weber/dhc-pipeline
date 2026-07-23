// Package rescan is a pure "reporter" for the CVE rescan pipeline. It takes
// scan + enrichment data (all plain data, no network or I/O) and decides which
// NEW HIGH/CRITICAL CVEs warrant a GitHub issue, producing the templated issue
// content.
//
// RED phase: the function bodies below are stubs that compile and return zero
// values so the test suite RUNS and FAILS with assertion errors. GREEN fills in
// the real logic against the signatures and types pinned here.
package rescan

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// ---- Trivy image-scan JSON (subset we consume) ----
type TrivyReport struct {
	ArtifactName string        `json:"ArtifactName"`
	Results      []TrivyResult `json:"Results"`
}
type TrivyResult struct {
	Target          string      `json:"Target"`
	Vulnerabilities []TrivyVuln `json:"Vulnerabilities"`
}
type TrivyVuln struct {
	VulnerabilityID  string `json:"VulnerabilityID"`
	PkgName          string `json:"PkgName"`
	InstalledVersion string `json:"InstalledVersion"`
	FixedVersion     string `json:"FixedVersion"`
	Severity         string `json:"Severity"`
	Title            string `json:"Title"`
	PrimaryURL       string `json:"PrimaryURL"`
}

// ---- EPSS (FIRST.org) response (subset) ----
type EPSSResponse struct {
	Data []EPSSItem `json:"data"`
}
type EPSSItem struct {
	CVE        string `json:"cve"`
	EPSS       string `json:"epss"`
	Percentile string `json:"percentile"`
}
type EPSSScore struct {
	Score      float64
	Percentile float64
}

// ---- CISA KEV catalog (subset) ----
type KEVCatalog struct {
	Vulnerabilities []KEVItem `json:"vulnerabilities"`
}
type KEVItem struct {
	CveID string `json:"cveID"`
}

// ---- aggregated finding ----
type Package struct {
	Name      string
	Installed string
	Fixed     string
}
type Finding struct {
	CVE      string
	Severity string    // "CRITICAL" or "HIGH" (max across images)
	Images   []string  // sorted, unique ArtifactNames where this CVE appears
	Packages []Package // sorted by Name, unique
	Title    string
	URL      string
}

// ---- output ----
type Issue struct {
	CVE      string   `json:"cve"`
	Severity string   `json:"severity"`
	Images   []string `json:"images"`
	Title    string   `json:"title"`
	Body     string   `json:"body"`
	Labels   []string `json:"labels"`
}

// ---- inputs to BuildIssues (all data, no I/O) ----
type Inputs struct {
	Reports  []TrivyReport
	EPSS     map[string]EPSSScore
	KEV      map[string]bool
	Existing map[string]bool
}

// Aggregate collapses all HIGH/CRITICAL vulns across reports into one Finding
// per CVE. Severity = max across images (CRITICAL > HIGH). Images and Packages
// are de-duplicated and sorted (Images ascending; Packages by Name). Non-
// HIGH/CRITICAL severities are ignored. Result sorted: CRITICAL before HIGH,
// then CVE id ascending.
func Aggregate(reports []TrivyReport) []Finding {
	type agg struct {
		rank     int
		images   map[string]bool
		pkgOrder []string
		pkgs     map[string]Package
		title    string
		url      string
	}
	byCVE := map[string]*agg{}
	for _, report := range reports {
		for _, result := range report.Results {
			for _, v := range result.Vulnerabilities {
				rank := sevRank(v.Severity)
				if rank == 0 {
					continue // ignore anything that is not HIGH/CRITICAL
				}
				a := byCVE[v.VulnerabilityID]
				if a == nil {
					a = &agg{images: map[string]bool{}, pkgs: map[string]Package{}}
					byCVE[v.VulnerabilityID] = a
				}
				if rank > a.rank {
					a.rank = rank
				}
				a.images[report.ArtifactName] = true
				if _, seen := a.pkgs[v.PkgName]; !seen {
					a.pkgOrder = append(a.pkgOrder, v.PkgName)
					a.pkgs[v.PkgName] = Package{
						Name:      v.PkgName,
						Installed: v.InstalledVersion,
						Fixed:     v.FixedVersion,
					}
				}
				if a.title == "" {
					a.title = v.Title
				}
				if a.url == "" {
					a.url = v.PrimaryURL
				}
			}
		}
	}

	findings := make([]Finding, 0, len(byCVE))
	for cve, a := range byCVE {
		images := make([]string, 0, len(a.images))
		for img := range a.images {
			images = append(images, img)
		}
		sort.Strings(images)

		pkgs := make([]Package, 0, len(a.pkgs))
		for _, name := range a.pkgOrder {
			pkgs = append(pkgs, a.pkgs[name])
		}
		sort.Slice(pkgs, func(i, j int) bool { return pkgs[i].Name < pkgs[j].Name })

		findings = append(findings, Finding{
			CVE:      cve,
			Severity: canonicalSev(a.rank),
			Images:   images,
			Packages: pkgs,
			Title:    a.title,
			URL:      a.url,
		})
	}

	sort.Slice(findings, func(i, j int) bool {
		ri, rj := sevRank(findings[i].Severity), sevRank(findings[j].Severity)
		if ri != rj {
			return ri > rj // CRITICAL before HIGH
		}
		return findings[i].CVE < findings[j].CVE
	})
	return findings
}

// sevRank ranks a Trivy severity: CRITICAL > HIGH > everything-else (0).
func sevRank(s string) int {
	switch strings.ToUpper(s) {
	case "CRITICAL":
		return 2
	case "HIGH":
		return 1
	default:
		return 0
	}
}

// canonicalSev turns a rank back into the canonical severity string.
func canonicalSev(rank int) string {
	if rank == 2 {
		return "CRITICAL"
	}
	return "HIGH"
}

// BuildIssues aggregates, drops CVEs already tracked (in.Existing[cve]==true),
// enriches with EPSS + KEV, renders title/body/labels, and returns issues sorted
// CRITICAL-first, then EPSS score descending, then CVE id ascending.
func BuildIssues(in Inputs) []Issue {
	type enriched struct {
		f       Finding
		epss    EPSSScore
		hasEPSS bool
		kev     bool
	}

	var items []enriched
	for _, f := range Aggregate(in.Reports) {
		if in.Existing[f.CVE] {
			continue // already-tracked CVE: no new issue
		}
		s, ok := in.EPSS[f.CVE]
		items = append(items, enriched{
			f:       f,
			epss:    s,
			hasEPSS: ok,
			kev:     in.KEV[f.CVE],
		})
	}

	sort.Slice(items, func(i, j int) bool {
		ri, rj := sevRank(items[i].f.Severity), sevRank(items[j].f.Severity)
		if ri != rj {
			return ri > rj // CRITICAL block first
		}
		if items[i].epss.Score != items[j].epss.Score {
			return items[i].epss.Score > items[j].epss.Score // EPSS descending
		}
		return items[i].f.CVE < items[j].f.CVE // then CVE id ascending
	})

	issues := make([]Issue, 0, len(items))
	for _, it := range items {
		issues = append(issues, renderIssue(it.f, it.epss, it.hasEPSS, it.kev))
	}
	return issues
}

// renderIssue turns an enriched Finding into the templated GitHub Issue.
func renderIssue(f Finding, epss EPSSScore, hasEPSS, kev bool) Issue {
	names := shortNames(f.Images)

	epssCell := "n/a"
	if hasEPSS {
		epssCell = fmt.Sprintf("%.4f (%.1f pct)", epss.Score, epss.Percentile*100)
	}
	kevCell := "no"
	if kev {
		kevCell = "yes"
	}

	var b strings.Builder
	fmt.Fprintf(&b, "## %s — %s\n\n", f.CVE, f.Severity)
	fmt.Fprintf(&b, "<!-- rescan-cve: %s -->\n\n", f.CVE)

	fmt.Fprintf(&b, "| Field | Value |\n")
	fmt.Fprintf(&b, "|---|---|\n")
	fmt.Fprintf(&b, "| Severity | %s |\n", f.Severity)
	fmt.Fprintf(&b, "| EPSS | %s |\n", epssCell)
	fmt.Fprintf(&b, "| CISA KEV | %s |\n", kevCell)
	fmt.Fprintf(&b, "| Affected images | %s |\n\n", strings.Join(f.Images, ", "))

	fmt.Fprintf(&b, "### Package(s)\n\n")
	for _, p := range f.Packages {
		if p.Fixed == "" {
			fmt.Fprintf(&b, "- `%s` %s → no fix available\n", p.Name, p.Installed)
		} else {
			fmt.Fprintf(&b, "- `%s` %s → fixed in %s\n", p.Name, p.Installed, p.Fixed)
		}
	}
	b.WriteString("\n")

	fmt.Fprintf(&b, "### Details\n\n")
	if f.Title != "" {
		fmt.Fprintf(&b, "%s\n\n", f.Title)
	}
	if f.URL != "" {
		fmt.Fprintf(&b, "%s\n\n", f.URL)
	}

	fmt.Fprintf(&b, "### Triage\n\n")
	b.WriteString("- [ ] Assess exploitability in our build context.\n")
	b.WriteString("- [ ] If not-affected, publish an OpenVEX statement under `triage/vex/` (task 7.3) and record it in `triage/LOG.md`.\n")
	b.WriteString("- [ ] If a fix is warranted, open a version-bump / rebuild PR.\n")

	return Issue{
		CVE:      f.CVE,
		Severity: f.Severity,
		Images:   f.Images,
		Title:    fmt.Sprintf("%s: %s in %s", f.CVE, f.Severity, titleNames(names)),
		Body:     b.String(),
		Labels:   []string{"security", "cve", "severity:" + strings.ToLower(f.Severity)},
	}
}

// shortName reduces a full image ref to its bare name: the last path segment
// with any :tag stripped (e.g. ghcr.io/mm-weber/dhc/grafana:0.1.0 -> grafana).
func shortName(ref string) string {
	name := ref
	if i := strings.LastIndex(name, "/"); i >= 0 {
		name = name[i+1:]
	}
	if i := strings.Index(name, ":"); i >= 0 {
		name = name[:i]
	}
	return name
}

// shortNames maps refs to unique short names, preserving input order.
func shortNames(refs []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(refs))
	for _, ref := range refs {
		n := shortName(ref)
		if !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}
	return out
}

// titleNames joins names for the issue title, capping at 3 with a "+N more".
func titleNames(names []string) string {
	if len(names) <= 3 {
		return strings.Join(names, ", ")
	}
	return strings.Join(names[:3], ", ") + fmt.Sprintf(", +%d more", len(names)-3)
}

func ParseTrivy(data []byte) (TrivyReport, error) { // one report
	var r TrivyReport
	if err := json.Unmarshal(data, &r); err != nil {
		return TrivyReport{}, err
	}
	return r, nil
}

func ParseEPSS(data []byte) (map[string]EPSSScore, error) { // cve -> score (parse EPSS/Percentile strings to float64)
	var resp EPSSResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, err
	}
	out := make(map[string]EPSSScore, len(resp.Data))
	for _, item := range resp.Data {
		score, err := strconv.ParseFloat(item.EPSS, 64)
		if err != nil {
			continue // skip rows with a malformed/empty epss value
		}
		pct, err := strconv.ParseFloat(item.Percentile, 64)
		if err != nil {
			continue
		}
		out[item.CVE] = EPSSScore{Score: score, Percentile: pct}
	}
	return out, nil
}

func ParseKEV(data []byte) (map[string]bool, error) { // cve -> true for every cveID
	var cat KEVCatalog
	if err := json.Unmarshal(data, &cat); err != nil {
		return nil, err
	}
	out := make(map[string]bool, len(cat.Vulnerabilities))
	for _, v := range cat.Vulnerabilities {
		out[v.CveID] = true
	}
	return out, nil
}

func ParseExisting(data []byte) (map[string]bool, error) { // input is a JSON array of CVE strings -> set{cve:true}
	var cves []string
	if err := json.Unmarshal(data, &cves); err != nil {
		return nil, err
	}
	out := make(map[string]bool, len(cves))
	for _, cve := range cves {
		out[cve] = true
	}
	return out, nil
}
