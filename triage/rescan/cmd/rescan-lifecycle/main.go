// Command rescan-lifecycle decides, on today's evidence, which cve issues
// close and with which graded label, and which closed ones reopen (task
// 10.6; Req 6.52 to 6.57). Glue around the tested rescan package: read the
// issues gh listed, the supported set's reports, the verified SBOMs, the
// scanner version and the VEX sources; call Lifecycle; write the actions.
// The gh calls that apply them live in rescan.yml.
//
// Usage:
//
//	rescan-lifecycle --enumeration <tsv> --reports <dir> --sboms <dir> --issues <json> \
//	  --aperture CRITICAL,HIGH [--scanner trivy-version.json] [--vex-dir triage/vex] --out actions.json
//
// --issues is `gh issue list --state all --label cve --json number,state,body,labels`.
// --sboms holds fetch-sboms.sh's output, sha256-<manifest hex>.cdx.json.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mm-weber/dhc-pipeline/triage/rescan"
	"github.com/mm-weber/dhc-pipeline/triage/rescan/cmd/internal/inputs"
)

func main() {
	enumeration := flag.String("enumeration", "", "the rescan's enumeration.tsv (required)")
	reportsDir := flag.String("reports", "", "supported-set scan reports (rescan-out/trivy) (required)")
	sbomsDir := flag.String("sboms", "", "verified CycloneDX SBOMs, sha256-<hex>.cdx.json (fetch-sboms.sh) (required)")
	issuesFile := flag.String("issues", "", "gh issue list --json number,state,body,labels (required)")
	scannerFile := flag.String("scanner", "", "trivy version --format json (required) (Req 6.52 names the versions)")
	vexDir := flag.String("vex-dir", "", "the OpenVEX source directory, to name covering statements by file (required), absolute (the binary runs under go -C)")
	vexReports := flag.String("vex-reports", "", "the scan step's compile reports (rescan-out/vex); a digest whose VEX did not resolve is evidence of nothing (optional)")
	labelsFile := flag.String("labels", "", "the policy's resolved labels, grade -> {name,...} JSON (triage-policy.sh resolved-labels) (optional)")
	apertureFlag := flag.String("aperture", "", "decision aperture, comma-separated severities in rank order (required)")
	outFile := flag.String("out", "", "where to write actions.json (required)")
	flag.Parse()
	for _, req := range []struct{ name, value string }{{"--enumeration", *enumeration}, {"--reports", *reportsDir}, {"--sboms", *sbomsDir},
		{"--issues", *issuesFile}, {"--scanner", *scannerFile}, {"--vex-dir", *vexDir}, {"--aperture", *apertureFlag}, {"--out", *outFile}} {
		if req.value == "" {
			fatal(req.name + " is required")
		}
	}

	digests, err := inputs.LoadSupported(*enumeration, "", *reportsDir, *vexReports)
	if err != nil {
		fatal(err.Error())
	}
	data, err := os.ReadFile(*issuesFile)
	if err != nil {
		fatal("issues: " + err.Error())
	}
	issues, err := rescan.ParseIssuesJSON(data)
	if err != nil {
		fatal("issues: " + err.Error())
	}
	in := rescan.LifecycleInputs{
		Aperture:   strings.Split(*apertureFlag, ","),
		Issues:     issues,
		Digests:    digests,
		SBOMs:      map[string][]rescan.SBOMComponent{},
		VEXSources: map[string][]string{},
	}
	files, _ := filepath.Glob(filepath.Join(*sbomsDir, "sha256-*.cdx.json"))
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			fatal(err.Error())
		}
		cs, err := rescan.ParseCycloneDX(data)
		if err != nil {
			fatal(fmt.Sprintf("%s: %v", f, err))
		}
		hex := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(f), "sha256-"), ".cdx.json")
		in.SBOMs["sha256:"+hex] = cs
	}
	data, err = os.ReadFile(*scannerFile)
	if err != nil {
		fatal("scanner: " + err.Error())
	}
	if in.Scanner, err = rescan.ParseScanner(data); err != nil {
		fatal("scanner: " + err.Error())
	}
	if *labelsFile != "" {
		data, err := os.ReadFile(*labelsFile)
		if err != nil {
			fatal("labels: " + err.Error())
		}
		var declared map[string]struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(data, &declared); err != nil {
			fatal("labels: " + err.Error())
		}
		in.Labels = map[string]string{}
		for grade, l := range declared {
			in.Labels[grade] = l.Name
		}
	}
	sources, _ := filepath.Glob(filepath.Join(*vexDir, "*.json"))
	if len(sources) == 0 {
		warn("no OpenVEX source under %s: covering statements will be named by the applied document only", *vexDir)
	}
	for _, f := range sources {
		data, err := os.ReadFile(f)
		if err != nil {
			warn("%s: %v (not named as a source)", f, err)
			continue
		}
		doc, err := rescan.ParseVEX(data)
		if err != nil {
			warn("%s: %v (not named as a source)", f, err)
			continue
		}
		seen := map[string]bool{}
		for _, st := range doc.Statements {
			if id := st.Vulnerability.Name; id != "" && !seen[id] {
				seen[id] = true
				in.VEXSources[id] = append(in.VEXSources[id], f)
			}
		}
	}

	actions := rescan.Lifecycle(in)
	out, err := json.MarshalIndent(actions, "", "  ")
	if err != nil {
		fatal(err.Error())
	}
	if err := os.WriteFile(*outFile, append(out, '\n'), 0o644); err != nil {
		fatal(err.Error())
	}
	fmt.Printf("rescan-lifecycle: %d issue(s) examined over %d supported digest(s), %d SBOM(s): close %d, reopen %d, keep %d\n",
		len(issues), len(digests), len(in.SBOMs), len(actions.Close), len(actions.Reopen), len(actions.Kept))
}

func warn(format string, a ...any) { fmt.Fprintf(os.Stderr, "rescan-lifecycle: "+format+"\n", a...) }

func fatal(msg string) {
	fmt.Fprintln(os.Stderr, "rescan-lifecycle: "+msg)
	os.Exit(1)
}
