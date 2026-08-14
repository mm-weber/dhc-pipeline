package e2e

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"github.com/mm-weber/dhc-pipeline/test/checks"
)

// assertReadyHardened waits for the component's workload rollout to complete,
// then for its pods to reach Ready within five minutes (Req 5.3), and asserts
// every live pod matches the restricted securityContext (Req 5.4). Shared by
// the install and upgrade specs. The rollout wait is what makes the upgrade
// path honest (issue #75): pod-level checks alone are satisfied by the OLD
// ReplicaSet's still-Ready pods during a rolling update, so without it a
// crash-looping bumped image sails through — every later assertion here would
// inspect and probe the pre-upgrade pods through the still-serving Service.
func assertReadyHardened(ctx context.Context, r *resources.Resources, s componentSpec) {
	GinkgoHelper()
	By("workload rollout completes — no pod of a previous revision remains")
	Expect(checks.WaitRolloutComplete(ctx, r, s.Selector, checks.ReadyTimeout)).To(Succeed())

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
