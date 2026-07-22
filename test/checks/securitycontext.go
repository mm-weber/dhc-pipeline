// Package checks holds the pure assertion predicates the e2e specs build on:
// small, dependency-free functions over corev1 objects (no cluster access) so
// the hardening claims are unit-testable in isolation before the kind suite.
package checks

import corev1 "k8s.io/api/core/v1"

// The restricted profile the catalogue pins (Req 5.4 / 4.3).
const (
	RestrictedUID int64 = 65532
	RestrictedGID int64 = 65532
)

// RestrictedViolations reports how pod deviates from the restricted
// securityContext profile; empty means compliant. (stub — GREEN implements)
func RestrictedViolations(pod *corev1.Pod) []string {
	return []string{"RESTRICTED_VIOLATIONS_NOT_IMPLEMENTED"}
}
