// Package inputs reads the rescan's per-digest outputs by their naming for
// the commands that compute over the supported set (rescan-status,
// rescan-lifecycle). It is the one place that knows the layout:
// <reattest>/<name>__<12 hex>/out/*.openvex.json for the document attested
// today and <reports>/<name>__<12 hex>__<platform>.json for the scan reports.
package inputs

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/mm-weber/dhc-pipeline/triage/rescan"
)

// LoadSupported reads the enumeration and, for every supported digest, its
// platform manifests, the document (when reattestDir is given), the reports,
// and, when vexReportsDir is given, whether today's VEX compile for it
// resolved (<vexReportsDir>/<name>__<12 hex>.report.json with an empty
// digest means the scan ran without --vex). A document or report that does
// not parse is an error, not an empty input: a computation over half the
// evidence would be wrong by construction.
func LoadSupported(enumeration, reattestDir, reportsDir, vexReportsDir string) ([]rescan.SupportedDigest, error) {
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
		if !slices.Contains(d.Tags, cols[1]) {
			d.Tags = append(d.Tags, cols[1])
		}
		if !slices.Contains(d.Manifests, cols[4]) {
			d.Manifests = append(d.Manifests, cols[4])
		}
		if !slices.Contains(d.Platforms, cols[3]) {
			d.Platforms = append(d.Platforms, cols[3])
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	out := make([]rescan.SupportedDigest, 0, len(order))
	for _, k := range order {
		d := byKey[k]
		work := rescan.StatusWorkDirName(d.Repository, d.Digest)
		if reattestDir != "" {
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
		if vexReportsDir != "" {
			if data, err := os.ReadFile(filepath.Join(vexReportsDir, work+".report.json")); err == nil {
				var rep struct {
					Digest string `json:"digest"`
				}
				if err := json.Unmarshal(data, &rep); err != nil {
					return nil, fmt.Errorf("%s: %w", filepath.Join(vexReportsDir, work+".report.json"), err)
				}
				d.VEXUnresolved = rep.Digest == ""
			}
		}
		out = append(out, *d)
	}
	return out, nil
}

// The catalogue page's inputs (Req 6.61; task 15.8).

// LoadDefinitions reads the definitions list the status step derives through
// definition-lib.sh: one row per definition, name, "active" or "inactive",
// the published repository, and the declared tags comma-joined (empty for
// none), in the order the step wrote them.
func LoadDefinitions(path string) ([]rescan.Definition, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []rescan.Definition
	for i, line := range strings.Split(strings.TrimRight(string(data), "\n"), "\n") {
		if line == "" {
			continue
		}
		cols := strings.Split(line, "\t")
		if len(cols) != 4 || cols[0] == "" || cols[2] == "" {
			return nil, fmt.Errorf("%s:%d: expected name, active|inactive, repository, tags; got %q", path, i+1, line)
		}
		var active bool
		switch cols[1] {
		case "active":
			active = true
		case "inactive":
		default:
			return nil, fmt.Errorf("%s:%d: %q is neither active nor inactive", path, i+1, cols[1])
		}
		d := rescan.Definition{Name: cols[0], Active: active, Repository: cols[2]}
		if cols[3] != "" {
			d.Tags = strings.Split(cols[3], ",")
		}
		out = append(out, d)
	}
	return out, nil
}

// LoadAdmission reads scripts/verify-catalogue.sh's record: the verification
// policy's verdict per tag-referenced digest, keyed by "<repository>@<digest>";
// true for pass, false for anything else. The declared must-reject control is
// the policy's proof, not a catalogue digest, and is left out.
func LoadAdmission(path string) (map[string]bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Control   string `json:"control"`
		Resources []struct {
			Name   string `json:"name"`
			Ref    string `json:"ref"`
			Result string `json:"result"`
		} `json:"resources"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	out := map[string]bool{}
	for _, r := range doc.Resources {
		if strings.HasPrefix(r.Name, "control") || r.Ref == doc.Control {
			continue
		}
		out[r.Ref] = r.Result == "pass"
	}
	return out, nil
}

// LoadExpiries reads scripts/lint-accepted-risk.sh's report as the rescan's
// expiries step keeps it: every workflow-command line about an exception file
// that says an entry "expires in" (lapsing within the warning window) or "is
// in the past" (lapsed), attributed to the definition the file is named for.
// Other findings of the lint are not the page's to show.
func LoadExpiries(path string) ([]rescan.Expiry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []rescan.Expiry
	for _, line := range strings.Split(string(data), "\n") {
		m := expiryLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		msg := m[2]
		lapsed := strings.Contains(msg, "is in the past")
		if !lapsed && !strings.Contains(msg, "expires in") {
			continue
		}
		msg = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(msg, "risk treatment (Req 6.11):"), "risk treatment:"))
		out = append(out, rescan.Expiry{Definition: m[1], Lapsed: lapsed, Message: msg})
	}
	return out, nil
}

var expiryLine = regexp.MustCompile(`^::(?:warning|error) file=triage/accepted-risk/([^.,]+)\.yaml[^:]*::(.*)$`)

// CountSuperseded counts the catalogue tags the enumeration marked
// superseded, once per (repository, tag) whatever their platforms: the
// support statement's other half as the page prints it (task 15.8).
func CountSuperseded(enumeration string) (int, error) {
	data, err := os.ReadFile(enumeration)
	if err != nil {
		return 0, err
	}
	seen := map[string]bool{}
	for _, line := range strings.Split(string(data), "\n") {
		cols := strings.Split(line, "\t")
		if len(cols) < 6 || cols[5] != "superseded" {
			continue
		}
		seen[cols[0]+"\t"+cols[1]] = true
	}
	return len(seen), nil
}
