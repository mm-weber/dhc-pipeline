package checks

import (
	"context"
	"time"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/klient/wait"
	"sigs.k8s.io/e2e-framework/klient/wait/conditions"
)

// ReadyTimeout is the deadline for a component's pods to become Ready
// (Req 5.3: workload pods reach Ready within five minutes).
const ReadyTimeout = 5 * time.Minute

// WaitReady blocks until at least count pods matching labelSelector in r's
// namespace report Ready, or timeout elapses. It drives e2e-framework's poll
// loop with the same pure PodReady predicate the unit tests cover, so the
// readiness rule enforced live is exactly the one asserted in isolation. An
// empty labelSelector matches every pod in the namespace.
func WaitReady(ctx context.Context, r *resources.Resources, labelSelector string, count int, timeout time.Duration) error {
	var listOpts []resources.ListOption
	if labelSelector != "" {
		listOpts = append(listOpts, resources.WithLabelSelector(labelSelector))
	}
	var pods corev1.PodList
	return wait.For(
		conditions.New(r).ResourceListMatchN(&pods, count, func(o k8s.Object) bool {
			p, ok := o.(*corev1.Pod)
			return ok && PodReady(p)
		}, listOpts...),
		wait.WithTimeout(timeout),
		wait.WithContext(ctx),
	)
}
