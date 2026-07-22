package e2e

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"sigs.k8s.io/e2e-framework/pkg/env"
	"sigs.k8s.io/e2e-framework/pkg/envconf"
	"sigs.k8s.io/e2e-framework/pkg/envfuncs"
	"sigs.k8s.io/e2e-framework/support/kind"

	"github.com/mm-weber/dhc-pipeline/test/checks"
	"github.com/mm-weber/dhc-pipeline/test/harness"
)

// chartFlag selects which catalogue component this run provisions and exercises,
// matching the design entrypoint: `go test ./test/e2e/... -args --chart <name>`.
// CI (task 6.5) runs one component per kind cluster so failures are isolated.
var chartFlag string

func init() {
	flag.StringVar(&chartFlag, "chart", "",
		"catalogue component to install on kind (cert-manager|grafana|hardened-app)")
}

// testenv is the e2e-framework environment provisioned in TestMain and shared by
// the Ginkgo specs added in task 6.3 (install + functional probes). The shared
// assertions those specs call — readiness (checks.WaitReady) and restricted
// securityContext (checks.RestrictedViolations) — landed in task 6.2.
var testenv env.Environment

// cfg is the environment config testenv is built from; the kind provisioning
// funcs populate its kubeconfig, so the diagnostics hook can reach the cluster
// client after a spec fails.
var cfg *envconf.Config

// selected is the component chartFlag resolved to; specs read it to know which
// chart to install and which functional probe to run.
var selected harness.Component

// TestMain provisions the cluster the Ginkgo specs run against, then hands off.
// Provisioning is gated on DHC_E2E=1 (set by the e2e.yml workflow, task 6.5);
// without it the suite runs cluster-free so `go test ./...` and the unit layer
// stay fast and Docker-free. Two cluster modes:
//   - E2E_KUBECONFIG set (CI): attach to the kind cluster the workflow already
//     created and loaded the private images into; the suite only creates the
//     component namespace and never tears the cluster down (the workflow owns it).
//   - otherwise (local): create and destroy an ephemeral kind cluster.
func TestMain(m *testing.M) {
	flag.Parse()

	if os.Getenv("DHC_E2E") != "1" {
		fmt.Fprintln(os.Stderr, "e2e: DHC_E2E!=1 — skipping kind provisioning (bootstrap no-op)")
		os.Exit(m.Run())
	}

	comp, err := harness.Lookup(chartFlag)
	if err != nil {
		fmt.Fprintf(os.Stderr, "e2e: %v — pass -chart with a known component\n", err)
		os.Exit(1)
	}
	selected = comp

	if kubeconfig := os.Getenv("E2E_KUBECONFIG"); kubeconfig != "" {
		// CI: the workflow owns the cluster and has already loaded the images.
		cfg = envconf.NewWithKubeConfig(kubeconfig)
		testenv = env.NewWithConfig(cfg)
		testenv.Setup(envfuncs.CreateNamespace(comp.Namespace))
	} else {
		// Local: create an ephemeral kind cluster and tear it down after.
		clusterName := harness.ClusterName("dhc-e2e-" + comp.Name)
		provider := kind.NewProvider()
		if img := os.Getenv("KIND_NODE_IMAGE"); img != "" {
			kind.WithImage(img)(provider)
		}
		cfg = envconf.New()
		testenv = env.NewWithConfig(cfg)
		testenv.Setup(
			envfuncs.CreateCluster(provider, clusterName),
			envfuncs.CreateNamespace(comp.Namespace),
		)
		testenv.Finish(envfuncs.DestroyCluster(clusterName))
	}
	os.Exit(testenv.Run(m))
}

// TestE2E is the Ginkgo v2 entrypoint; Gomega is wired via RegisterFailHandler.
func TestE2E(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "dhc-pipeline e2e suite")
}

// ReportAfterEach preserves cluster diagnostics whenever a spec fails (Req 5.7):
// the selected component's pods, events, and deployments are written under
// checks.ArtifactsDir() for the e2e workflow (task 6.5) to upload. No-op unless a
// cluster was provisioned (cfg is nil in the DHC_E2E!=1 bootstrap path).
var _ = ReportAfterEach(func(report SpecReport) {
	if !report.Failed() || cfg == nil {
		return
	}
	outDir := filepath.Join(checks.ArtifactsDir(), selected.Name)
	r := cfg.Client().Resources(selected.Namespace)
	if err := checks.DumpDiagnostics(context.Background(), r, selected.Namespace, outDir); err != nil {
		GinkgoWriter.Printf("diagnostics dump for %s failed: %v\n", selected.Name, err)
		return
	}
	GinkgoWriter.Printf("diagnostics for %s written to %s\n", selected.Name, outDir)
})
