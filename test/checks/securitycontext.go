// Package checks holds the pure assertion predicates the e2e specs build on:
// small, dependency-free functions over corev1 objects (no cluster access) so
// the hardening claims are unit-testable in isolation before the kind suite.
package checks

import (
	"fmt"

	corev1 "k8s.io/api/core/v1"
)

// The restricted profile the catalogue pins (Req 5.4 / 4.3).
const (
	RestrictedUID int64 = 65532
	RestrictedGID int64 = 65532
)

// RestrictedViolations reports how pod deviates from the restricted
// securityContext profile; empty means compliant. Every app and init container
// is evaluated: the inheritable fields (runAsNonRoot / runAsUser / runAsGroup /
// seccompProfile) use the effective value (container over pod), while the
// container-only fields (readOnlyRootFilesystem / allowPrivilegeEscalation /
// capabilities) are checked directly.
func RestrictedViolations(pod *corev1.Pod) []string {
	var violations []string
	psc := pod.Spec.SecurityContext
	for i := range pod.Spec.Containers {
		violations = append(violations, containerViolations(pod.Spec.Containers[i], "container", psc)...)
	}
	for i := range pod.Spec.InitContainers {
		violations = append(violations, containerViolations(pod.Spec.InitContainers[i], "initContainer", psc)...)
	}
	return violations
}

// containerViolations lists the restricted-profile deviations for a single
// container. kind ("container"/"initContainer") is woven into each message so
// callers can tell app containers from init containers.
func containerViolations(c corev1.Container, kind string, psc *corev1.PodSecurityContext) []string {
	sc := c.SecurityContext
	if sc == nil {
		sc = &corev1.SecurityContext{}
	}
	if psc == nil {
		psc = &corev1.PodSecurityContext{}
	}
	label := fmt.Sprintf("%s %q", kind, c.Name)

	var vs []string
	if b := effective(sc.RunAsNonRoot, psc.RunAsNonRoot); b == nil || !*b {
		vs = append(vs, label+": runAsNonRoot must be true")
	}
	if u := effective(sc.RunAsUser, psc.RunAsUser); u == nil || *u != RestrictedUID {
		vs = append(vs, fmt.Sprintf("%s: runAsUser must be %d", label, RestrictedUID))
	}
	if g := effective(sc.RunAsGroup, psc.RunAsGroup); g == nil || *g != RestrictedGID {
		vs = append(vs, fmt.Sprintf("%s: runAsGroup must be %d", label, RestrictedGID))
	}
	if sc.ReadOnlyRootFilesystem == nil || !*sc.ReadOnlyRootFilesystem {
		vs = append(vs, label+": readOnlyRootFilesystem must be true")
	}
	if sc.AllowPrivilegeEscalation == nil || *sc.AllowPrivilegeEscalation {
		vs = append(vs, label+": allowPrivilegeEscalation must be false")
	}
	if !dropsAll(sc.Capabilities) {
		vs = append(vs, label+": capabilities must drop ALL")
	}
	if p := effective(sc.SeccompProfile, psc.SeccompProfile); p == nil || p.Type != corev1.SeccompProfileTypeRuntimeDefault {
		vs = append(vs, label+": seccompProfile type must be RuntimeDefault")
	}
	return vs
}

// effective returns the container-level value when set, else the pod-level one.
func effective[T any](container, pod *T) *T {
	if container != nil {
		return container
	}
	return pod
}

// dropsAll reports whether caps drops the ALL capability.
func dropsAll(caps *corev1.Capabilities) bool {
	if caps == nil {
		return false
	}
	for _, d := range caps.Drop {
		if d == corev1.Capability("ALL") {
			return true
		}
	}
	return false
}
