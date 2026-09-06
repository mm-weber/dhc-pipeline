package rescan

import "strings"

// A reportFinding is one line of one scan report: a reported (uncovered)
// finding, or a suppressed one with the suppression that covered it. Both
// the clocks and the issue lifecycle walk reports this way, so what counts
// as "present" is decided once.
type reportFinding struct {
	ID         string
	Severity   string
	Reported   bool           // false: suppressed
	Suppressed *TrivyModified // the suppression, for a suppressed finding
}

// eachFinding calls fn for every finding a report lists, reported or
// suppressed alike, with severity upper-cased. Modified findings of another
// type (a misconfiguration, a secret) are not findings here.
func eachFinding(r TrivyReport, fn func(f reportFinding)) {
	for _, res := range r.Results {
		for _, v := range res.Vulnerabilities {
			if v.VulnerabilityID == "" {
				continue
			}
			fn(reportFinding{ID: v.VulnerabilityID, Severity: strings.ToUpper(v.Severity), Reported: true})
		}
		for i := range res.ExperimentalModifiedFindings {
			m := &res.ExperimentalModifiedFindings[i]
			if m.Type != "" && m.Type != "vulnerability" || m.Finding.VulnerabilityID == "" {
				continue
			}
			fn(reportFinding{ID: m.Finding.VulnerabilityID, Severity: strings.ToUpper(m.Finding.Severity), Suppressed: m})
		}
	}
}

// manifestOf is the platform manifest a report was taken from: the scan
// addresses <repository>@<manifest digest>.
func manifestOf(r TrivyReport) string {
	if i := strings.LastIndex(r.ArtifactName, "@"); i >= 0 {
		return r.ArtifactName[i+1:]
	}
	return ""
}

// scanState says whether every platform manifest of a supported digest has a
// report today, and names the ones that do not. A digest whose enumeration
// did not list manifests (older callers, tests) counts as scanned when it
// has any report at all.
func (d SupportedDigest) scanState() (complete bool, missing []string) {
	if d.VEXUnresolved {
		return false, []string{"VEX not applied (compile failed), so its reports over-report"}
	}
	if len(d.Manifests) == 0 {
		return len(d.Reports) > 0, nil
	}
	have := map[string]bool{}
	for _, r := range d.Reports {
		have[manifestOf(r)] = true
	}
	for _, m := range d.Manifests {
		if !have[m] {
			missing = append(missing, m)
		}
	}
	return len(missing) == 0, missing
}
