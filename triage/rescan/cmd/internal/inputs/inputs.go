// Package inputs reads the rescan's per-digest outputs by their naming for
// the commands that compute over the supported set (rescan-status,
// rescan-lifecycle). It is the one place that knows the layout:
// <reattest>/<name>__<12 hex>/out/*.openvex.json for the document attested
// today and <reports>/<name>__<12 hex>__<platform>.json for the scan reports.
package inputs

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/mm-weber/dhc-pipeline/triage/rescan"
)

// LoadSupported reads the enumeration and, for every supported digest, the
// document (when reattestDir is given) and the reports. A document or report
// that does not parse is an error, not an empty input: a computation over
// half the evidence would be wrong by construction.
func LoadSupported(enumeration, reattestDir, reportsDir string) ([]rescan.SupportedDigest, error) {
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
		out = append(out, *d)
	}
	return out, nil
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}
