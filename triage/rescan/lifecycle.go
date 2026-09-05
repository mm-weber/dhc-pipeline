// The evidence-based issue lifecycle over the supported set (task 10.6;
// Req 6.52 to 6.57). Lifecycle decides, from today's attested scan reports,
// the attested SBOMs and the merged triage artifacts, which open cve issues
// close and with which graded label, and which closed ones reopen. It
// records evidence, never a decision (Req 6.54): every comment names what was
// examined and what was found. Pure data in, data out; the command and the
// workflow do the reading and the gh calls.
package rescan

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
)

// ---- our own issue template, read back ----

type CVEIssue struct {
	Number   int
	ID       string // the hidden marker's id: the durable finding identity
	State    string // open | closed
	Labels   []string
	Images   []string
	Packages []Package
}

var (
	markerRe  = regexp.MustCompile(`<!--\s*rescan-cve:\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*-->`)
	imagesRe  = regexp.MustCompile(`(?m)^\|\s*Affected images\s*\|\s*(.*?)\s*\|\s*$`)
	packageRe = regexp.MustCompile("(?m)^- `([^`]+)` (\\S+) → (?:fixed in (.+?)|no fix available)\\s*$")
)

// ParseCVEIssue reads an issue the reporter filed: the marker is the finding
// identity, the images row and the package lines are what it recorded at
// filing time (the version a bump is measured against). An issue without the
// marker is not ours.
func ParseCVEIssue(number int, state string, labels []string, body string) (CVEIssue, bool) {
	m := markerRe.FindStringSubmatch(body)
	if m == nil {
		return CVEIssue{}, false
	}
	is := CVEIssue{Number: number, ID: m[1], State: strings.ToLower(state), Labels: labels}
	if im := imagesRe.FindStringSubmatch(body); im != nil {
		for _, ref := range strings.Split(im[1], ",") {
			if ref = strings.TrimSpace(ref); ref != "" {
				is.Images = append(is.Images, ref)
			}
		}
	}
	for _, pm := range packageRe.FindAllStringSubmatch(body, -1) {
		is.Packages = append(is.Packages, Package{Name: pm[1], Installed: pm[2], Fixed: strings.TrimSpace(pm[3])})
	}
	return is, true
}

// ParseIssuesJSON reads `gh issue list --json number,state,body,labels`.
func ParseIssuesJSON(data []byte) ([]CVEIssue, error) {
	var raw []struct {
		Number int    `json:"number"`
		State  string `json:"state"`
		Body   string `json:"body"`
		Labels []struct {
			Name string `json:"name"`
		} `json:"labels"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	out := []CVEIssue{}
	for _, r := range raw {
		labels := make([]string, 0, len(r.Labels))
		for _, l := range r.Labels {
			labels = append(labels, l.Name)
		}
		if is, ok := ParseCVEIssue(r.Number, r.State, labels, r.Body); ok {
			out = append(out, is)
		}
	}
	return out, nil
}

// ---- attested SBOMs and the scanner ----

type SBOMComponent struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	PURL    string `json:"purl"`
}

// ParseCycloneDX accepts the bare CycloneDX document or the in-toto statement
// verify-attestation returns it in.
func ParseCycloneDX(data []byte) ([]SBOMComponent, error) {
	var doc struct {
		Predicate  *struct{ Components []SBOMComponent } `json:"predicate"`
		Components []SBOMComponent                       `json:"components"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, err
	}
	if doc.Predicate != nil {
		return doc.Predicate.Components, nil
	}
	return doc.Components, nil
}

type Scanner struct {
	Version     string
	DBUpdatedAt string
}

// ParseScanner reads `trivy version --format json`: the scanner and the
// vulnerability database the run scanned with (Req 6.55).
func ParseScanner(data []byte) (Scanner, error) {
	var v struct {
		Version string `json:"Version"`
		DB      struct {
			UpdatedAt string `json:"UpdatedAt"`
		} `json:"VulnerabilityDB"`
	}
	if err := json.Unmarshal(data, &v); err != nil {
		return Scanner{}, err
	}
	return Scanner{Version: v.Version, DBUpdatedAt: v.DB.UpdatedAt}, nil
}

func (s Scanner) String() string {
	db := s.DBUpdatedAt
	if db == "" {
		db = "unknown"
	}
	return fmt.Sprintf("scanner trivy %s, vulnerability database updated %s", orUnknown(s.Version), db)
}
func orUnknown(s string) string {
	if s == "" {
		return "unknown"
	}
	return s
}

// ---- inputs and actions ----

type LifecycleInputs struct {
	Aperture   []string
	Issues     []CVEIssue                 // every cve issue, open and closed
	Digests    []SupportedDigest          // the supported set with today's reports
	SBOMs      map[string][]SBOMComponent // platform manifest digest -> its attested CycloneDX components
	Scanner    Scanner
	VEXSources map[string][]string // finding id -> the source files under triage/vex naming it
}
type CloseAction struct {
	Number  int    `json:"number"`
	ID      string `json:"id"`
	Label   string `json:"label"`
	Comment string `json:"comment"`
}
type ReopenAction struct {
	Number       int      `json:"number"`
	ID           string   `json:"id"`
	Comment      string   `json:"comment"`
	RemoveLabels []string `json:"remove_labels"`
}
type KeptIssue struct {
	Number int    `json:"number"`
	ID     string `json:"id"`
	Reason string `json:"reason"`
}
type LifecycleActions struct {
	Close  []CloseAction  `json:"close"`
	Reopen []ReopenAction `json:"reopen"`
	Kept   []KeptIssue    `json:"kept"`
}

// ---- evidence ----

type coverage struct {
	kind      string // accepted | not_affected | fixed
	source    string
	statement string
}
type sighting struct { // one platform manifest's report on one finding
	repo, index, manifest string
	tags                  []string
	reported              bool
	severity              string
	coverage              []coverage
}
type digestRef struct {
	repo, index string
	tags        []string
	manifests   []string
}

func manifestOf(r TrivyReport) string {
	if i := strings.LastIndex(r.ArtifactName, "@"); i >= 0 {
		return r.ArtifactName[i+1:]
	}
	return ""
}

func short(ref string) string {
	if len(ref) > 19 {
		return ref[:19] + "…"
	}
	return ref
}
func refOf(repo, digest string) string { return repo + "@" + short(digest) }

// Lifecycle is the decision, as specified: an open issue closes when its
// finding is absent from every supported digest's report (Req 6.52) or
// covered on every one that lists it (Req 6.53), graded by the evidence
// (Req 6.56); a closed issue reopens when its finding is reported again on a
// supported digest (Req 6.57). A supported digest without a report today
// blocks every close, because absence cannot be read from a scan that did
// not happen; a reopen needs only the positive evidence.
func Lifecycle(in LifecycleInputs) LifecycleActions {
	sightings := map[string][]sighting{}
	examined := []digestRef{}
	unscanned := []string{}
	scannedManifests := []string{}
	for _, d := range in.Digests {
		if len(d.Reports) == 0 {
			unscanned = append(unscanned, refOf(d.Repository, d.Digest))
			continue
		}
		ref := digestRef{repo: d.Repository, index: d.Digest, tags: d.Tags}
		for _, r := range d.Reports {
			m := manifestOf(r)
			ref.manifests = append(ref.manifests, m)
			scannedManifests = append(scannedManifests, m)
			seen := map[string]*sighting{}
			at := func(id string) *sighting {
				s := seen[id]
				if s == nil {
					s = &sighting{repo: d.Repository, index: d.Digest, manifest: m, tags: d.Tags}
					seen[id] = s
				}
				return s
			}
			for _, res := range r.Results {
				for _, v := range res.Vulnerabilities {
					if sevRank(v.Severity, in.Aperture) == 0 || v.VulnerabilityID == "" {
						continue
					}
					s := at(v.VulnerabilityID)
					s.reported = true
					if sevRank(v.Severity, in.Aperture) > sevRank(s.severity, in.Aperture) {
						s.severity = strings.ToUpper(v.Severity)
					}
				}
				for _, mod := range res.ExperimentalModifiedFindings {
					if mod.Type != "" && mod.Type != "vulnerability" {
						continue
					}
					v := mod.Finding
					if sevRank(v.Severity, in.Aperture) == 0 || v.VulnerabilityID == "" {
						continue
					}
					var kind string
					switch mod.Status {
					case "ignored":
						kind = "accepted"
					case "not_affected", "fixed":
						kind = mod.Status
					default:
						continue
					}
					at(v.VulnerabilityID).coverage = append(at(v.VulnerabilityID).coverage, coverage{kind: kind, source: mod.Source, statement: mod.Statement})
				}
			}
			ids := make([]string, 0, len(seen))
			for id := range seen {
				ids = append(ids, id)
			}
			sort.Strings(ids)
			for _, id := range ids {
				sightings[id] = append(sightings[id], *seen[id])
			}
		}
		examined = append(examined, ref)
	}
	sort.Strings(unscanned)

	// Empty lists are lists, never null: the workflow iterates them with jq.
	out := LifecycleActions{Close: []CloseAction{}, Reopen: []ReopenAction{}, Kept: []KeptIssue{}}
	openIDs := map[string]bool{}
	for _, is := range in.Issues {
		if is.State == "open" {
			openIDs[is.ID] = true
		}
	}

	// open issues: close on evidence, or keep with the reason
	for _, is := range in.Issues {
		if is.State != "open" {
			continue
		}
		var reportedAt []string
		for _, s := range sightings[is.ID] {
			if s.reported {
				reportedAt = append(reportedAt, fmt.Sprintf("%s (%s)", refOf(s.repo, s.manifest), s.severity))
			}
		}
		if len(reportedAt) > 0 {
			out.Kept = append(out.Kept, KeptIssue{is.Number, is.ID, "reported on " + strings.Join(reportedAt, ", ")})
			continue
		}
		if len(unscanned) > 0 {
			out.Kept = append(out.Kept, KeptIssue{is.Number, is.ID, "no report today for " + strings.Join(unscanned, ", ") + ", so absence cannot be read"})
			continue
		}
		if len(examined) == 0 {
			out.Kept = append(out.Kept, KeptIssue{is.Number, is.ID, "no supported digest examined today"})
			continue
		}
		var covered []sighting
		for _, s := range sightings[is.ID] {
			if len(s.coverage) > 0 {
				covered = append(covered, s)
			}
		}
		if len(covered) > 0 {
			label, comment := closeCovered(is, covered, examined, in)
			out.Close = append(out.Close, CloseAction{is.Number, is.ID, label, comment})
			continue
		}
		label, comment := closeAbsent(is, examined, scannedManifests, in)
		out.Close = append(out.Close, CloseAction{is.Number, is.ID, label, comment})
	}

	// closed issues: reopen the latest one per finding that is reported again
	latestClosed := map[string]CVEIssue{}
	for _, is := range in.Issues {
		if is.State != "closed" || openIDs[is.ID] {
			continue
		}
		if cur, ok := latestClosed[is.ID]; !ok || is.Number > cur.Number {
			latestClosed[is.ID] = is
		}
	}
	for id, is := range latestClosed {
		var where []string
		for _, s := range sightings[id] {
			if s.reported {
				where = append(where, fmt.Sprintf("- %s (%s), manifest %s: %s", refOf(s.repo, s.index), strings.Join(s.tags, ", "), short(s.manifest), s.severity))
			}
		}
		if len(where) == 0 {
			continue
		}
		var remove []string
		for _, l := range is.Labels {
			if strings.HasPrefix(l, "resolved:") {
				remove = append(remove, l)
			}
		}
		comment := fmt.Sprintf("Reopened by the rescan (Req 6.57): %s is reported again on a supported digest.\n\n%s\n\n%s.", id, strings.Join(where, "\n"), in.Scanner)
		out.Reopen = append(out.Reopen, ReopenAction{is.Number, id, comment, remove})
	}

	sort.Slice(out.Close, func(i, j int) bool { return out.Close[i].Number < out.Close[j].Number })
	sort.Slice(out.Reopen, func(i, j int) bool { return out.Reopen[i].Number < out.Reopen[j].Number })
	sort.Slice(out.Kept, func(i, j int) bool { return out.Kept[i].Number < out.Kept[j].Number })
	return out
}

func examinedLines(examined []digestRef) string {
	var b strings.Builder
	for _, d := range examined {
		ms := make([]string, 0, len(d.manifests))
		for _, m := range d.manifests {
			ms = append(ms, short(m))
		}
		fmt.Fprintf(&b, "- %s (%s): manifests %s\n", refOf(d.repo, d.index), strings.Join(d.tags, ", "), strings.Join(ms, ", "))
	}
	return b.String()
}

// closeCovered: Req 6.53, graded by the covering artifacts (Req 6.56). The
// weakest grade wins: an exception anywhere is `accepted`, else a
// not_affected statement anywhere, else every cover is a fixed statement.
func closeCovered(is CVEIssue, covered []sighting, examined []digestRef, in LifecycleInputs) (string, string) {
	grade := "fixed"
	var lines []string
	coveredRepos := map[string]bool{}
	for _, s := range covered {
		coveredRepos[s.repo] = true
		for _, c := range s.coverage {
			switch c.kind {
			case "accepted":
				grade = "accepted"
			case "not_affected":
				if grade != "accepted" {
					grade = "not_affected"
				}
			}
			artifact := c.source
			what := "accepted-risk exception"
			if c.kind != "accepted" {
				what = "OpenVEX statement " + c.kind
				if srcs := in.VEXSources[is.ID]; len(srcs) > 0 {
					artifact = strings.Join(srcs, ", ")
				}
			}
			line := fmt.Sprintf("- %s: %s, %s", refOf(s.repo, s.manifest), what, artifact)
			if c.statement != "" {
				line += fmt.Sprintf(": \"%s\"", c.statement)
			}
			lines = append(lines, line)
		}
	}
	var absent []string
	for _, d := range examined {
		if !coveredRepos[d.repo] {
			absent = append(absent, fmt.Sprintf("%s (%s)", refOf(d.repo, d.index), strings.Join(d.tags, ", ")))
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Closed by the rescan on evidence, not a decision (Req 6.53, 6.54): every supported digest whose attested scan report lists %s lists it as covered.\n\n", is.ID)
	b.WriteString("Covering artifacts:\n" + strings.Join(lines, "\n") + "\n")
	if len(absent) > 0 {
		b.WriteString("\nAbsent, reported or suppressed, from the other supported digests examined: " + strings.Join(absent, "; ") + ".\n")
	}
	fmt.Fprintf(&b, "\n%s.\nLabel: resolved:%s\n", in.Scanner, grade)
	return "resolved:" + grade, b.String()
}

// closeAbsent: Req 6.52, graded by the attested SBOMs (Req 6.56): `fixed`
// only when every occurrence of every recorded package bumped, `removed`
// when the packages left every SBOM, `absent` otherwise, and never a claim
// without every scanned manifest's SBOM in hand.
func closeAbsent(is CVEIssue, examined []digestRef, scanned []string, in LifecycleInputs) (string, string) {
	grade, evidence := sbomGrade(is, scanned, in.SBOMs)
	var b strings.Builder
	fmt.Fprintf(&b, "Closed by the rescan on evidence, not a decision (Req 6.52, 6.54): %s appears, reported or suppressed, in no supported digest's attested scan report today.\n\n", is.ID)
	fmt.Fprintf(&b, "Examined, %s:\n%s", in.Scanner, examinedLines(examined))
	b.WriteString("\nSBOM evidence, attested CycloneDX read through verification (Req 6.56):\n" + strings.Join(evidence, "\n") + "\n")
	fmt.Fprintf(&b, "\nLabel: resolved:%s\n", grade)
	return "resolved:" + grade, b.String()
}

func sbomGrade(is CVEIssue, scanned []string, sboms map[string][]SBOMComponent) (string, []string) {
	if len(is.Packages) == 0 {
		return "absent", []string{"- the issue records no package, so no version bump can be shown; the finding is absent from every report"}
	}
	var missing []string
	for _, m := range scanned {
		if _, ok := sboms[m]; !ok {
			missing = append(missing, short(m))
		}
	}
	if len(missing) > 0 {
		return "absent", []string{"- no verified SBOM for manifest(s) " + strings.Join(missing, ", ") + ", so no bump is claimed; the finding is absent from every report"}
	}
	manifests := make([]string, 0, len(sboms))
	for m := range sboms {
		manifests = append(manifests, m)
	}
	sort.Strings(manifests)
	bumped, removed, same := 0, 0, 0
	var lines []string
	for _, p := range is.Packages {
		var now, still []string
		for _, m := range manifests {
			for _, c := range sboms[m] {
				if c.Name != p.Name {
					continue
				}
				if sameVersion(p.Installed, c.Version) {
					still = append(still, fmt.Sprintf("%s (%s)", c.Version, short(m)))
				} else {
					now = append(now, fmt.Sprintf("%s (%s)", c.Version, short(m)))
				}
			}
		}
		switch {
		case len(now) == 0 && len(still) == 0:
			removed++
			lines = append(lines, fmt.Sprintf("- `%s` recorded %s when filed; in no supported manifest's SBOM now", p.Name, p.Installed))
		case len(still) == 0:
			bumped++
			lines = append(lines, fmt.Sprintf("- `%s` recorded %s when filed; now %s: every occurrence bumped", p.Name, p.Installed, strings.Join(now, ", ")))
		default:
			same++
			lines = append(lines, fmt.Sprintf("- `%s` recorded %s when filed; still %s: the same version is present, the scanner stopped reporting it", p.Name, p.Installed, strings.Join(still, ", ")))
		}
	}
	switch {
	case same > 0:
		return "absent", lines
	case bumped > 0:
		return "fixed", lines
	default:
		return "removed", lines
	}
}

// sameVersion compares as the scanner and the SBOM tool spell versions:
// trivy writes Go versions with a v, syft writes the standard library as goN.
func sameVersion(a, b string) bool {
	norm := func(s string) string {
		s = strings.TrimSpace(s)
		s = strings.TrimPrefix(s, "go")
		s = strings.TrimPrefix(s, "v")
		return s
	}
	return norm(a) == norm(b)
}
