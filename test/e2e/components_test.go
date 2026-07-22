package e2e

import (
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/mm-weber/dhc-pipeline/test/checks"
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

// componentSpecs are the three components that currently have a hardened chart.
// valkey's SET/GET probe waits on its chart (task 8.1); harness.Lookup already
// errors on it, documenting the gap.
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
			})

			It("installs, reaches Ready, matches the restricted securityContext, and passes its probe", func(ctx SpecContext) {
				r := cfg.Client().Resources(s.Namespace)

				By("helm install of the hardened chart")
				Expect(helmInstall(ctx, s)).To(Succeed())

				By("workload pods reach Ready within five minutes")
				Expect(checks.WaitReady(ctx, r, s.Selector, s.Replicas, checks.ReadyTimeout)).To(Succeed())

				By("every live pod matches the restricted securityContext")
				var pods corev1.PodList
				Expect(r.List(ctx, &pods, resources.WithLabelSelector(s.Selector))).To(Succeed())
				Expect(pods.Items).NotTo(BeEmpty())
				for i := range pods.Items {
					Expect(checks.RestrictedViolations(&pods.Items[i])).To(
						BeEmpty(), "pod %s violates the restricted profile", pods.Items[i].Name)
				}

				By("functional probe")
				Expect(s.Probe(ctx, r, s.Component)).To(Succeed())
			})
		})
	}
})
