// The clocks and the status issue (task 10.4; Req 6.46, 6.47). BuildStatus
// reads, for every finding within the decision aperture on every supported
// digest, first seen and decided from the attested OpenVEX statements, and
// fixed as the first day the finding was absent, reported and suppressed
// alike, from every supported digest of its repository, carried forward
// from the previously published status data. It is pure data in, data out;
// the command and the workflow do the reading and the publishing.
package rescan

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"
)

// ---- OpenVEX (subset the compiler writes) ----
type VEXDocument struct {
	ID         string         `json:"@id"`
	Timestamp  string         `json:"timestamp,omitempty"`
	Statements []VEXStatement `json:"statements"`
}
type VEXStatement struct {
	Vulnerability            VEXVulnerability `json:"vulnerability"`
	Products                 []VEXProduct     `json:"products,omitempty"`
	Status                   string           `json:"status"`
	Timestamp                string           `json:"timestamp"`
	LastUpdated              string           `json:"last_updated,omitempty"`
	ActionStatementTimestamp string           `json:"action_statement_timestamp,omitempty"`
	// The decision in the statement's own words (task 15.9): what the
	// published status carries beside the clock.
	Justification   string `json:"justification,omitempty"`
	ImpactStatement string `json:"impact_statement,omitempty"`
	ActionStatement string `json:"action_statement,omitempty"`
	StatusNotes     string `json:"status_notes,omitempty"`
}
type VEXVulnerability struct {
	Name string `json:"name"`
}

// UnmarshalJSON accepts both spellings OpenVEX allows: an object with a name,
// or the bare identifier string.
func (v *VEXVulnerability) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		v.Name = s
		return nil
	}
	var o struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(b, &o); err != nil {
		return err
	}
	v.Name = o.Name
	return nil
}

type VEXProduct struct {
	ID            string            `json:"@id"`
	Subcomponents []VEXSubcomponent `json:"subcomponents,omitempty"`
}
type VEXSubcomponent struct {
	ID string `json:"@id"`
}

func ParseVEX(data []byte) (VEXDocument, error) {
	var d VEXDocument
	if err := json.Unmarshal(data, &d); err != nil {
		return VEXDocument{}, err
	}
	return d, nil
}

// ---- inputs ----

// SupportedDigest is one tag-referenced digest of the supported set with what
// today's rescan produced for it: the document it attested (nil when the
// digest was skipped) and the scan reports of its platform manifests (none
// when it was not scanned).
type SupportedDigest struct {
	Repository    string
	Digest        string
	Tags          []string
	Manifests     []string // its platform manifest digests, from the enumeration
	Platforms     []string // its platforms (os/arch), from the enumeration, in order (Req 6.61)
	Document      *VEXDocument
	Reports       []TrivyReport
	VEXUnresolved bool // the VEX compile for it failed today: scanned without --vex, so over-reporting
}

type StatusInputs struct {
	Today string // YYYY-MM-DD, UTC
	Run   string // the run's URL, informational
	// SourceURL is the base under which the repository's files are served
	// ("<server>/<owner>/<repo>/blob/<ref>"); with it, the files a
	// statement's notes name become links (task 15.9). Empty: no file links.
	SourceURL string
	// HandStatements names the CVEs with a hand-written statement under
	// triage/vex/, so the page can link the source of a fixed or
	// not_affected decision; nil: none linked.
	HandStatements map[string]bool
	Aperture       []string
	Ceilings       map[string]int // severity -> days (catalogue-policy.yaml triage.ceilings)
	KEVCeiling     int            // days (triage.kev_ceiling)
	KEV            map[string]bool
	Digests        []SupportedDigest
	Previous       *StatusData // the previously published status data, nil on the first run
}

// ---- the published data (metrics.json) ----

const StatusSchemaVersion = 1

// StatusMarker is the hidden marker the workflow finds the status issue by.
const StatusMarker = "<!-- catalogue-status -->"

// Revocation is one entry of triage/revocations.yaml (Req 9.5), read from the
// JSON scripts/check-revocations.sh derives from it. The status issue lists
// every entry (task 13.3) so whoever reads the status sees what was
// withdrawn, why, and what replaced it.
type Revocation struct {
	Image       string `json:"image"`
	Digest      string `json:"digest"`
	Reason      string `json:"reason"`
	Replacement string `json:"replacement"`
	Withdrawal  string `json:"withdrawal,omitempty"`
	Tombstone   string `json:"tombstone,omitempty"`
	Advisory    string `json:"advisory"`
	Date        string `json:"date"`
}

type StatusData struct {
	SchemaVersion int              `json:"schema_version"`
	GeneratedAt   string           `json:"generated_at"`
	Run           string           `json:"run,omitempty"`
	Policy        StatusPolicy     `json:"policy"`
	Repositories  []RepoStatus     `json:"repositories"`
	Findings      []FindingClock   `json:"findings"`
	Aggregates    StatusAggregates `json:"aggregates"`
	Revocations   []Revocation     `json:"revocations"`
	// Support is the support statement as declared in catalogue-policy.yaml
	// (triage.support, Req 6.49), read through scripts/triage-policy.sh and
	// published here so the statement and the clocks it scopes cannot
	// disagree (review D7). nil when the tool was not given one.
	Support *SupportStatement `json:"support,omitempty"`
	// SupersededTags counts the catalogue tags the enumeration marked
	// superseded (referenced, scanned and attested, outside the supported
	// set): the support statement's other half, as a number (task 15.8).
	SupersededTags int `json:"superseded_tags"`
}

// SupportStatement names the supported set and what a superseded digest
// keeps; both sentences are the policy file's, verbatim.
type SupportStatement struct {
	SupportedSet string `json:"supported_set"`
	Superseded   string `json:"superseded"`
}

// Definition is one definition directory as the catalogue page draws it
// (Req 6.61): its name, whether the active set lists it, the repository it
// publishes to and the tags it declares. Read from the list the status step
// derives through definition-lib.sh, never from YAML here.
type Definition struct {
	Name       string
	Active     bool
	Repository string
	Tags       []string
}

// Expiry is one accepted-risk exception the lint reports as lapsing within
// the warning window, or lapsed, attributed to the definition whose
// exception file carries it (Req 6.10, 6.61).
type Expiry struct {
	Definition string
	Lapsed     bool
	Message    string
}
type StatusPolicy struct {
	Aperture   []string       `json:"aperture"`
	Ceilings   map[string]int `json:"ceilings_days"`
	KEVCeiling int            `json:"kev_ceiling_days"`
}
type RepoStatus struct {
	Repository string         `json:"repository"`
	Digests    []DigestStatus `json:"digests"`
}
type DigestStatus struct {
	Digest    string   `json:"digest"`
	Tags      []string `json:"tags"`
	Platforms []string `json:"platforms,omitempty"` // os/arch per platform manifest (task 15.8)
	Scanned   bool     `json:"scanned"`             // at least one platform manifest report today
	Document  bool     `json:"document"`            // a compiled document today
	// Admitted is the day's admission proof for this digest (verify-catalogue,
	// Req 2.23): true when the verification policy admitted it, false when it
	// did not, absent when no proof was read (task 15.8).
	Admitted *bool `json:"admitted,omitempty"`
}

// FindingClock is one finding's stopwatch in one repository, over that
// repository's supported digests.
type FindingClock struct {
	Repository string   `json:"repository"`
	ID         string   `json:"id"`
	Severity   string   `json:"severity"`
	KEV        bool     `json:"kev"`
	Digests    []string `json:"digests,omitempty"`  // supported digests carrying it today
	Status     string   `json:"status"`             // undecided | decided | fixed
	Decision   string   `json:"decision,omitempty"` // affected | not_affected | fixed, once decided
	FirstSeen  string   `json:"first_seen"`         // the statement timestamp, never later than published before
	Decided    string   `json:"decided,omitempty"`  // action_statement_timestamp (affected) or the statement timestamp
	Fixed      string   `json:"fixed,omitempty"`    // YYYY-MM-DD: the first day absent from every supported digest of the repository

	// Attested is the decision as the statement the clock was read from
	// states it (Req 6.47 as amended; task 15.9); carried forward for a
	// finding absent today, absent for one that never had a statement.
	Attested *AttestedDecision `json:"attested,omitempty"`

	AgeDays        *int `json:"age_days,omitempty"`     // undecided only: today minus first seen
	CeilingDays    *int `json:"ceiling_days,omitempty"` // undecided only: the KEV ceiling if listed, else the severity's
	OverCeiling    bool `json:"over_ceiling"`
	DaysToDecision *int `json:"days_to_decision,omitempty"`
	DaysToFix      *int `json:"days_to_fix,omitempty"`
}
type StatusAggregates struct {
	Findings             int      `json:"findings"`
	Undecided            int      `json:"undecided"`
	OverCeiling          int      `json:"over_ceiling"`
	Decided              int      `json:"decided"`
	Fixed                int      `json:"fixed"`
	OldestUndecidedDays  *int     `json:"oldest_undecided_days,omitempty"`
	MedianDaysToDecision *float64 `json:"median_days_to_decision,omitempty"`
	MedianDaysToFix      *float64 `json:"median_days_to_fix,omitempty"`
}

func ParseStatus(data []byte) (StatusData, error) {
	var s StatusData
	if err := json.Unmarshal(data, &s); err != nil {
		return StatusData{}, err
	}
	return s, nil
}

// ---- time helpers: the clocks count whole days in UTC ----

func parseTime(s string) (time.Time, bool) {
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02"} {
		if t, err := time.Parse(layout, strings.TrimSpace(s)); err == nil {
			return t.UTC(), true
		}
	}
	return time.Time{}, false
}
func dateOf(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
func dayDiff(from, to time.Time) int { // whole days from one date to the other, never negative
	n := int(dateOf(to).Sub(dateOf(from)).Hours() / 24)
	if n < 0 {
		return 0
	}
	return n
}
func earlier(a, b string) string { // the earlier of two timestamps; an unparsable one loses
	ta, oka := parseTime(a)
	tb, okb := parseTime(b)
	switch {
	case !oka:
		return b
	case !okb:
		return a
	case tb.Before(ta):
		return b
	}
	return a
}

// ---- per digest: what the document says about one finding ----

type digestClock struct {
	firstSeen string
	undecided bool
	decided   string // the earliest decision on this digest
	decision  string
	statement *VEXStatement // the statement the decision (or the under_investigation) was read from
}

// readDigest reads one finding's statements from the digest's own document
// (the compiler already scoped every statement to this digest). No
// statement means undecided with first seen from the report; any
// under_investigation statement means undecided; otherwise the earliest
// decision counts: action_statement_timestamp for affected (Req 6.46), the
// statement timestamp for not_affected and fixed.
func readDigest(d *VEXDocument, cve, reportStamp string) digestClock {
	c := digestClock{undecided: true}
	if d == nil {
		c.firstSeen = reportStamp
		return c
	}
	found := false
	for _, st := range d.Statements {
		if st.Vulnerability.Name != cve {
			continue
		}
		found = true
		if c.firstSeen == "" {
			c.firstSeen = st.Timestamp
		} else {
			c.firstSeen = earlier(c.firstSeen, st.Timestamp)
		}
		var at string
		switch st.Status {
		case "affected":
			at = st.ActionStatementTimestamp
			if at == "" {
				at = st.Timestamp
			}
		case "not_affected", "fixed":
			at = st.Timestamp
		default: // under_investigation, or anything this compiler does not write
			c.undecided = true
			c.decided, c.decision = "", ""
			st := st
			c.statement = &st
			return c
		}
		if c.decided == "" || earlier(c.decided, at) == at && at != c.decided {
			st := st
			c.decided, c.decision, c.statement = at, st.Status, &st
		}
	}
	if !found {
		c.firstSeen = reportStamp
		return c
	}
	c.undecided = false
	return c
}

// ---- BuildStatus ----

type findingKey struct{ repo, cve string }

func BuildStatus(in StatusInputs) StatusData {
	today, ok := parseTime(in.Today)
	if !ok {
		today = time.Now().UTC()
	}
	todayStr := dateOf(today).Format("2006-01-02")

	previous := map[findingKey]FindingClock{}
	previousOrder := []findingKey{}
	if in.Previous != nil {
		for _, f := range in.Previous.Findings {
			k := findingKey{f.Repository, f.ID}
			if _, dup := previous[k]; !dup {
				previousOrder = append(previousOrder, k)
			}
			previous[k] = f
		}
	}

	// today's evidence per (repository, finding), in input order
	type acc struct {
		key       findingKey
		sev       string
		rank      int
		digests   []string
		undecided bool
		decided   string // the latest decision across the digests carrying it
		decision  string
		statement *VEXStatement
		firstSeen string
	}
	accs := map[findingKey]*acc{}
	order := []findingKey{}
	repoScanned := map[string]bool{}
	repoOrder := []string{}
	repos := map[string]*RepoStatus{}

	for _, d := range in.Digests {
		if repos[d.Repository] == nil {
			repos[d.Repository] = &RepoStatus{Repository: d.Repository}
			repoOrder = append(repoOrder, d.Repository)
		}
		complete, _ := d.scanState()
		repos[d.Repository].Digests = append(repos[d.Repository].Digests, DigestStatus{
			Digest: d.Digest, Tags: d.Tags, Platforms: d.Platforms, Scanned: complete, Document: d.Document != nil})
		// A repository counts as looked at only when every platform manifest
		// of every supported digest has a report: absence read from half a
		// scan would be a fix date invented.
		if _, seen := repoScanned[d.Repository]; !seen {
			repoScanned[d.Repository] = true
		}
		if !complete {
			repoScanned[d.Repository] = false
		}
		// present today: reported or suppressed alike, within the aperture
		presentSev := map[string]string{}
		presentRank := map[string]int{}
		stamp := ""
		for _, r := range d.Reports {
			if stamp == "" || earlier(stamp, r.CreatedAt) == r.CreatedAt {
				stamp = r.CreatedAt
			}
			eachFinding(r, func(f reportFinding) {
				rank := sevRank(f.Severity, in.Aperture)
				if rank == 0 {
					return
				}
				if rank > presentRank[f.ID] {
					presentRank[f.ID] = rank
					presentSev[f.ID] = f.Severity
				}
			})
		}
		cves := make([]string, 0, len(presentSev))
		for cve := range presentSev {
			cves = append(cves, cve)
		}
		sort.Strings(cves)
		for _, cve := range cves {
			k := findingKey{d.Repository, cve}
			a := accs[k]
			if a == nil {
				a = &acc{key: k}
				accs[k] = a
				order = append(order, k)
			}
			if presentRank[cve] > a.rank {
				a.rank, a.sev = presentRank[cve], presentSev[cve]
			}
			a.digests = append(a.digests, d.Digest)
			dc := readDigest(d.Document, cve, stamp)
			if a.firstSeen == "" {
				a.firstSeen = dc.firstSeen
			} else {
				a.firstSeen = earlier(a.firstSeen, dc.firstSeen)
			}
			if dc.undecided {
				a.undecided = true
				if a.statement == nil || a.statement.Status != "under_investigation" {
					a.statement = dc.statement
				}
				continue
			}
			if a.decided == "" || earlier(a.decided, dc.decided) == a.decided && dc.decided != a.decided {
				a.decided, a.decision, a.statement = dc.decided, dc.decision, dc.statement
			}
		}
	}

	// rows: what is present today, then what the previous data knew and today does not list
	rows := []FindingClock{}
	seen := map[findingKey]bool{}
	for _, k := range order {
		a := accs[k]
		f := FindingClock{Repository: k.repo, ID: k.cve, Severity: a.sev, KEV: in.KEV[k.cve], Digests: a.digests, FirstSeen: a.firstSeen}
		if p, ok := previous[k]; ok {
			f.FirstSeen = earlier(f.FirstSeen, p.FirstSeen)
			if f.FirstSeen == "" {
				f.FirstSeen = p.FirstSeen
			}
		}
		if a.undecided {
			f.Status = "undecided"
		} else {
			f.Status, f.Decided, f.Decision = "decided", a.decided, a.decision
		}
		f.Attested = attestedDecision(a.statement, k.cve, in.SourceURL, in.HandStatements)
		rows = append(rows, f)
		seen[k] = true
	}
	for _, k := range previousOrder {
		if seen[k] {
			continue
		}
		p := previous[k]
		f := FindingClock{Repository: k.repo, ID: k.cve, Severity: p.Severity, KEV: in.KEV[k.cve] || p.KEV,
			Status: p.Status, Decision: p.Decision, FirstSeen: p.FirstSeen, Decided: p.Decided, Fixed: p.Fixed, Attested: p.Attested}
		if repoScanned[k.repo] {
			// absent from every supported digest of a repository that was
			// looked at today: fixed, on the first such day (Req 6.46)
			f.Status = "fixed"
			if f.Fixed == "" {
				f.Fixed = todayStr
			}
		}
		rows = append(rows, f)
	}

	// the derived numbers
	for i := range rows {
		f := &rows[i]
		first, okFirst := parseTime(f.FirstSeen)
		if okFirst {
			if f.Decided != "" {
				if t, ok := parseTime(f.Decided); ok {
					n := dayDiff(first, t)
					f.DaysToDecision = &n
				}
			}
			if f.Fixed != "" {
				if t, ok := parseTime(f.Fixed); ok {
					n := dayDiff(first, t)
					f.DaysToFix = &n
				}
			}
			if f.Status == "undecided" {
				n := dayDiff(first, today)
				f.AgeDays = &n
				if c, ok := ceilingFor(in, f.Severity, f.KEV); ok {
					f.CeilingDays = &c
					f.OverCeiling = n > c
				}
			}
		}
	}
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].Repository != rows[j].Repository {
			return rows[i].Repository < rows[j].Repository
		}
		return rows[i].ID < rows[j].ID
	})

	sort.Strings(repoOrder)
	repoList := make([]RepoStatus, 0, len(repoOrder))
	for _, r := range repoOrder {
		repoList = append(repoList, *repos[r])
	}
	return StatusData{
		SchemaVersion: StatusSchemaVersion,
		GeneratedAt:   todayStr,
		Run:           in.Run,
		Policy:        StatusPolicy{Aperture: in.Aperture, Ceilings: in.Ceilings, KEVCeiling: in.KEVCeiling},
		Repositories:  repoList,
		Findings:      rows,
		Aggregates:    aggregate(rows),
	}
}

func ceilingFor(in StatusInputs, severity string, kev bool) (int, bool) {
	if kev {
		return in.KEVCeiling, in.KEVCeiling > 0
	}
	c, ok := in.Ceilings[strings.ToUpper(severity)]
	return c, ok
}

func aggregate(rows []FindingClock) StatusAggregates {
	ag := StatusAggregates{Findings: len(rows)}
	var toDecision, toFix []float64
	for _, f := range rows {
		switch f.Status {
		case "undecided":
			ag.Undecided++
			if f.OverCeiling {
				ag.OverCeiling++
			}
			if f.AgeDays != nil && (ag.OldestUndecidedDays == nil || *f.AgeDays > *ag.OldestUndecidedDays) {
				n := *f.AgeDays
				ag.OldestUndecidedDays = &n
			}
		case "decided":
			ag.Decided++
		case "fixed":
			ag.Fixed++
		}
		if f.DaysToDecision != nil {
			toDecision = append(toDecision, float64(*f.DaysToDecision))
		}
		if f.DaysToFix != nil {
			toFix = append(toFix, float64(*f.DaysToFix))
		}
	}
	ag.MedianDaysToDecision = median(toDecision)
	ag.MedianDaysToFix = median(toFix)
	return ag
}

func median(xs []float64) *float64 {
	if len(xs) == 0 {
		return nil
	}
	sort.Float64s(xs)
	var m float64
	if n := len(xs); n%2 == 1 {
		m = xs[n/2]
	} else {
		m = (xs[n/2-1] + xs[n/2]) / 2
	}
	return &m
}

// ---- the status issue (Req 6.47) ----

// RenderStatusIssue is the issue body: the marker, the numbers, the open
// findings against their ceilings, the fixed ones folded away, and the
// metrics JSON in a fenced block the next run reads back (ExtractFencedJSON).
// shortDigest renders sha256:<64 hex> as sha256:<12 hex>, the table's width.
func shortDigest(d string) string {
	const prefix = "sha256:"
	if strings.HasPrefix(d, prefix) && len(d) > len(prefix)+12 {
		return d[:len(prefix)+12]
	}
	return d
}

func RenderStatusIssue(s StatusData) string {
	var b strings.Builder
	b.WriteString(StatusMarker + "\n")
	b.WriteString("## Catalogue status\n\n")
	b.WriteString("The clocks over the supported set (Req 6.46, 6.47), read from the attested OpenVEX statements and today's attested scan reports: ")
	b.WriteString("first seen is the statement's timestamp, decided its decision time, fixed the first day a finding was absent, reported and suppressed alike, from every supported digest of its repository. ")
	b.WriteString("Ages of undecided findings are measured against the policy file's ceilings. Maintained by the daily rescan; the JSON block below is the same data as the `catalogue-status` artifact.\n\n")
	if s.Support != nil {
		fmt.Fprintf(&b, "The supported set is %s; a superseded tag-referenced digest is %s (the support statement, `catalogue-policy.yaml` `triage.support`, Req 6.49).\n\n", s.Support.SupportedSet, s.Support.Superseded)
	}

	ag := s.Aggregates
	run := s.GeneratedAt
	if s.Run != "" {
		run = fmt.Sprintf("%s ([run](%s))", s.GeneratedAt, s.Run)
	}
	fmt.Fprintf(&b, "- generated: %s\n", run)
	oldest := ""
	if ag.OldestUndecidedDays != nil {
		oldest = fmt.Sprintf(", oldest: %d days", *ag.OldestUndecidedDays)
	}
	fmt.Fprintf(&b, "- findings: %d; undecided: %d (over ceiling: %d%s); decided: %d; fixed: %d\n", ag.Findings, ag.Undecided, ag.OverCeiling, oldest, ag.Decided, ag.Fixed)
	fmt.Fprintf(&b, "- median days to decision: %s; median days to fix: %s\n", num(ag.MedianDaysToDecision), num(ag.MedianDaysToFix))
	if len(s.Revocations) == 0 {
		b.WriteString("- revocations: none\n\n")
	} else {
		fmt.Fprintf(&b, "- revocations: %d (Req 9.5), listed below\n\n", len(s.Revocations))
		b.WriteString("| Repository | Digest | Date | Reason | Outcome | Advisory |\n")
		b.WriteString("|---|---|---|---|---|---|\n")
		for _, r := range s.Revocations {
			outcome := "withdrawn (" + orNA(r.Withdrawal) + ")"
			if r.Replacement != "" && r.Replacement != "none" {
				outcome = "replaced by `" + shortDigest(r.Replacement) + "`"
			} else if r.Tombstone != "" {
				outcome += ", tombstone `" + shortDigest(r.Tombstone) + "`"
			}
			advisory := r.Advisory
			if i := strings.LastIndex(r.Advisory, "/"); i >= 0 && i+1 < len(r.Advisory) {
				advisory = fmt.Sprintf("[%s](%s)", r.Advisory[i+1:], r.Advisory)
			}
			fmt.Fprintf(&b, "| %s | `%s` | %s | %s | %s | %s |\n",
				shortName(r.Image), shortDigest(r.Digest), r.Date, r.Reason, outcome, advisory)
		}
		b.WriteString("\n")
	}

	open := []FindingClock{}
	fixed := []FindingClock{}
	for _, f := range s.Findings {
		if f.Status == "fixed" {
			fixed = append(fixed, f)
		} else {
			open = append(open, f)
		}
	}
	sort.SliceStable(open, func(i, j int) bool {
		a, c := open[i], open[j]
		if (a.Status == "undecided") != (c.Status == "undecided") {
			return a.Status == "undecided"
		}
		if a.Status == "undecided" {
			if a.OverCeiling != c.OverCeiling {
				return a.OverCeiling
			}
			if age(a) != age(c) {
				return age(a) > age(c)
			}
		}
		if a.Repository != c.Repository {
			return a.Repository < c.Repository
		}
		return a.ID < c.ID
	})

	b.WriteString("| Repository | Finding | Severity | KEV | Status | First seen | Decided | Age / ceiling | Decision |\n")
	b.WriteString("|---|---|---|---|---|---|---|---|---|\n")
	if len(open) == 0 {
		b.WriteString("| n/a | nothing undecided or decided-and-present today | | | | | | | |\n")
	}
	for _, f := range open {
		status := f.Status
		if f.Decision != "" {
			status = fmt.Sprintf("%s (%s)", f.Status, f.Decision)
		}
		ageCell := "n/a"
		if f.AgeDays != nil {
			ceiling := "n/a"
			if f.CeilingDays != nil {
				ceiling = fmt.Sprint(*f.CeilingDays)
			}
			ageCell = fmt.Sprintf("%d / %s", *f.AgeDays, ceiling)
			if f.OverCeiling {
				ageCell = "**" + ageCell + "**"
			}
		}
		fmt.Fprintf(&b, "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n",
			shortName(f.Repository), f.ID, f.Severity, yesNo(f.KEV), status, day(f.FirstSeen), day(f.Decided), ageCell, decisionCell(f.Attested))
	}
	b.WriteString("\n")

	fmt.Fprintf(&b, "<details><summary>fixed (%d)</summary>\n\n", len(fixed))
	if len(fixed) > 0 {
		b.WriteString("| Repository | Finding | Severity | First seen | Decided | Fixed | Days to fix | Last decision |\n")
		b.WriteString("|---|---|---|---|---|---|---|---|\n")
		for _, f := range fixed {
			fmt.Fprintf(&b, "| %s | %s | %s | %s | %s | %s | %s | %s |\n",
				shortName(f.Repository), f.ID, f.Severity, day(f.FirstSeen), day(f.Decided), orNA(f.Fixed), intOrNA(f.DaysToFix), decisionCell(f.Attested))
		}
		b.WriteString("\n")
	}
	b.WriteString("</details>\n\n")

	data, _ := json.MarshalIndent(s, "", " ")
	b.WriteString("```json\n")
	b.Write(data)
	b.WriteString("\n```\n")
	return b.String()
}

// ExtractFencedJSON returns the last ```json block after the marker (or in
// the whole text when the marker is absent): the previously published data.
func ExtractFencedJSON(body string) ([]byte, bool) {
	from := 0
	if i := strings.Index(body, StatusMarker); i >= 0 {
		from = i + len(StatusMarker)
	}
	rest := body[from:]
	start := strings.LastIndex(rest, "```json\n")
	if start < 0 {
		return nil, false
	}
	start += len("```json\n")
	end := strings.Index(rest[start:], "\n```")
	if end < 0 {
		return nil, false
	}
	return []byte(rest[start : start+end]), true
}

// StatusWorkDirName is the rescan's per-digest naming, <name>__<12 hex>: the
// re-attest work directory and the prefix of the digest's report files.
func StatusWorkDirName(repository, digest string) string {
	hex := strings.TrimPrefix(digest, "sha256:")
	if len(hex) > 12 {
		hex = hex[:12]
	}
	return shortName(repository) + "__" + hex
}

func age(f FindingClock) int {
	if f.AgeDays == nil {
		return -1
	}
	return *f.AgeDays
}
func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func day(ts string) string {
	if t, ok := parseTime(ts); ok {
		return dateOf(t).Format("2006-01-02")
	}
	return orNA(ts)
}
func orNA(s string) string {
	if s == "" {
		return "n/a"
	}
	return s
}
func intOrNA(n *int) string {
	if n == nil {
		return "n/a"
	}
	return fmt.Sprint(*n)
}
func num(f *float64) string {
	if f == nil {
		return "n/a"
	}
	return fmt.Sprintf("%g", *f)
}

// decisionCell is the Decision column of the issue's tables: the short form
// and the statement's links as Markdown; "n/a" for a finding that never had
// a statement. The full statement stays on the page (task 15.9).
func decisionCell(d *AttestedDecision) string {
	if d == nil {
		return "n/a"
	}
	cell := strings.ReplaceAll(d.Summary, "|", "\\|")
	if len(d.Links) > 0 {
		parts := make([]string, 0, len(d.Links))
		for _, l := range d.Links {
			parts = append(parts, fmt.Sprintf("[%s](%s)", l.Label, l.URL))
		}
		cell += " (" + strings.Join(parts, ", ") + ")"
	}
	return cell
}
