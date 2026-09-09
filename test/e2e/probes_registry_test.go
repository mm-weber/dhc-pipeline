package e2e

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mm-weber/dhc-pipeline/test/install"
)

// TestProbeDeclarations holds the chart declarations and the probes registry
// equal in both directions (task 14.3, Req 5.5, 5.8), the same discipline the
// Renovate manager fixtures follow: every probe a chart declares has a
// registration, so the suite can never skip a declared probe by name, and
// every registration is declared by some chart, so no probe rots unused.
// Runs cluster-free (plain testing, no Ginkgo), in validate's go job.
func TestProbeDeclarations(t *testing.T) {
	charts, err := filepath.Glob(filepath.Join(repoRoot(), "chart", "*", "chart.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if len(charts) == 0 {
		t.Fatal("no chart/*/chart.yaml found; the glob or the repo root is wrong")
	}
	declared := map[string][]string{}
	for _, f := range charts {
		rel, _ := filepath.Rel(repoRoot(), f)
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		d, err := install.ParseDeclaration(b)
		if err != nil {
			t.Errorf("%s: %v", rel, err)
			continue
		}
		if d.Probe == "" {
			// Allowed by this reader; whether an active definition may go
			// without a probe is scripts/lint-probes.sh's question (Req 5.8).
			continue
		}
		if _, ok := probes[d.Probe]; !ok {
			t.Errorf("%s declares probe %q, but test/e2e registers no probe under that name", rel, d.Probe)
		}
		declared[d.Probe] = append(declared[d.Probe], rel)
	}
	for name := range probes {
		if len(declared[name]) == 0 {
			t.Errorf("probe %q is registered in test/e2e but no chart/*/chart.yaml declares it", name)
		}
	}
}
