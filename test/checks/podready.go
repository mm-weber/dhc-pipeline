package checks

import corev1 "k8s.io/api/core/v1"

// PodReady reports whether pod has a Ready condition set to True.
func PodReady(pod *corev1.Pod) bool {
	for _, c := range pod.Status.Conditions {
		if c.Type == corev1.PodReady && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}
