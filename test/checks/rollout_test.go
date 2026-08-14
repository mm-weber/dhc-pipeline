package checks

import (
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func int32p(v int32) *int32 { return &v }

// TestDeploymentRolledOut exercises the rollout-completion predicate against
// the states an upgrade passes through (issue #75): the bug it closes is a
// crash-looping new revision hiding behind the old ReplicaSet's still-Ready
// pods, which satisfy every at-least-N pod check while the rollout never
// finishes.
func TestDeploymentRolledOut(t *testing.T) {
	base := func() *appsv1.Deployment {
		return &appsv1.Deployment{
			ObjectMeta: metav1.ObjectMeta{Generation: 2},
			Spec:       appsv1.DeploymentSpec{Replicas: int32p(1)},
			Status: appsv1.DeploymentStatus{
				ObservedGeneration: 2,
				Replicas:           1,
				UpdatedReplicas:    1,
				AvailableReplicas:  1,
			},
		}
	}

	cases := []struct {
		name   string
		mutate func(*appsv1.Deployment)
		want   bool
	}{
		{"rolled out", func(d *appsv1.Deployment) {}, true},
		{
			// The controller has not seen the new template yet — every status
			// field still describes the OLD revision and must not count.
			"generation not yet observed",
			func(d *appsv1.Deployment) { d.Status.ObservedGeneration = 1 },
			false,
		},
		{
			// Mid-rollout with a crash-looping new pod: the old pod is still
			// Ready (Available=1) but nothing updated is — the issue #75 state.
			"no updated replica available",
			func(d *appsv1.Deployment) { d.Status.UpdatedReplicas = 0 },
			false,
		},
		{
			// New pod created but never Available (crash loop before Ready).
			"updated but not available",
			func(d *appsv1.Deployment) { d.Status.AvailableReplicas = 0 },
			false,
		},
		{
			// Rollout technically progressing but the old pod lingers:
			// total replicas above spec means a previous revision remains.
			"old replica still terminating",
			func(d *appsv1.Deployment) { d.Status.Replicas = 2 },
			false,
		},
		{
			// nil Spec.Replicas defaults to 1, matching the API server.
			"nil replicas defaults to one",
			func(d *appsv1.Deployment) { d.Spec.Replicas = nil },
			true,
		},
		{
			"nil replicas, nothing updated",
			func(d *appsv1.Deployment) {
				d.Spec.Replicas = nil
				d.Status.UpdatedReplicas = 0
			},
			false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := base()
			tc.mutate(d)
			if got := DeploymentRolledOut(d); got != tc.want {
				t.Errorf("DeploymentRolledOut() = %v, want %v", got, tc.want)
			}
		})
	}
}

// TestStatefulSetRolledOut covers the same contract for StatefulSets (valkey's
// workload kind): completion additionally means the current revision has
// caught up with the update revision, which is how a StatefulSet says "no pod
// from the previous template remains".
func TestStatefulSetRolledOut(t *testing.T) {
	base := func() *appsv1.StatefulSet {
		return &appsv1.StatefulSet{
			ObjectMeta: metav1.ObjectMeta{Generation: 2},
			Spec:       appsv1.StatefulSetSpec{Replicas: int32p(1)},
			Status: appsv1.StatefulSetStatus{
				ObservedGeneration: 2,
				Replicas:           1,
				UpdatedReplicas:    1,
				ReadyReplicas:      1,
				CurrentRevision:    "web-2",
				UpdateRevision:     "web-2",
			},
		}
	}

	cases := []struct {
		name   string
		mutate func(*appsv1.StatefulSet)
		want   bool
	}{
		{"rolled out", func(s *appsv1.StatefulSet) {}, true},
		{
			"generation not yet observed",
			func(s *appsv1.StatefulSet) { s.Status.ObservedGeneration = 1 },
			false,
		},
		{
			"no updated replica",
			func(s *appsv1.StatefulSet) { s.Status.UpdatedReplicas = 0 },
			false,
		},
		{
			"updated but not ready",
			func(s *appsv1.StatefulSet) { s.Status.ReadyReplicas = 0 },
			false,
		},
		{
			// Old revision still current: the update never completed even
			// though counts look right (partition or stalled rolling update).
			"revision not caught up",
			func(s *appsv1.StatefulSet) { s.Status.CurrentRevision = "web-1" },
			false,
		},
		{
			"nil replicas defaults to one",
			func(s *appsv1.StatefulSet) { s.Spec.Replicas = nil },
			true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := base()
			tc.mutate(s)
			if got := StatefulSetRolledOut(s); got != tc.want {
				t.Errorf("StatefulSetRolledOut() = %v, want %v", got, tc.want)
			}
		})
	}
}
