package checks

import (
	"testing"

	corev1 "k8s.io/api/core/v1"
)

// TestPodReady exercises the Ready-condition predicate across the states the
// e2e readiness gate depends on (Req 5.3).
func TestPodReady(t *testing.T) {
	cases := []struct {
		name       string
		conditions []corev1.PodCondition
		want       bool
	}{
		{
			name:       "ready true",
			conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}},
			want:       true,
		},
		{
			name:       "ready false",
			conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionFalse}},
			want:       false,
		},
		{
			name:       "no conditions",
			conditions: nil,
			want:       false,
		},
		{
			name: "ready true among others",
			conditions: []corev1.PodCondition{
				{Type: corev1.PodInitialized, Status: corev1.ConditionTrue},
				{Type: corev1.ContainersReady, Status: corev1.ConditionTrue},
				{Type: corev1.PodReady, Status: corev1.ConditionTrue},
			},
			want: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pod := &corev1.Pod{}
			pod.Status.Conditions = tc.conditions
			if got := PodReady(pod); got != tc.want {
				t.Errorf("PodReady() = %v, want %v", got, tc.want)
			}
		})
	}
}
