package rescan

import (
	"bytes"
	_ "embed"
	"fmt"
	"html/template"
	"strings"
)

// The catalogue page (Req 6.61; task 15.8; design Decision 12): the status
// data drawn as one card per definition, with the clocks, the revocation
// record and the support statement beneath. BuildPage derives the view from
// the data the tool already publishes and the definitions list the workflow
// wrote; RenderCataloguePage prints it through one embedded html/template.
// Every number on the page is the JSON's or a count over it, and the page
// loads nothing from anywhere: no script, no stylesheet, no image.

// Page is the view the template renders.
type Page struct {
	GeneratedAt    string
	Run            string
	Policy         StatusPolicy
	Support        *SupportStatement
	Aggregates     StatusAggregates
	SupersededTags int
	Cards          []Card
	Open           []FindingClock // undecided and decided, the issue's order
	Fixed          []FindingClock
	Revocations    []Revocation
}

// Card is one definition as the page shows it.
type Card struct {
	Name        string
	Active      bool
	Repository  string
	Tags        []string
	Digests     []CardDigest    // the repository's supported digests the definition's tags reference
	Unpublished []string        // declared tags no supported digest carries today
	Severities  []SeverityCount // per aperture severity, fixed findings left out
	Undecided   int
	OverCeiling int
	Fixed       int
	Expiries    []Expiry
}

// CardDigest is one supported digest on a card.
type CardDigest struct {
	Digest    string
	Tags      []string
	Platforms []string
	Scanned   bool
	Document  bool
	Admitted  *bool
}

// SeverityCount is a card's findings of one aperture severity.
type SeverityCount struct {
	Severity    string
	Count       int
	Undecided   int
	OverCeiling int
}

// BuildPage derives the view: a definition's card carries the digests of its
// repository whose tags intersect the definition's declared tags (a runtime
// definition and its compat variant share a repository and are told apart by
// tag), the findings on those digests (a finding naming no digest, fixed or
// carried forward unscanned, counts for every definition of the repository),
// and the exceptions the lint attributed to its exception file.
func BuildPage(s StatusData, defs []Definition, expiries []Expiry) Page {
	p := Page{GeneratedAt: s.GeneratedAt, Run: s.Run, Policy: s.Policy, Support: s.Support, Aggregates: s.Aggregates,
		SupersededTags: s.SupersededTags, Revocations: s.Revocations}
	byRepo := map[string][]DigestStatus{}
	for _, r := range s.Repositories {
		byRepo[r.Repository] = r.Digests
	}
	for _, d := range defs {
		c := Card{Name: d.Name, Active: d.Active, Repository: d.Repository, Tags: d.Tags}
		declared := map[string]bool{}
		for _, t := range d.Tags {
			declared[t] = true
		}
		carried := map[string]bool{}
		mine := map[string]bool{}
		for _, ds := range byRepo[d.Repository] {
			var tags []string
			for _, t := range ds.Tags {
				if declared[t] {
					tags = append(tags, t)
					carried[t] = true
				}
			}
			if len(tags) == 0 {
				continue
			}
			mine[ds.Digest] = true
			c.Digests = append(c.Digests, CardDigest{Digest: ds.Digest, Tags: tags, Platforms: ds.Platforms,
				Scanned: ds.Scanned, Document: ds.Document, Admitted: ds.Admitted})
		}
		for _, t := range d.Tags {
			if !carried[t] {
				c.Unpublished = append(c.Unpublished, t)
			}
		}
		counts := map[string]*SeverityCount{}
		for _, sev := range s.Policy.Aperture {
			sc := &SeverityCount{Severity: sev}
			counts[sev] = sc
			c.Severities = append(c.Severities, *sc)
		}
		for _, f := range s.Findings {
			if f.Repository != d.Repository {
				continue
			}
			if f.Status == "fixed" {
				c.Fixed++
				continue
			}
			// A finding names the supported digests carrying it today; one
			// that names none (carried forward on a day its repository was
			// not scanned) is the repository's, so every card of the
			// repository shows it rather than none.
			on := len(f.Digests) == 0
			for _, dg := range f.Digests {
				if mine[dg] {
					on = true
				}
			}
			if !on {
				continue
			}
			sc, ok := counts[f.Severity]
			if !ok {
				sc = &SeverityCount{Severity: f.Severity}
				counts[f.Severity] = sc
				c.Severities = append(c.Severities, *sc)
			}
			sc.Count++
			if f.Status == "undecided" {
				sc.Undecided++
				c.Undecided++
				if f.OverCeiling {
					sc.OverCeiling++
					c.OverCeiling++
				}
			}
		}
		for i := range c.Severities {
			c.Severities[i] = *counts[c.Severities[i].Severity]
		}
		for _, e := range expiries {
			if e.Definition == d.Name {
				c.Expiries = append(c.Expiries, e)
			}
		}
		p.Cards = append(p.Cards, c)
	}
	for _, f := range s.Findings {
		if f.Status == "fixed" {
			p.Fixed = append(p.Fixed, f)
		} else {
			p.Open = append(p.Open, f)
		}
	}
	return p
}

//go:embed page.html.tmpl
var pageTemplate string

var pageFuncs = template.FuncMap{
	"short": shortDigest,
	"join":  func(v []string) string { return strings.Join(v, ", ") },
	"joinInt": func(v map[string]int, keys []string) string {
		parts := make([]string, 0, len(keys))
		for _, k := range keys {
			parts = append(parts, fmt.Sprintf("%s %d days", k, v[k]))
		}
		return strings.Join(parts, ", ")
	},
	"num":       num,
	"shortName": shortName,
	"day":       day,
	"yesNo":     yesNo,
	"deref":     func(b *bool) bool { return b != nil && *b },
	"admission": func(a *bool) string {
		switch {
		case a == nil:
			return "admission not checked"
		case *a:
			return "admitted by the verification policy"
		default:
			return "not admitted"
		}
	},
	"ptr": func(p *int) string {
		if p == nil {
			return "–"
		}
		return fmt.Sprint(*p)
	},
	"advisoryName": func(a string) string {
		if i := strings.LastIndex(a, "/"); i >= 0 && i+1 < len(a) {
			return a[i+1:]
		}
		return a
	},
	"outcome": func(r Revocation) string {
		outcome := "withdrawn (" + orNA(r.Withdrawal) + ")"
		if r.Replacement != "" && r.Replacement != "none" {
			outcome = "replaced by " + shortDigest(r.Replacement)
		} else if r.Tombstone != "" {
			outcome += ", tombstone " + shortDigest(r.Tombstone)
		}
		return outcome
	},
}

// RenderCataloguePage prints the page. The template is parsed once per call
// from the embedded file; a template that fails to parse or execute is a
// programming error, and panics rather than publishing half a page.
func RenderCataloguePage(p Page) string {
	t := template.Must(template.New("page").Funcs(pageFuncs).Parse(pageTemplate))
	var b bytes.Buffer
	if err := t.Execute(&b, p); err != nil {
		panic("catalogue page: " + err.Error())
	}
	return b.String()
}
