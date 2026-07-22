package checks

import (
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

// boolPtr / int64Ptr are local pointer helpers so the tests can populate the
// pointer-typed securityContext fields without pulling in a dependency.
func boolPtr(b bool) *bool    { return &b }
func int64Ptr(i int64) *int64 { return &i }

// compliantPod returns a fresh, fully-compliant one-container Pod: every
// restricted-profile field is set at the container level so callers can mutate
// a single field to drive one fault at a time. Each call allocates anew, so
// mutating the returned pod never leaks into another test.
func compliantPod() *corev1.Pod {
	return &corev1.Pod{
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{
				{
					Name:            "app",
					SecurityContext: compliantContainerSC(),
				},
			},
		},
	}
}

// compliantContainerSC is a container securityContext that satisfies every
// field of the restricted profile.
func compliantContainerSC() *corev1.SecurityContext {
	return &corev1.SecurityContext{
		RunAsNonRoot:             boolPtr(true),
		RunAsUser:                int64Ptr(RestrictedUID),
		RunAsGroup:               int64Ptr(RestrictedGID),
		ReadOnlyRootFilesystem:   boolPtr(true),
		AllowPrivilegeEscalation: boolPtr(false),
		Capabilities:             &corev1.Capabilities{Drop: []corev1.Capability{corev1.Capability("ALL")}},
		SeccompProfile:           &corev1.SeccompProfile{Type: corev1.SeccompProfileTypeRuntimeDefault},
	}
}

// containerOnlyCompliantSC sets only the container-only fields (the ones with no
// pod-level equivalent) and leaves the effective-merge fields nil so they must
// be inherited from the pod.
func containerOnlyCompliantSC() *corev1.SecurityContext {
	return &corev1.SecurityContext{
		ReadOnlyRootFilesystem:   boolPtr(true),
		AllowPrivilegeEscalation: boolPtr(false),
		Capabilities:             &corev1.Capabilities{Drop: []corev1.Capability{corev1.Capability("ALL")}},
	}
}

// compliantPodSC is a pod-level securityContext that satisfies the four
// inheritable fields (runAsNonRoot / runAsUser / runAsGroup / seccomp).
func compliantPodSC() *corev1.PodSecurityContext {
	return &corev1.PodSecurityContext{
		RunAsNonRoot:   boolPtr(true),
		RunAsUser:      int64Ptr(RestrictedUID),
		RunAsGroup:     int64Ptr(RestrictedGID),
		SeccompProfile: &corev1.SeccompProfile{Type: corev1.SeccompProfileTypeRuntimeDefault},
	}
}

// containsViolation reports whether any violation string contains every one of
// subs (case-insensitively), so message wording stays flexible.
func containsViolation(vs []string, subs ...string) bool {
	for _, v := range vs {
		lv := strings.ToLower(v)
		matched := true
		for _, s := range subs {
			if !strings.Contains(lv, strings.ToLower(s)) {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}

func TestRestrictedViolations_Compliant(t *testing.T) {
	pod := compliantPod()
	if got := RestrictedViolations(pod); len(got) != 0 {
		t.Fatalf("compliant pod: want 0 violations, got %d: %v", len(got), got)
	}
}

// TestRestrictedViolations_SingleFault mutates exactly one restricted-profile
// field on the app container and asserts a single violation naming both the
// container and the offending field.
func TestRestrictedViolations_SingleFault(t *testing.T) {
	cases := []struct {
		name    string
		mutate  func(sc *corev1.SecurityContext)
		keyword string
	}{
		{
			name:    "runAsNonRoot false",
			mutate:  func(sc *corev1.SecurityContext) { sc.RunAsNonRoot = boolPtr(false) },
			keyword: "runAsNonRoot",
		},
		{
			name:    "runAsUser root",
			mutate:  func(sc *corev1.SecurityContext) { sc.RunAsUser = int64Ptr(0) },
			keyword: "runAsUser",
		},
		{
			name:    "runAsGroup root",
			mutate:  func(sc *corev1.SecurityContext) { sc.RunAsGroup = int64Ptr(0) },
			keyword: "runAsGroup",
		},
		{
			name:    "readOnlyRootFilesystem nil",
			mutate:  func(sc *corev1.SecurityContext) { sc.ReadOnlyRootFilesystem = nil },
			keyword: "readOnlyRootFilesystem",
		},
		{
			name:    "allowPrivilegeEscalation true",
			mutate:  func(sc *corev1.SecurityContext) { sc.AllowPrivilegeEscalation = boolPtr(true) },
			keyword: "allowPrivilegeEscalation",
		},
		{
			name: "capabilities missing ALL drop",
			mutate: func(sc *corev1.SecurityContext) {
				sc.Capabilities = &corev1.Capabilities{Drop: []corev1.Capability{corev1.Capability("NET_RAW")}}
			},
			keyword: "capabilit",
		},
		{
			name: "seccomp Unconfined",
			mutate: func(sc *corev1.SecurityContext) {
				sc.SeccompProfile = &corev1.SeccompProfile{Type: corev1.SeccompProfileTypeUnconfined}
			},
			keyword: "seccomp",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pod := compliantPod()
			tc.mutate(pod.Spec.Containers[0].SecurityContext)

			got := RestrictedViolations(pod)
			if len(got) != 1 {
				t.Fatalf("want exactly 1 violation, got %d: %v", len(got), got)
			}
			if !containsViolation(got, "app", tc.keyword) {
				t.Errorf("violation %q must name container %q and field %q", got[0], "app", tc.keyword)
			}
		})
	}
}

// TestRestrictedViolations_InheritanceOK: the four merge fields are set only at
// the pod level and the container sets just the container-only fields; the
// effective values are inherited, so the pod is compliant.
func TestRestrictedViolations_InheritanceOK(t *testing.T) {
	pod := compliantPod()
	pod.Spec.SecurityContext = compliantPodSC()
	pod.Spec.Containers[0].SecurityContext = containerOnlyCompliantSC()

	if got := RestrictedViolations(pod); len(got) != 0 {
		t.Fatalf("inherited-compliant pod: want 0 violations, got %d: %v", len(got), got)
	}
}

// TestRestrictedViolations_OverrideBad: pod level is compliant but the container
// overrides runAsUser to root while keeping its container-only fields compliant;
// the effective (container-wins) value violates, so exactly one violation names
// runAsUser.
func TestRestrictedViolations_OverrideBad(t *testing.T) {
	pod := compliantPod()
	pod.Spec.SecurityContext = compliantPodSC()
	sc := containerOnlyCompliantSC()
	sc.RunAsUser = int64Ptr(0) // override pod-level 65532 with root
	pod.Spec.Containers[0].SecurityContext = sc

	got := RestrictedViolations(pod)
	if len(got) != 1 {
		t.Fatalf("want exactly 1 violation, got %d: %v", len(got), got)
	}
	if !containsViolation(got, "app", "runAsUser") {
		t.Errorf("violation %q must name container %q and field runAsUser", got[0], "app")
	}
}

// TestRestrictedViolations_InitContainer: a compliant pod with one faulty
// initContainer yields a violation that flags the initContainer by kind and
// name.
func TestRestrictedViolations_InitContainer(t *testing.T) {
	pod := compliantPod()
	faulty := compliantContainerSC()
	faulty.RunAsUser = int64Ptr(0)
	pod.Spec.InitContainers = []corev1.Container{
		{Name: "init-migrate", SecurityContext: faulty},
	}

	got := RestrictedViolations(pod)
	if len(got) != 1 {
		t.Fatalf("want exactly 1 violation, got %d: %v", len(got), got)
	}
	if !containsViolation(got, "initContainer", "init-migrate") {
		t.Errorf("violation %q must flag initContainer %q", got[0], "init-migrate")
	}
}

// TestRestrictedViolations_ContainerSCNil: with a nil container securityContext
// the four merge fields inherit the compliant pod level, but the three
// container-only fields have no pod equivalent and are therefore all violated.
func TestRestrictedViolations_ContainerSCNil(t *testing.T) {
	pod := compliantPod()
	pod.Spec.SecurityContext = compliantPodSC()
	pod.Spec.Containers[0].SecurityContext = nil

	got := RestrictedViolations(pod)
	if len(got) != 3 {
		t.Fatalf("nil container securityContext: want 3 container-only violations, got %d: %v", len(got), got)
	}
	if !containsViolation(got, "app", "readOnlyRootFilesystem") {
		t.Errorf("violations %v must flag readOnlyRootFilesystem on container app", got)
	}
	if !containsViolation(got, "app", "allowPrivilegeEscalation") {
		t.Errorf("violations %v must flag allowPrivilegeEscalation on container app", got)
	}
	if !containsViolation(got, "app", "capabilit") {
		t.Errorf("violations %v must flag capabilities on container app", got)
	}
}
