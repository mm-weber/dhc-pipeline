package checks

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/klient/wait"
)

// DeploymentRolledOut reports whether d's current pod template has fully
// replaced its predecessors: the controller has observed the current
// generation, every desired replica is updated AND available, and no replica
// of an older revision remains. This is `kubectl rollout status`'s completion
// rule. An at-least-N Ready-pod count cannot stand in for it — during a
// rolling update the OLD ReplicaSet's pods are still Ready and still backing
// the Service, so a crash-looping new revision passes every pod-level check
// while the rollout never finishes (issue #75).
func DeploymentRolledOut(d *appsv1.Deployment) bool {
	if d.Status.ObservedGeneration < d.Generation {
		return false
	}
	want := int32(1)
	if d.Spec.Replicas != nil {
		want = *d.Spec.Replicas
	}
	return d.Status.UpdatedReplicas == want &&
		d.Status.AvailableReplicas == want &&
		d.Status.Replicas == want
}

// StatefulSetRolledOut is the StatefulSet counterpart: generation observed,
// every desired replica updated and Ready, and the current revision caught up
// with the update revision — the controller's own statement that no pod from
// the previous template remains.
func StatefulSetRolledOut(s *appsv1.StatefulSet) bool {
	if s.Status.ObservedGeneration < s.Generation {
		return false
	}
	want := int32(1)
	if s.Spec.Replicas != nil {
		want = *s.Spec.Replicas
	}
	return s.Status.UpdatedReplicas == want &&
		s.Status.ReadyReplicas == want &&
		s.Status.CurrentRevision == s.Status.UpdateRevision
}

// WaitRolloutComplete blocks until every Deployment and StatefulSet matching
// labelSelector in r's namespace satisfies its RolledOut predicate, or timeout
// elapses. At least one workload must match: zero matches stay pending rather
// than passing vacuously, so a selector typo cannot green the gate. Same
// poll-and-retry shape as WaitReady — transient List errors retry until the
// deadline, and the pure predicates carry the logic the unit tests cover.
func WaitRolloutComplete(ctx context.Context, r *resources.Resources, labelSelector string, timeout time.Duration) error {
	var listOpts []resources.ListOption
	if labelSelector != "" {
		listOpts = append(listOpts, resources.WithLabelSelector(labelSelector))
	}
	var lastState string
	err := wait.For(
		func(ctx context.Context) (bool, error) {
			var deps appsv1.DeploymentList
			if err := r.List(ctx, &deps, listOpts...); err != nil {
				lastState = fmt.Sprintf("listing deployments: %v", err)
				return false, nil
			}
			var sets appsv1.StatefulSetList
			if err := r.List(ctx, &sets, listOpts...); err != nil {
				lastState = fmt.Sprintf("listing statefulsets: %v", err)
				return false, nil
			}
			if len(deps.Items)+len(sets.Items) == 0 {
				lastState = fmt.Sprintf("no Deployment or StatefulSet matches %q", labelSelector)
				return false, nil
			}
			for i := range deps.Items {
				if d := &deps.Items[i]; !DeploymentRolledOut(d) {
					lastState = fmt.Sprintf(
						"deployment %s: generation %d observed %d, %d/%d updated, %d available, %d total",
						d.Name, d.Generation, d.Status.ObservedGeneration,
						d.Status.UpdatedReplicas, ptrOr1(d.Spec.Replicas),
						d.Status.AvailableReplicas, d.Status.Replicas)
					return false, nil
				}
			}
			for i := range sets.Items {
				if s := &sets.Items[i]; !StatefulSetRolledOut(s) {
					lastState = fmt.Sprintf(
						"statefulset %s: generation %d observed %d, %d/%d updated, %d ready, revision %s -> %s",
						s.Name, s.Generation, s.Status.ObservedGeneration,
						s.Status.UpdatedReplicas, ptrOr1(s.Spec.Replicas),
						s.Status.ReadyReplicas, s.Status.CurrentRevision, s.Status.UpdateRevision)
					return false, nil
				}
			}
			return true, nil
		},
		wait.WithTimeout(timeout),
		wait.WithContext(ctx),
	)
	if err != nil {
		// wait.For's bare deadline error says nothing about WHY — carry the
		// last observed state so a red run names the stuck workload.
		return fmt.Errorf("rollout not complete: %s: %w", lastState, err)
	}
	return nil
}

func ptrOr1(p *int32) int32 {
	if p != nil {
		return *p
	}
	return 1
}
