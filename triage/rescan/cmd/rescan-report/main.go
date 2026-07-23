// Command rescan-report turns Trivy scan output, plus EPSS/KEV enrichment and the
// set of already-open CVE issues, into the list of new GitHub issues to file. It
// is pure glue around the tested rescan package: read the inputs, call
// BuildIssues, print the resulting issues as JSON on stdout. All network I/O
// (scanning, fetching EPSS/KEV, listing/creating issues) lives in rescan.yml.
//
// Usage:
//
//	rescan-report --trivy <dir> [--epss f] [--kev f] [--existing f]
//
// --trivy is a directory of Trivy image-scan JSON reports (one per image). The
// enrichment/dedup inputs are optional: a missing or unreadable file degrades to
// empty (no enrichment / no dedup) rather than failing the run.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/mm-weber/dhc-pipeline/triage/rescan"
)

func main() {
	trivyDir := flag.String("trivy", "", "directory of Trivy image-scan JSON reports (*.json) — required")
	epssFile := flag.String("epss", "", "EPSS response JSON (FIRST.org) — optional")
	kevFile := flag.String("kev", "", "CISA KEV catalog JSON — optional")
	existingFile := flag.String("existing", "", "JSON array of already-open CVE IDs — optional")
	flag.Parse()

	if *trivyDir == "" {
		fatal("--trivy <dir> is required")
	}

	reports, err := loadTrivy(*trivyDir)
	if err != nil {
		fatal(err.Error())
	}

	in := rescan.Inputs{
		Reports:  reports,
		EPSS:     map[string]rescan.EPSSScore{},
		KEV:      map[string]bool{},
		Existing: map[string]bool{},
	}
	if *epssFile != "" {
		if m, err := readInto(*epssFile, rescan.ParseEPSS); err != nil {
			warn("epss: %v (continuing without EPSS enrichment)", err)
		} else {
			in.EPSS = m
		}
	}
	if *kevFile != "" {
		if m, err := readInto(*kevFile, rescan.ParseKEV); err != nil {
			warn("kev: %v (continuing without KEV enrichment)", err)
		} else {
			in.KEV = m
		}
	}
	if *existingFile != "" {
		if m, err := readInto(*existingFile, rescan.ParseExisting); err != nil {
			warn("existing: %v (continuing without dedup)", err)
		} else {
			in.Existing = m
		}
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(rescan.BuildIssues(in)); err != nil {
		fatal(err.Error())
	}
}

// loadTrivy parses every *.json in dir as a Trivy report. A file that fails to
// parse is skipped with a warning rather than aborting the whole rescan.
func loadTrivy(dir string) ([]rescan.TrivyReport, error) {
	matches, err := filepath.Glob(filepath.Join(dir, "*.json"))
	if err != nil {
		return nil, err
	}
	var reports []rescan.TrivyReport
	for _, f := range matches {
		data, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		r, err := rescan.ParseTrivy(data)
		if err != nil {
			warn("skipping %s: %v", f, err)
			continue
		}
		reports = append(reports, r)
	}
	return reports, nil
}

func readInto[T any](path string, parse func([]byte) (T, error)) (T, error) {
	var zero T
	data, err := os.ReadFile(path)
	if err != nil {
		return zero, err
	}
	return parse(data)
}

func warn(format string, a ...any) { fmt.Fprintf(os.Stderr, "rescan-report: "+format+"\n", a...) }

func fatal(msg string) {
	fmt.Fprintln(os.Stderr, "rescan-report: "+msg)
	os.Exit(1)
}
