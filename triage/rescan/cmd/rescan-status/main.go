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
//	  --support '{"supported_set": "...", "superseded": "..."}' \
//	  [--kev f] [--previous metrics.json | --previous-body issue.md] [--today YYYY-MM-DD] [--run url] \
//	  [--definitions definitions.tsv --admission verify-catalogue.json --expiries accepted-risk.txt --out-html index.html] \
//	  [--source-url <server>/<owner>/<repo>/blob/<ref> --statements triage/vex] \
//	  --out-json metrics.json --out-body issue.md
//
// --support is the support statement as scripts/triage-policy.sh prints it
// (Req 6.49); the issue publishes it beside the clocks it scopes (review D7).
// --out-html renders the catalogue page from the same data (Req 6.61; task
// 15.8): --definitions lists the definitions (the status step derives it
// through definition-lib.sh), --admission adds the verification policy's
// verdict per digest to the data and the page, --expiries the exception
// lint's lapsing entries to the page. Each finding's decision as attested
// (Req 6.47 as amended; task 15.9) rides in the data as `attested`, read
// from the statement its clock came from; --source-url turns the files a
// statement's notes name into links, --statements marks the hand-written
// statements on disk so their source is linked too.
// --enumeration is the rescan's enumeration.tsv (repository, tag, digest,
// platform, manifest, supported|superseded); only supported rows count.
// --reattest is the re-attest work directory: <name>__<12 hex>/out/*.openvex.json
// is the document attested today. --reports holds the supported set's scan
// reports, <name>__<12 hex>__<platform>.json, scanned with --show-suppressed.
// A document or report that does not parse is an error, not an empty input:
// a clock read from half the evidence would be wrong by construction.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/mm-weber/dhc-pipeline/triage/rescan"
	"github.com/mm-weber/dhc-pipeline/triage/rescan/cmd/internal/inputs"
)

func main() {
	enumeration := flag.String("enumeration", "", "the rescan's enumeration.tsv (required)")
	reattestDir := flag.String("reattest", "", "re-attest work directory (rescan-out/reattest) (required)")
	reportsDir := flag.String("reports", "", "supported-set scan reports (rescan-out/trivy) (required)")
	vexReports := flag.String("vex-reports", "", "the scan step's compile reports (rescan-out/vex); a digest whose VEX did not resolve counts as unscanned (optional)")
	kevFile := flag.String("kev", "", "CISA KEV catalog JSON (optional)")
	apertureFlag := flag.String("aperture", "", "decision aperture, comma-separated severities in rank order (required)")
	ceilingsFlag := flag.String("ceilings", "", "exception ceilings in days per severity, SEV=days comma-separated (required)")
	kevCeiling := flag.Int("kev-ceiling", 0, "ceiling in days for a KEV-listed finding (required)")
	previousFile := flag.String("previous", "", "previously published metrics.json (optional)")
	previousBody := flag.String("previous-body", "", "the status issue's body, the fenced JSON block is read (optional)")
	todayFlag := flag.String("today", "", "YYYY-MM-DD; default: the latest report's date, else now (UTC)")
	runURL := flag.String("run", "", "the run's URL, recorded in the data (optional)")
	revocationsFile := flag.String("revocations", "", "the revocation record as JSON, scripts/check-revocations.sh's output; its revocations list is carried into the status (optional)")
	supportFlag := flag.String("support", "", "the support statement as JSON {supported_set, superseded}, scripts/triage-policy.sh's support output; published in the issue (required)")
	definitionsFile := flag.String("definitions", "", "the definitions list for the catalogue page: name, active|inactive, repository, tags comma-joined, tab-separated (required with --out-html)")
	admissionFile := flag.String("admission", "", "scripts/verify-catalogue.sh's record; the verdict per digest joins the data and the page (optional)")
	expiriesFile := flag.String("expiries", "", "scripts/lint-accepted-risk.sh's report as the expiries step keeps it; lapsing exceptions join the page (optional)")
	outHTML := flag.String("out-html", "", "where to write the catalogue page, index.html (optional; Req 6.61)")
	sourceURL := flag.String("source-url", "", "the base the repository's files are served under (<server>/<owner>/<repo>/blob/<ref>); with it, the files a statement's notes name become links (optional; task 15.9)")
	statementsDir := flag.String("statements", "", "the hand-written statements directory (triage/vex): a <CVE>.openvex.json there is linked as the decision's source (optional; task 15.9)")
	outJSON := flag.String("out-json", "", "where to write metrics.json (required)")
	outBody := flag.String("out-body", "", "where to write the issue body (required)")
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
	var support rescan.SupportStatement
	if *supportFlag == "" {
		fatal("--support is required: the support statement is declared, never assumed (Req 6.49)")
	}
	if err := json.Unmarshal([]byte(*supportFlag), &support); err != nil {
		fatal("--support: not the JSON scripts/triage-policy.sh prints: " + err.Error())
	}
	if support.SupportedSet == "" || support.Superseded == "" {
		fatal("--support: both supported_set and superseded are required (Req 6.49)")
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

	digests, err := inputs.LoadSupported(*enumeration, *reattestDir, *reportsDir, *vexReports)
	if err != nil {
		fatal(err.Error())
	}

	in := rescan.StatusInputs{
		Run:        *runURL,
		SourceURL:  *sourceURL,
		Aperture:   strings.Split(*apertureFlag, ","),
		Ceilings:   ceilings,
		KEVCeiling: *kevCeiling,
		KEV:        map[string]bool{},
		Digests:    digests,
	}
	if *statementsDir != "" {
		files, err := filepath.Glob(filepath.Join(*statementsDir, "*.openvex.json"))
		if err != nil {
			fatal("statements: " + err.Error())
		}
		in.HandStatements = map[string]bool{}
		for _, f := range files {
			in.HandStatements[strings.TrimSuffix(filepath.Base(f), ".openvex.json")] = true
		}
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
	status.Support = &support
	if status.SupersededTags, err = inputs.CountSuperseded(*enumeration); err != nil {
		fatal(err.Error())
	}
	if *admissionFile != "" {
		admitted, err := inputs.LoadAdmission(*admissionFile)
		if err != nil {
			fatal("admission: " + err.Error())
		}
		for i := range status.Repositories {
			for j := range status.Repositories[i].Digests {
				d := &status.Repositories[i].Digests[j]
				if v, ok := admitted[status.Repositories[i].Repository+"@"+d.Digest]; ok {
					v := v
					d.Admitted = &v
				}
			}
		}
	}
	if *revocationsFile != "" {
		data, err := os.ReadFile(*revocationsFile)
		if err != nil {
			fatal(fmt.Sprintf("read %s: %v", *revocationsFile, err))
		}
		var record struct {
			Revocations []rescan.Revocation `json:"revocations"`
		}
		if err := json.Unmarshal(data, &record); err != nil {
			fatal(fmt.Sprintf("parse %s: %v", *revocationsFile, err))
		}
		status.Revocations = record.Revocations
	}
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
	if *outHTML != "" {
		if *definitionsFile == "" {
			fatal("--out-html needs --definitions: the page is one card per definition (Req 6.61)")
		}
		defs, err := inputs.LoadDefinitions(*definitionsFile)
		if err != nil {
			fatal("definitions: " + err.Error())
		}
		var expiries []rescan.Expiry
		if *expiriesFile != "" {
			if expiries, err = inputs.LoadExpiries(*expiriesFile); err != nil {
				fatal("expiries: " + err.Error())
			}
		}
		page := rescan.RenderCataloguePage(rescan.BuildPage(status, defs, expiries))
		if err := os.WriteFile(*outHTML, []byte(page), 0o644); err != nil {
			fatal(err.Error())
		}
	}
	ag := status.Aggregates
	fmt.Printf("rescan-status: %d finding(s) over %d supported digest(s): %d undecided (%d over ceiling), %d decided, %d fixed\n",
		ag.Findings, len(digests), ag.Undecided, ag.OverCeiling, ag.Decided, ag.Fixed)
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

func warn(format string, a ...any) { fmt.Fprintf(os.Stderr, "rescan-status: "+format+"\n", a...) }

func fatal(msg string) {
	fmt.Fprintln(os.Stderr, "rescan-status: "+msg)
	os.Exit(1)
}
