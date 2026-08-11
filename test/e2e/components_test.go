package e2e

import (
	"os"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/mm-weber/dhc-pipeline/test/harness"
)

// componentSpec is a per-component e2e case: the catalogue Component plus the
// pod selector + replica count readiness waits on, any extra install args, and
// the functional probe (Req 5.5).
type componentSpec struct {
	harness.Component
	Selector  string
	Replicas  int
	ExtraArgs []string
	Probe     probeFunc
}

// componentSpecs are the four components that have a hardened chart.
var componentSpecs = []componentSpec{
	{
		Component: component("cert-manager"),
		Selector:  "app.kubernetes.io/instance=cert-manager",
		Replicas:  3,
		// The chart ships CRDs off by default; the issuance probe needs them.
		ExtraArgs: []string{"--set", "crds.enabled=true"},
		Probe:     probeCertManager,
	},
	{
		Component: component("grafana"),
		Selector:  "app.kubernetes.io/instance=grafana",
		Replicas:  1,
		Probe:     httpProbe("/api/health"),
	},
	{
		Component: component("hardened-app"),
		Selector:  "app.kubernetes.io/instance=hardened-app",
		Replicas:  1,
		Probe:     httpProbe("/healthz"),
	},
	{
		Component: component("valkey"),
		Selector:  "app.kubernetes.io/instance=valkey",
		Replicas:  1,
		Probe:     probeValkey,
	},
}

var _ = Describe("hardened catalogue component on kind", func() {
	for _, s := range componentSpecs {
		s := s
		Context(s.Name, func() {
			BeforeEach(func() {
				if cfg == nil {
					Skip("requires a kind cluster (set DHC_E2E=1 and -chart=" + s.Name + ")")
				}
				if selected.Name != s.Name {
					Skip("this run targets -chart=" + selected.Name)
				}
				if os.Getenv("DHC_UPGRADE_FROM") != "" {
					Skip("bump PR — the upgrade-path spec installs and upgrades instead")
				}
			})

			It("installs, reaches Ready, matches the restricted securityContext, and passes its probe", func(ctx SpecContext) {
				r := cfg.Client().Resources(s.Namespace)

				By("helm install of the hardened chart")
				Expect(helmInstall(ctx, s)).To(Succeed())

				assertHealthy(ctx, r, s)
			})
		})
	}
})
