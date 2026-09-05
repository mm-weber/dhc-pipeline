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
	enumeration := flag.String("enumeration", "", "the rescan's enumeration.tsv — required")
	reportsDir := flag.String("reports", "", "supported-set scan reports (rescan-out/trivy) — required")
	sbomsDir := flag.String("sboms", "", "verified CycloneDX SBOMs, sha256-<hex>.cdx.json (fetch-sboms.sh) — required")
	issuesFile := flag.String("issues", "", "gh issue list --json number,state,body,labels — required")
	scannerFile := flag.String("scanner", "", "trivy version --format json — optional")
	vexDir := flag.String("vex-dir", "triage/vex", "the OpenVEX source directory, to name covering statements by file")
	apertureFlag := flag.String("aperture", "", "decision aperture, comma-separated severities in rank order — required")
	outFile := flag.String("out", "", "where to write actions.json — required")
	flag.Parse()
	for name, v := range map[string]string{"--enumeration": *enumeration, "--reports": *reportsDir, "--sboms": *sbomsDir,
		"--issues": *issuesFile, "--aperture": *apertureFlag, "--out": *outFile} {
		if v == "" {
			fatal(name + " is required")
		}
	}

	digests, err := inputs.LoadSupported(*enumeration, "", *reportsDir)
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
	if *scannerFile != "" {
		if data, err := os.ReadFile(*scannerFile); err != nil {
			warn("scanner: %v (versions will read as unknown)", err)
		} else if s, err := rescan.ParseScanner(data); err != nil {
			warn("scanner: %v (versions will read as unknown)", err)
		} else {
			in.Scanner = s
		}
	}
	sources, _ := filepath.Glob(filepath.Join(*vexDir, "*.json"))
	for _, f := range sources {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		doc, err := rescan.ParseVEX(data)
		if err != nil {
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
