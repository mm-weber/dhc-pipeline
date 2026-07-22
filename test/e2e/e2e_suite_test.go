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

// TestMain provisions an ephemeral kind cluster for the selected component, then
// hands off to the Ginkgo specs. Provisioning is gated on DHC_E2E=1 (set by the
// e2e.yml workflow, task 6.5); without it the suite runs cluster-free so
// `go test ./...` and the unit layer stay fast and Docker-free.
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

	clusterName := harness.ClusterName("dhc-e2e-" + comp.Name)
	provider := kind.NewProvider()
	if img := os.Getenv("KIND_NODE_IMAGE"); img != "" {
		// Pin the node image from CI (task 6.5) so kind never floats a tag.
		kind.WithImage(img)(provider)
	}

	cfg = envconf.New()
	testenv = env.NewWithConfig(cfg)
	testenv.Setup(
		envfuncs.CreateCluster(provider, clusterName),
		envfuncs.CreateNamespace(comp.Namespace),
	)
	testenv.Finish(
		envfuncs.DestroyCluster(clusterName),
	)
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

var _ = Describe("hardened catalogue component on kind", func() {
	// The per-component specs land in task 6.3: each installs its chart, waits
	// Ready via checks.WaitReady, asserts checks.RestrictedViolations is empty on
	// the live pods, then runs its functional probe (cert-manager issues a
	// Certificate, grafana answers HTTP health, valkey serves SET/GET,
	// hardened-app returns HTTP 200). Pending until then so bootstrap CI is green
	// without a cluster.
	PIt("reaches Ready and matches the restricted securityContext", func() {
		Expect(selected.Name).NotTo(BeEmpty())
	})
})
