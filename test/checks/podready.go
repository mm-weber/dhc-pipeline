package checks

import corev1 "k8s.io/api/core/v1"

// PodReady reports whether pod has a Ready condition set to True.
// (stub — GREEN implements)
func PodReady(pod *corev1.Pod) bool { return false }
