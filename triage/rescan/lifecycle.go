// The evidence-based issue lifecycle over the supported set (task 10.6;
// Req 6.52 to 6.57). Lifecycle decides, from today's attested scan reports,
// the attested SBOMs and the merged triage artifacts, which open cve issues
// close and with which graded label, which closed ones reopen, and which
// open ones wear a stale resolved label. It records evidence, never a
// decision (Req 6.54): every comment names what was examined and what was
// found. Pure data in, data out; the command and the workflow do the
// reading and the gh calls.
package rescan

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// ---- our own issue template, read back ----

type CVEIssue struct {
	Number   int
	ID       string // the hidden marker's id: the durable finding identity
	State    string // open | closed
	Labels   []string
	Images   []string  // what the issue named when filed
	Packages []Package // name, installed version and fixed versions when filed
}

var (
	markerRe  = regexp.MustCompile(`<!--\s*rescan-cve:\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*-->`)
	imagesRe  = regexp.MustCompile(`(?m)^\|\s*Affected images\s*\|\s*(.*?)\s*\|\s*$`)
	packageRe = regexp.MustCompile("(?m)^- `([^`]+)` (\\S*) → (?:fixed in (.+?)|no fix available)\\s*$")
)

// ParseCVEIssue reads an issue the reporter filed: the marker is the finding
// identity, the images row and the package lines are what it recorded at
// filing time (the versions a bump is measured against). An issue without
// the marker is not ours.
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
	return fmt.Sprintf("scanner trivy %s, vulnerability database updated %s", orUnknown(s.Version), orUnknown(s.DBUpdatedAt))
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
	Labels     map[string]string   // evidence grade -> label name (catalogue-policy.yaml); default resolved:<grade>
}
type CloseAction struct {
	Number       int      `json:"number"`
	ID           string   `json:"id"`
	Label        string   `json:"label"`
	RemoveLabels []string `json:"remove_labels"` // stale resolved labels of another grade
	Comment      string   `json:"comment"`
}
type ReopenAction struct {
	Number       int      `json:"number"`
	ID           string   `json:"id"`
	Comment      string   `json:"comment"`
	RemoveLabels []string `json:"remove_labels"`
}
type RelabelAction struct { // an open issue that stays open wearing a resolved label
	Number       int      `json:"number"`
	ID           string   `json:"id"`
	RemoveLabels []string `json:"remove_labels"`
	Reason       string   `json:"reason"`
}
type KeptIssue struct {
	Number int    `json:"number"`
	ID     string `json:"id"`
	Reason string `json:"reason"`
}
type LifecycleActions struct {
	Close   []CloseAction   `json:"close"`
	Reopen  []ReopenAction  `json:"reopen"`
	Relabel []RelabelAction `json:"relabel"`
	Kept    []KeptIssue     `json:"kept"`
}

const grades = "fixed removed not_affected accepted absent"

func (in LifecycleInputs) labelFor(grade string) string {
	if l := in.Labels[grade]; l != "" {
		return l
	}
	return "resolved:" + grade
}

// resolvedLabels are the labels on an issue that this lifecycle owns.
func (in LifecycleInputs) resolvedLabels(labels []string) []string {
	owned := map[string]bool{}
	for _, g := range strings.Fields(grades) {
		owned[in.labelFor(g)] = true
	}
	out := []string{}
	for _, l := range labels {
		if owned[l] || strings.HasPrefix(l, "resolved:") {
			out = append(out, l)
		}
	}
	return out
}

// ---- evidence ----

type coverage struct {
	kind      string // accepted | not_affected | fixed
	source    string // the document or ignorefile the scanner applied
	statement string
}
type sighting struct { // one platform manifest's report on one finding
	repo, index, manifest string
	tags                  []string
	reported              bool
	inAperture            bool
	severity              string
	coverage              []coverage
}
type digestRef struct {
	repo, index string
	tags        []string
	manifests   []string
}

func short(ref string) string {
	if len(ref) > 19 {
		return ref[:19] + "…"
	}
	return ref
}
func refOf(repo, digest string) string { return repo + "@" + short(digest) }
func without(labels []string, keep string) []string {
	out := []string{}
	for _, l := range labels {
		if l != keep {
			out = append(out, l)
		}
	}
	return out
}

// Lifecycle is the decision, as specified: an open issue closes when its
// finding is absent from every supported digest's report (Req 6.52) or
// covered on every one that lists it (Req 6.53), graded by the evidence
// (Req 6.56); a closed issue reopens when its finding is reported again on
// a supported digest (Req 6.57). A supported digest without a complete set
// of reports today blocks every close, because absence cannot be read from
// a scan that did not happen; a reopen needs only the positive evidence. A
// digest scanned without its VEX (the compile failed) is evidence of
// nothing: its reports list covered findings as reported.
func Lifecycle(in LifecycleInputs) LifecycleActions {
	sightings := map[string][]sighting{}
	examined := []digestRef{}
	unscanned := []string{}
	for _, d := range in.Digests {
		complete, missing := d.scanState()
		if d.VEXUnresolved {
			unscanned = append(unscanned, fmt.Sprintf("%s (%s)", refOf(d.Repository, d.Digest), missing[0]))
			continue
		}
		if !complete {
			what := "no report today"
			if len(missing) > 0 {
				ms := make([]string, 0, len(missing))
				for _, m := range missing {
					ms = append(ms, short(m))
				}
				what = "no report today for manifest(s) " + strings.Join(ms, ", ")
			}
			unscanned = append(unscanned, fmt.Sprintf("%s (%s)", refOf(d.Repository, d.Digest), what))
		}
		ref := digestRef{repo: d.Repository, index: d.Digest, tags: d.Tags}
		for _, r := range d.Reports {
			m := manifestOf(r)
			ref.manifests = append(ref.manifests, m)
			seen := map[string]*sighting{}
			eachFinding(r, func(f reportFinding) {
				s := seen[f.ID]
				if s == nil {
					s = &sighting{repo: d.Repository, index: d.Digest, manifest: m, tags: d.Tags}
					seen[f.ID] = s
				}
				rank := sevRank(f.Severity, in.Aperture)
				if f.Reported {
					s.reported = true
					if rank > 0 {
						s.inAperture = true
					}
					if rank > sevRank(s.severity, in.Aperture) || s.severity == "" {
						s.severity = f.Severity
					}
					return
				}
				var kind string
				switch f.Suppressed.Status {
				case "ignored":
					kind = "accepted"
				case "not_affected", "fixed":
					kind = f.Suppressed.Status
				default:
					return
				}
				s.coverage = append(s.coverage, coverage{kind: kind, source: f.Suppressed.Source, statement: f.Suppressed.Statement})
			})
			ids := make([]string, 0, len(seen))
			for id := range seen {
				ids = append(ids, id)
			}
			sort.Strings(ids)
			for _, id := range ids {
				sightings[id] = append(sightings[id], *seen[id])
			}
		}
		if complete {
			examined = append(examined, ref)
		}
	}
	sort.Strings(unscanned)

	scanner := in.Scanner
	if scanner.Version == "" { // the reports carry the scanner's own version block
		for _, d := range in.Digests {
			for _, r := range d.Reports {
				if r.Trivy.Version != "" {
					scanner.Version = r.Trivy.Version
					break
				}
			}
		}
	}

	// Empty lists are lists, never null: the workflow iterates them with jq.
	out := LifecycleActions{Close: []CloseAction{}, Reopen: []ReopenAction{}, Relabel: []RelabelAction{}, Kept: []KeptIssue{}}
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
		var reportedAt, outside []string
		for _, s := range sightings[is.ID] {
			if s.reported && s.inAperture {
				reportedAt = append(reportedAt, fmt.Sprintf("%s (%s)", refOf(s.repo, s.manifest), s.severity))
			} else if s.reported {
				outside = append(outside, fmt.Sprintf("%s (%s, outside the decision aperture)", refOf(s.repo, s.manifest), s.severity))
			}
		}
		keep := func(reason string) {
			out.Kept = append(out.Kept, KeptIssue{is.Number, is.ID, reason})
			if stale := in.resolvedLabels(is.Labels); len(stale) > 0 {
				out.Relabel = append(out.Relabel, RelabelAction{is.Number, is.ID, stale, "open, so no resolved label applies: " + reason})
			}
		}
		switch {
		case len(reportedAt) > 0:
			keep("reported on " + strings.Join(reportedAt, ", "))
			continue
		case len(unscanned) > 0:
			keep("incomplete evidence today: " + strings.Join(unscanned, "; ") + "; absence cannot be read")
			continue
		case len(examined) == 0:
			keep("no supported digest examined today")
			continue
		}
		var covered []sighting
		for _, s := range sightings[is.ID] {
			if len(s.coverage) > 0 {
				covered = append(covered, s)
			}
		}
		var label, comment string
		if len(covered) > 0 {
			label, comment = closeCovered(is, covered, examined, scanner, in)
		} else {
			label, comment = closeAbsent(is, examined, outside, scanner, in)
		}
		out.Close = append(out.Close, CloseAction{is.Number, is.ID, label, without(in.resolvedLabels(is.Labels), label), comment})
	}

	// closed issues: the original (lowest-numbered) closed issue per finding
	// reopens when the finding is reported again, in the aperture
	original := map[string]CVEIssue{}
	for _, is := range in.Issues {
		if is.State != "closed" || openIDs[is.ID] {
			continue
		}
		if cur, ok := original[is.ID]; !ok || is.Number < cur.Number {
			original[is.ID] = is
		}
	}
	for id, is := range original {
		var where []string
		for _, s := range sightings[id] {
			if s.reported && s.inAperture {
				where = append(where, fmt.Sprintf("- %s (%s), manifest %s: %s", refOf(s.repo, s.index), strings.Join(s.tags, ", "), short(s.manifest), s.severity))
			}
		}
		if len(where) == 0 {
			continue
		}
		comment := fmt.Sprintf("Reopened by the rescan (Req 6.57): %s is reported again on a supported digest.\n\n%s\n\n%s.", id, strings.Join(where, "\n"), scanner)
		out.Reopen = append(out.Reopen, ReopenAction{is.Number, id, comment, in.resolvedLabels(is.Labels)})
	}

	sort.Slice(out.Close, func(i, j int) bool { return out.Close[i].Number < out.Close[j].Number })
	sort.Slice(out.Reopen, func(i, j int) bool { return out.Reopen[i].Number < out.Reopen[j].Number })
	sort.Slice(out.Relabel, func(i, j int) bool { return out.Relabel[i].Number < out.Relabel[j].Number })
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
func filedAgainst(is CVEIssue) string {
	if len(is.Images) == 0 {
		return ""
	}
	return "Filed against: " + strings.Join(is.Images, ", ") + ".\n\n"
}

// closeCovered: Req 6.53, graded by the covering artifacts (Req 6.56). The
// weakest grade wins: an exception anywhere is `accepted`, else a
// not_affected statement anywhere, else every cover is a fixed statement.
func closeCovered(is CVEIssue, covered []sighting, examined []digestRef, scanner Scanner, in LifecycleInputs) (string, string) {
	grade := "fixed"
	var lines []string
	coveredDigests := map[string]bool{}
	for _, s := range covered {
		coveredDigests[s.index] = true
		for _, c := range s.coverage {
			switch c.kind {
			case "accepted":
				grade = "accepted"
			case "not_affected":
				if grade != "accepted" {
					grade = "not_affected"
				}
			}
			var line string
			if c.kind == "accepted" {
				line = fmt.Sprintf("- %s: accepted-risk exception, %s", refOf(s.repo, s.manifest), c.source)
			} else {
				line = fmt.Sprintf("- %s: OpenVEX statement %s, applied from %s", refOf(s.repo, s.manifest), c.kind, filepath.Base(c.source))
				if srcs := in.VEXSources[is.ID]; len(srcs) > 0 {
					line += ", source " + strings.Join(srcs, ", ")
				}
			}
			if c.statement != "" {
				line += fmt.Sprintf(": \"%s\"", c.statement)
			}
			lines = append(lines, line)
		}
	}
	var absent []string
	for _, d := range examined {
		if !coveredDigests[d.index] {
			absent = append(absent, fmt.Sprintf("%s (%s)", refOf(d.repo, d.index), strings.Join(d.tags, ", ")))
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Closed by the rescan on evidence, not a decision (Req 6.53, 6.54): every supported digest whose attested scan report lists %s lists it as covered.\n\n", is.ID)
	b.WriteString(filedAgainst(is))
	b.WriteString("Covering artifacts:\n" + strings.Join(lines, "\n") + "\n")
	if len(absent) > 0 {
		b.WriteString("\nAbsent, reported or suppressed, from the other supported digests examined: " + strings.Join(absent, "; ") + ".\n")
	}
	fmt.Fprintf(&b, "\n%s.\nLabel: %s\n", scanner, in.labelFor(grade))
	return in.labelFor(grade), b.String()
}

// closeAbsent: Req 6.52, graded by the attested SBOMs (Req 6.56): `fixed`
// only when every occurrence of every recorded package moved to a fixed
// version, `removed` when the packages left every SBOM, `absent` otherwise,
// and never a claim without every examined manifest's SBOM in hand.
func closeAbsent(is CVEIssue, examined []digestRef, outside []string, scanner Scanner, in LifecycleInputs) (string, string) {
	var manifests []string
	for _, d := range examined {
		manifests = append(manifests, d.manifests...)
	}
	grade, evidence := sbomGrade(is, manifests, in.SBOMs)
	var b strings.Builder
	fmt.Fprintf(&b, "Closed by the rescan on evidence, not a decision (Req 6.52, 6.54): %s appears, reported or suppressed, in no supported digest's attested scan report today.\n\n", is.ID)
	b.WriteString(filedAgainst(is))
	fmt.Fprintf(&b, "Examined, %s:\n%s", scanner, examinedLines(examined))
	if len(outside) > 0 {
		b.WriteString("\nListed below the decision aperture, which holds no issues: " + strings.Join(outside, "; ") + ".\n")
	}
	b.WriteString("\nSBOM evidence, attested CycloneDX read through verification (Req 6.56):\n" + strings.Join(evidence, "\n") + "\n")
	fmt.Fprintf(&b, "\nLabel: %s\n", in.labelFor(grade))
	return in.labelFor(grade), b.String()
}

func sbomGrade(is CVEIssue, manifests []string, sboms map[string][]SBOMComponent) (string, []string) {
	if len(is.Packages) == 0 {
		return "absent", []string{"- the issue records no package, so no version bump can be shown; the finding is absent from every report"}
	}
	var missing []string
	for _, m := range manifests {
		if len(sboms[m]) == 0 { // unread, or a document without components, is no evidence
			missing = append(missing, short(m))
		}
	}
	if len(missing) > 0 {
		return "absent", []string{"- no verified SBOM with components for manifest(s) " + strings.Join(missing, ", ") + ", so no bump is claimed; the finding is absent from every report"}
	}
	keys := make([]string, 0, len(sboms))
	for m := range sboms {
		keys = append(keys, m)
	}
	sort.Strings(keys)
	bumped, removed, same := 0, 0, 0
	var lines []string
	for _, p := range is.Packages {
		if p.Installed == "" {
			same++
			lines = append(lines, fmt.Sprintf("- `%s`: the issue recorded no installed version, so no bump can be shown", p.Name))
			continue
		}
		var now, still []string
		for _, m := range keys {
			for _, c := range sboms[m] {
				if !strings.EqualFold(c.Name, p.Name) {
					continue
				}
				if bumpedTo(p, c.Version) {
					now = append(now, fmt.Sprintf("%s (%s)", c.Version, short(m)))
				} else {
					still = append(still, fmt.Sprintf("%s (%s)", c.Version, short(m)))
				}
			}
		}
		fixedNote := ""
		if p.Fixed != "" {
			fixedNote = ", fixed in " + p.Fixed
		}
		switch {
		case len(now) == 0 && len(still) == 0:
			removed++
			lines = append(lines, fmt.Sprintf("- `%s` recorded %s when filed%s; in no supported manifest's SBOM now", p.Name, p.Installed, fixedNote))
		case len(still) == 0:
			bumped++
			lines = append(lines, fmt.Sprintf("- `%s` recorded %s when filed%s; now %s: every occurrence bumped", p.Name, p.Installed, fixedNote, strings.Join(now, ", ")))
		default:
			same++
			lines = append(lines, fmt.Sprintf("- `%s` recorded %s when filed%s; still %s: not shown as bumped, the scanner stopped reporting it", p.Name, p.Installed, fixedNote, strings.Join(still, ", ")))
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

// bumpedTo says whether a version now in an SBOM shows the recorded package
// bumped: different from what the issue recorded and, when the issue
// recorded fixed versions, at or above the fix on the installed version's
// own release line (the scanner lists one fix per line: 1.25.11, 1.26.4). A
// version that cannot be compared shows nothing.
func bumpedTo(p Package, version string) bool {
	if sameVersion(p.Installed, version) {
		return false
	}
	if strings.TrimSpace(p.Fixed) == "" {
		return true
	}
	fix, ok := fixForLine(p.Installed, strings.Split(p.Fixed, ","))
	if !ok {
		return false
	}
	cmp, ok := compareVersions(version, fix)
	return ok && cmp >= 0
}

// fixForLine picks, among the fixed versions, the one sharing the longest
// numeric prefix with the installed version: the fix for its release line.
func fixForLine(installed string, fixes []string) (string, bool) {
	inst := digitsRe.FindAllString(normVersion(installed), -1)
	best, bestLen := "", -1
	for _, f := range fixes {
		f = strings.TrimSpace(f)
		fd := digitsRe.FindAllString(normVersion(f), -1)
		if len(fd) == 0 {
			continue
		}
		n := 0
		for n < len(inst) && n < len(fd) && inst[n] == fd[n] {
			n++
		}
		if n > bestLen {
			best, bestLen = f, n
		}
	}
	return best, bestLen >= 0
}

// sameVersion compares as the scanner and the SBOM tool spell versions:
// trivy writes Go versions with a v, syft writes the standard library as goN.
func sameVersion(a, b string) bool { return normVersion(a) == normVersion(b) }
func normVersion(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "go")
	return strings.TrimPrefix(s, "v")
}

var digitsRe = regexp.MustCompile(`\d+`)

// compareVersions compares the numeric runs of two versions in order
// (1.26.4 against 1.26.4, 3.5.8-r1 against 3.5.8-r0); versions without a
// number cannot be compared.
func compareVersions(a, b string) (int, bool) {
	na, nb := digitsRe.FindAllString(normVersion(a), -1), digitsRe.FindAllString(normVersion(b), -1)
	if len(na) == 0 || len(nb) == 0 {
		return 0, false
	}
	for i := 0; i < len(na) && i < len(nb); i++ {
		x, _ := strconv.Atoi(na[i])
		y, _ := strconv.Atoi(nb[i])
		if x != y {
			if x < y {
				return -1, true
			}
			return 1, true
		}
	}
	switch {
	case len(na) < len(nb):
		return -1, true
	case len(na) > len(nb):
		return 1, true
	}
	return 0, true
}
