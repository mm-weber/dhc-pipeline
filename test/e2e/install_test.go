package e2e

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"sigs.k8s.io/yaml"

	"github.com/mm-weber/dhc-pipeline/test/harness"
)

// repoRoot resolves the catalogue root from this test file's location
// (test/e2e/ -> ../..), so chart paths work regardless of the test's cwd.
func repoRoot() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(file), "..", "..")
}

// pin mirrors the adapted chart's chart.yaml `upstream:` block (Req 4.1): the
// pinned upstream chart the e2e install renders live, exactly as render-chart.sh
// and the kyverno gate do.
type pin struct {
	Name       string `json:"name"`
	Repository string `json:"repository"`
	Version    string `json:"version"`
}

// readPin loads the upstream pin from an adapted chart directory.
func readPin(chartDir string) (pin, error) {
	b, err := os.ReadFile(filepath.Join(repoRoot(), chartDir, "chart.yaml"))
	if err != nil {
		return pin{}, err
	}
	var doc struct {
		Upstream pin `json:"upstream"`
	}
	if err := yaml.Unmarshal(b, &doc); err != nil {
		return pin{}, fmt.Errorf("parse %s/chart.yaml: %w", chartDir, err)
	}
	if doc.Upstream.Name == "" || doc.Upstream.Repository == "" || doc.Upstream.Version == "" {
		return pin{}, fmt.Errorf("%s/chart.yaml: incomplete upstream pin %+v", chartDir, doc.Upstream)
	}
	return doc.Upstream, nil
}

// helmInstall installs a component's chart onto the kind cluster the same two
// ways render-chart.sh renders it: an owned chart from its local directory, an
// adapted chart from its pinned upstream (--repo/--version) with the hardened
// values overlay as the only change. Extra --set args (e.g. cert-manager CRDs)
// are appended. Errors carry helm's combined output so a failed install is
// diagnosable from the CI log.
func helmInstall(ctx context.Context, spec componentSpec) error {
	c := spec.Component
	args := []string{"install", c.Release}
	if c.Owned {
		args = append(args, filepath.Join(repoRoot(), c.ChartDir))
	} else {
		p, err := readPin(c.ChartDir)
		if err != nil {
			return err
		}
		values := filepath.Join(repoRoot(), c.ChartDir, "config", "values-hardened.yaml")
		args = append(args, p.Name, "--repo", p.Repository, "--version", p.Version, "-f", values)
	}
	args = append(args,
		"--namespace", c.Namespace, "--create-namespace",
		"--kubeconfig", cfg.KubeconfigFile(),
	)
	args = append(args, spec.ExtraArgs...)

	out, err := exec.CommandContext(ctx, "helm", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("helm install %s: %w\n%s", c.Name, err, out)
	}
	return nil
}

// component looks a registry entry up or dies at suite build — the registry is
// static, so an unknown name is a programming error, not a runtime condition.
func component(name string) harness.Component {
	c, err := harness.Lookup(name)
	if err != nil {
		panic(err)
	}
	return c
}
