package rescan

import (
	"regexp"
	"strings"
)

// The decision beside the clock (Req 6.47 as amended; task 15.9). A clock
// says when a finding was decided; the statement it was read from says what
// was decided and why, in the words the catalogue attested. This file keeps
// those words: the status, the justification, the action statement of an
// accepted risk or the impact statement of a fixed or not_affected decision,
// the notes, and the links they carry, plus a short form for a table cell.
// Only the attested document is read, never a repository file: what the
// page says is what the signed document says.

// AttestedDecision is the decision as attested, kept in the published data.
type AttestedDecision struct {
	Status        string `json:"status"`
	Justification string `json:"justification,omitempty"`
	Statement     string `json:"statement,omitempty"` // action statement (affected) or impact statement (fixed, not_affected)
	Notes         string `json:"notes,omitempty"`
	Treatment     string `json:"treatment,omitempty"` // affected: the word before the first colon of the action statement
	Expires       string `json:"expires,omitempty"`   // affected: the compiler's "Expires: YYYY-MM-DD."
	Summary       string `json:"summary"`             // the short form for a table cell
	Links         []Link `json:"links,omitempty"`     // the statement's and notes' links, then the files the notes name
}

// Link is one labelled URL.
type Link struct {
	Label string `json:"label"`
	URL   string `json:"url"`
}

var (
	urlPattern     = regexp.MustCompile(`https?://[^\s<>"')\]]+`)
	githubIssue    = regexp.MustCompile(`^https?://github\.com/[^/]+/([^/]+)/(?:issues|pull)/(\d+)$`)
	expiresPattern = regexp.MustCompile(`Expires: (\d{4}-\d{2}-\d{2})`)
	exceptionFile  = regexp.MustCompile(`exception in ([A-Za-z0-9._-]+\.yaml)`)
)

// attestedDecision derives the record from the statement a clock was read
// from; nil for nil (a finding present without any statement).
func attestedDecision(st *VEXStatement, cve, sourceURL string, hand map[string]bool) *AttestedDecision {
	if st == nil {
		return nil
	}
	d := &AttestedDecision{Status: st.Status, Justification: st.Justification, Notes: strings.TrimSpace(st.StatusNotes)}
	switch st.Status {
	case "affected":
		d.Statement = strings.TrimSpace(st.ActionStatement)
		if i := strings.Index(d.Statement, ":"); i > 0 && !strings.ContainsAny(d.Statement[:i], " \t") {
			d.Treatment = d.Statement[:i]
		}
		if m := expiresPattern.FindStringSubmatch(d.Statement); m != nil {
			d.Expires = m[1]
		}
	default:
		d.Statement = strings.TrimSpace(st.ImpactStatement)
	}
	d.Summary = summarise(d)
	d.Links = decisionLinks(d.Statement+" "+d.Notes, sourceURL)
	if sourceURL != "" {
		base := strings.TrimRight(sourceURL, "/")
		if strings.Contains(d.Notes, "LOG.md") {
			d.Links = appendLink(d.Links, Link{Label: "LOG", URL: base + "/triage/LOG.md"})
		}
		if m := exceptionFile.FindStringSubmatch(d.Notes); m != nil {
			d.Links = appendLink(d.Links, Link{Label: "exception file", URL: base + "/triage/accepted-risk/" + m[1]})
		}
		if hand[cve] {
			d.Links = appendLink(d.Links, Link{Label: "statement", URL: base + "/triage/vex/" + cve + ".openvex.json"})
		}
	}
	return d
}

// summarise is the short form: one line a table cell can hold.
func summarise(d *AttestedDecision) string {
	switch d.Status {
	case "affected":
		t := d.Treatment
		if t == "" {
			t = "accepted"
		}
		if d.Expires != "" {
			return t + ", accepted risk until " + d.Expires
		}
		return t + ", accepted risk"
	case "not_affected":
		if d.Justification != "" {
			return "not affected: " + strings.ReplaceAll(d.Justification, "_", " ")
		}
		return "not affected: " + firstClause(d.Statement, 100)
	case "fixed":
		if d.Statement == "" {
			return "fixed, as attested"
		}
		return "fixed: " + firstClause(d.Statement, 120)
	case "under_investigation":
		return "undecided, awaiting a triage decision"
	}
	return d.Status
}

// firstClause is the text up to its first sentence end, capped.
func firstClause(s string, max int) string {
	s = strings.TrimSpace(s)
	if i := strings.Index(s, ". "); i > 0 {
		s = s[:i]
	}
	s = strings.TrimSuffix(s, ".")
	if len(s) > max {
		if i := strings.LastIndex(s[:max], " "); i > 0 {
			s = s[:i]
		} else {
			s = s[:max]
		}
		s += "…"
	}
	return s
}

// decisionLinks extracts every URL of a text, in order, once each, with a
// label a reader can scan: repo#n for a GitHub issue or pull request, the
// host otherwise. Trailing punctuation belongs to the sentence, not the URL.
func decisionLinks(text, _ string) []Link {
	var out []Link
	for _, raw := range urlPattern.FindAllString(text, -1) {
		u := strings.TrimRight(raw, ".,;:)")
		label := ""
		if m := githubIssue.FindStringSubmatch(u); m != nil {
			label = m[1] + "#" + m[2]
		} else {
			host := strings.TrimPrefix(strings.TrimPrefix(u, "https://"), "http://")
			if i := strings.Index(host, "/"); i > 0 {
				host = host[:i]
			}
			label = host
		}
		out = appendLink(out, Link{Label: label, URL: u})
	}
	return out
}

func appendLink(links []Link, l Link) []Link {
	for _, have := range links {
		if have.URL == l.URL {
			return links
		}
	}
	return append(links, l)
}
