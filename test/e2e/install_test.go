package e2e

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/mm-weber/dhc-pipeline/test/harness"
	"github.com/mm-weber/dhc-pipeline/test/install"
)

// repoRoot resolves the catalogue root from this test file's location
// (test/e2e/ -> ../..), so chart paths work regardless of the test's cwd.
func repoRoot() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(file), "..", "..")
}

// deploySpec turns a componentSpec into an install.Spec for the given helm verb.
// version (non-empty only on the upgrade path) overrides the adapted chart's
// pinned version so the suite can install an older revision then upgrade to the
// proposed one (Req 5.6). Owned and adapted charts deploy the same two ways
// render-chart.sh renders them.
func deploySpec(verb string, s componentSpec, version string) (install.Spec, error) {
	c := s.Component
	spec := install.Spec{
		Verb:       verb,
		Release:    c.Release,
		Namespace:  c.Namespace,
		Kubeconfig: cfg.KubeconfigFile(),
		Owned:      c.Owned,
		Version:    version,
		Extra:      s.ExtraArgs,
	}
	if c.Owned {
		spec.ChartPath = filepath.Join(repoRoot(), c.ChartDir)
		return spec, nil
	}
	b, err := os.ReadFile(filepath.Join(repoRoot(), c.ChartDir, "chart.yaml"))
	if err != nil {
		return install.Spec{}, err
	}
	p, err := install.ParsePin(b)
	if err != nil {
		return install.Spec{}, fmt.Errorf("%s/chart.yaml: %w", c.ChartDir, err)
	}
	spec.Pin = p
	spec.ValuesFile = filepath.Join(repoRoot(), c.ChartDir, "config", "values-hardened.yaml")
	return spec, nil
}

// helmDeploy runs `helm <verb>` for a component, building the argv with the
// unit-tested install package. Errors carry helm's combined output so a failed
// deploy is diagnosable from the CI log.
func helmDeploy(ctx context.Context, verb string, s componentSpec, version string) error {
	spec, err := deploySpec(verb, s, version)
	if err != nil {
		return err
	}
	out, err := exec.CommandContext(ctx, "helm", install.Args(spec)...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("helm %s %s: %w\n%s", verb, s.Name, err, out)
	}
	return nil
}

// helmInstall installs a component's chart at its pinned version.
func helmInstall(ctx context.Context, s componentSpec) error {
	return helmDeploy(ctx, "install", s, "")
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
