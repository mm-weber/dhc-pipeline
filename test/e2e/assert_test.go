package e2e

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/mm-weber/dhc-pipeline/test/checks"
)

// assertReadyHardened waits for the component's workload pods to reach Ready
// within five minutes (Req 5.3) and asserts every live pod matches the
// restricted securityContext (Req 5.4). Shared by the install and upgrade specs.
func assertReadyHardened(ctx context.Context, r *resources.Resources, s componentSpec) {
	GinkgoHelper()
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
}

// assertHealthy is assertReadyHardened plus the component's functional probe (Req 5.5).
func assertHealthy(ctx context.Context, r *resources.Resources, s componentSpec) {
	GinkgoHelper()
	assertReadyHardened(ctx, r, s)
	By("functional probe")
	Expect(s.Probe(ctx, r, s.Component)).To(Succeed())
}
