// Package rescan is a pure "reporter" for the CVE rescan pipeline. It takes
// scan + enrichment data (all plain data, no network or I/O) and decides which
// NEW HIGH/CRITICAL CVEs warrant a GitHub issue, producing the templated issue
// content.
//
// RED phase: the function bodies below are stubs that compile and return zero
// values so the test suite RUNS and FAILS with assertion errors. GREEN fills in
// the real logic against the signatures and types pinned here.
package rescan

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
	return nil
}

// BuildIssues aggregates, drops CVEs already tracked (in.Existing[cve]==true),
// enriches with EPSS + KEV, renders title/body/labels, and returns issues sorted
// CRITICAL-first, then EPSS score descending, then CVE id ascending.
func BuildIssues(in Inputs) []Issue {
	return nil
}

func ParseTrivy(data []byte) (TrivyReport, error) { // one report
	return TrivyReport{}, nil
}

func ParseEPSS(data []byte) (map[string]EPSSScore, error) { // cve -> score (parse EPSS/Percentile strings to float64)
	return nil, nil
}

func ParseKEV(data []byte) (map[string]bool, error) { // cve -> true for every cveID
	return nil, nil
}

func ParseExisting(data []byte) (map[string]bool, error) { // input is a JSON array of CVE strings -> set{cve:true}
	return nil, nil
}
