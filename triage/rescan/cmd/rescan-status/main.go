// Command rescan-status computes the clocks over the supported set and
// renders the status issue (task 10.4; Req 6.46, 6.47). It is glue around the
// tested rescan package: read the rescan's outputs by their naming, call
// BuildStatus, write metrics.json and the issue body. Reading the previous
// status issue and publishing the new one live in rescan.yml.
//
// Usage:
//
//	rescan-status --enumeration <tsv> --reattest <dir> --reports <dir> \
//	  --aperture CRITICAL,HIGH --ceilings CRITICAL=30,HIGH=90 --kev-ceiling 14 \
//	  [--kev f] [--previous metrics.json | --previous-body issue.md] [--today YYYY-MM-DD] [--run url] \
//	  --out-json metrics.json --out-body issue.md
//
// --enumeration is the rescan's enumeration.tsv (repository, tag, digest,
// platform, manifest, supported|superseded); only supported rows count.
// --reattest is the re-attest work directory: <name>__<12 hex>/out/*.openvex.json
// is the document attested today. --reports holds the supported set's scan
// reports, <name>__<12 hex>__<platform>.json, scanned with --show-suppressed.
// A document or report that does not parse is an error, not an empty input:
// a clock read from half the evidence would be wrong by construction.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/mm-weber/dhc-pipeline/triage/rescan"
)

func main() {
	enumeration := flag.String("enumeration", "", "the rescan's enumeration.tsv — required")
	reattestDir := flag.String("reattest", "", "re-attest work directory (rescan-out/reattest) — required")
	reportsDir := flag.String("reports", "", "supported-set scan reports (rescan-out/trivy) — required")
	kevFile := flag.String("kev", "", "CISA KEV catalog JSON — optional")
	apertureFlag := flag.String("aperture", "", "decision aperture, comma-separated severities in rank order — required")
	ceilingsFlag := flag.String("ceilings", "", "exception ceilings in days per severity, SEV=days comma-separated — required")
	kevCeiling := flag.Int("kev-ceiling", 0, "ceiling in days for a KEV-listed finding — required")
	previousFile := flag.String("previous", "", "previously published metrics.json — optional")
	previousBody := flag.String("previous-body", "", "the status issue's body, the fenced JSON block is read — optional")
	todayFlag := flag.String("today", "", "YYYY-MM-DD; default: the latest report's date, else now (UTC)")
	runURL := flag.String("run", "", "the run's URL, recorded in the data — optional")
	outJSON := flag.String("out-json", "", "where to write metrics.json — required")
	outBody := flag.String("out-body", "", "where to write the issue body — required")
	flag.Parse()

	for name, v := range map[string]string{"--enumeration": *enumeration, "--reattest": *reattestDir, "--reports": *reportsDir,
		"--aperture": *apertureFlag, "--ceilings": *ceilingsFlag, "--out-json": *outJSON, "--out-body": *outBody} {
		if v == "" {
			fatal(name + " is required")
		}
	}
	if *kevCeiling <= 0 {
		fatal("--kev-ceiling <days> is required: the ceilings are declared, never assumed (Req 6.49)")
	}
	ceilings := map[string]int{}
	for _, kv := range strings.Split(*ceilingsFlag, ",") {
		parts := strings.SplitN(strings.TrimSpace(kv), "=", 2)
		if len(parts) != 2 {
			fatal("--ceilings: expected SEV=days, got " + kv)
		}
		n, err := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err != nil || n <= 0 {
			fatal("--ceilings: " + kv + " is not a number of days")
		}
		ceilings[strings.ToUpper(strings.TrimSpace(parts[0]))] = n
	}

	digests, err := loadSupported(*enumeration, *reattestDir, *reportsDir)
	if err != nil {
		fatal(err.Error())
	}

	in := rescan.StatusInputs{
		Run:        *runURL,
		Aperture:   strings.Split(*apertureFlag, ","),
		Ceilings:   ceilings,
		KEVCeiling: *kevCeiling,
		KEV:        map[string]bool{},
		Digests:    digests,
	}
	if *kevFile != "" {
		data, err := os.ReadFile(*kevFile)
		if err != nil {
			fatal("kev: " + err.Error())
		}
		if in.KEV, err = rescan.ParseKEV(data); err != nil {
			fatal("kev: " + err.Error())
		}
	}
	switch {
	case *previousFile != "":
		data, err := os.ReadFile(*previousFile)
		if err != nil {
			fatal("previous: " + err.Error())
		}
		prev, err := rescan.ParseStatus(data)
		if err != nil {
			fatal("previous: " + err.Error())
		}
		in.Previous = &prev
	case *previousBody != "":
		data, err := os.ReadFile(*previousBody)
		if err != nil {
			fatal("previous-body: " + err.Error())
		}
		if raw, ok := rescan.ExtractFencedJSON(string(data)); ok {
			prev, err := rescan.ParseStatus(raw)
			if err != nil {
				fatal("previous-body: the fenced block does not parse: " + err.Error())
			}
			in.Previous = &prev
		} else {
			warn("previous-body: no fenced JSON block, starting the clocks from today's evidence")
		}
	}
	in.Today = *todayFlag
	if in.Today == "" {
		in.Today = latestReportDay(digests)
	}

	status := rescan.BuildStatus(in)
	data, err := json.MarshalIndent(status, "", "  ")
	if err != nil {
		fatal(err.Error())
	}
	if err := os.WriteFile(*outJSON, append(data, '\n'), 0o644); err != nil {
		fatal(err.Error())
	}
	if err := os.WriteFile(*outBody, []byte(rescan.RenderStatusIssue(status)), 0o644); err != nil {
		fatal(err.Error())
	}
	ag := status.Aggregates
	fmt.Printf("rescan-status: %d finding(s) over %d supported digest(s): %d undecided (%d over ceiling), %d decided, %d fixed\n",
		ag.Findings, len(digests), ag.Undecided, ag.OverCeiling, ag.Decided, ag.Fixed)
}

// loadSupported reads the enumeration and, for every supported digest, the
// document and reports the rescan wrote under its <name>__<12 hex> naming.
func loadSupported(enumeration, reattestDir, reportsDir string) ([]rescan.SupportedDigest, error) {
	f, err := os.Open(enumeration)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	type key struct{ repo, digest string }
	byKey := map[key]*rescan.SupportedDigest{}
	order := []key{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 1024*1024)
	for sc.Scan() {
		cols := strings.Split(sc.Text(), "\t")
		if len(cols) < 6 || cols[5] != "supported" {
			continue
		}
		k := key{cols[0], cols[2]}
		d := byKey[k]
		if d == nil {
			d = &rescan.SupportedDigest{Repository: cols[0], Digest: cols[2]}
			byKey[k] = d
			order = append(order, k)
		}
		if !contains(d.Tags, cols[1]) {
			d.Tags = append(d.Tags, cols[1])
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	out := make([]rescan.SupportedDigest, 0, len(order))
	for _, k := range order {
		d := byKey[k]
		work := rescan.StatusWorkDirName(d.Repository, d.Digest)
		docs, _ := filepath.Glob(filepath.Join(reattestDir, work, "out", "*.openvex.json"))
		if len(docs) > 0 {
			sort.Strings(docs)
			data, err := os.ReadFile(docs[0])
			if err != nil {
				return nil, err
			}
			doc, err := rescan.ParseVEX(data)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", docs[0], err)
			}
			d.Document = &doc
		}
		reports, _ := filepath.Glob(filepath.Join(reportsDir, work+"__*.json"))
		sort.Strings(reports)
		for _, r := range reports {
			data, err := os.ReadFile(r)
			if err != nil {
				return nil, err
			}
			rep, err := rescan.ParseTrivy(data)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", r, err)
			}
			d.Reports = append(d.Reports, rep)
		}
		out = append(out, *d)
	}
	return out, nil
}

// latestReportDay is the UTC date of the newest report, the day the
// evidence was taken; without reports, today.
func latestReportDay(digests []rescan.SupportedDigest) string {
	var latest time.Time
	for _, d := range digests {
		for _, r := range d.Reports {
			for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
				if t, err := time.Parse(layout, r.CreatedAt); err == nil && t.After(latest) {
					latest = t
					break
				}
			}
		}
	}
	if latest.IsZero() {
		latest = time.Now()
	}
	return latest.UTC().Format("2006-01-02")
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}

func warn(format string, a ...any) { fmt.Fprintf(os.Stderr, "rescan-status: "+format+"\n", a...) }

func fatal(msg string) {
	fmt.Fprintln(os.Stderr, "rescan-status: "+msg)
	os.Exit(1)
}
