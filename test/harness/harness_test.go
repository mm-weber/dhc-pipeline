package harness

import (
	"strings"
	"testing"
)

// TestComponentsRegistry pins the exact set of components the e2e suite
// provisions: four entries, each with its canonical name, chart dir,
// ownership flag, release, and namespace.
func TestComponentsRegistry(t *testing.T) {
	want := map[string]Component{
		"cert-manager": {Name: "cert-manager", ChartDir: "chart/cert-manager", Owned: false, Release: "cert-manager", Namespace: "cert-manager"},
		"grafana":      {Name: "grafana", ChartDir: "chart/grafana", Owned: false, Release: "grafana", Namespace: "grafana"},
		"hardened-app": {Name: "hardened-app", ChartDir: "chart/hardened-app", Owned: true, Release: "hardened-app", Namespace: "hardened-app"},
		"valkey":       {Name: "valkey", ChartDir: "chart/valkey", Owned: false, Release: "valkey", Namespace: "valkey"},
	}

	if len(Components) != len(want) {
		t.Fatalf("Components has %d entries, want %d", len(Components), len(want))
	}

	byName := make(map[string]Component, len(Components))
	for _, c := range Components {
		byName[c.Name] = c
	}

	for name, wc := range want {
		got, ok := byName[name]
		if !ok {
			t.Errorf("Components missing entry %q", name)
			continue
		}
		if got != wc {
			t.Errorf("Components[%q] = %+v, want %+v", name, got, wc)
		}
	}
}

// TestLookupKnown verifies a known --chart value resolves to its exact
// Component with no error.
func TestLookupKnown(t *testing.T) {
	want := Component{Name: "hardened-app", ChartDir: "chart/hardened-app", Owned: true, Release: "hardened-app", Namespace: "hardened-app"}

	got, err := Lookup("hardened-app")
	if err != nil {
		t.Fatalf("Lookup(%q) returned error: %v", "hardened-app", err)
	}
	if got != want {
		t.Errorf("Lookup(%q) = %+v, want %+v", "hardened-app", got, want)
	}
}

// TestLookupUnknownErrors verifies unknown and empty --chart values are
// rejected with an error. "redis" is the near-miss worth naming: the valkey
// image ships redis-* symlinks, so the wrong --chart value is a plausible typo.
func TestLookupUnknownErrors(t *testing.T) {
	for _, name := range []string{"redis", ""} {
		t.Run("name="+name, func(t *testing.T) {
			if _, err := Lookup(name); err == nil {
				t.Errorf("Lookup(%q) returned nil error, want non-nil", name)
			}
		})
	}
}

// TestClusterNameAlreadyValid verifies a value that is already a valid RFC1123
// label passes through unchanged.
func TestClusterNameAlreadyValid(t *testing.T) {
	const base = "cert-manager"
	if got := ClusterName(base); got != base {
		t.Errorf("ClusterName(%q) = %q, want %q", base, got, base)
	}
}

// TestClusterNameSanitizes verifies lowercasing and that each run of
// non-[a-z0-9] characters collapses to a single dash.
func TestClusterNameSanitizes(t *testing.T) {
	const base = "PR-123/Grafana Test"
	const want = "pr-123-grafana-test"
	if got := ClusterName(base); got != want {
		t.Errorf("ClusterName(%q) = %q, want %q", base, got, want)
	}
}

// TestClusterNameTrimsAndCollapses verifies leading/trailing dashes are
// trimmed and interior dash runs collapse to one.
func TestClusterNameTrimsAndCollapses(t *testing.T) {
	cases := []struct {
		base string
		want string
	}{
		{"__weird__", "weird"},
		{"a--b", "a-b"},
	}
	for _, tc := range cases {
		t.Run(tc.base, func(t *testing.T) {
			if got := ClusterName(tc.base); got != tc.want {
				t.Errorf("ClusterName(%q) = %q, want %q", tc.base, got, tc.want)
			}
		})
	}
}

// TestClusterNameTruncates verifies an over-long value is truncated to the
// 63-char RFC1123 limit.
func TestClusterNameTruncates(t *testing.T) {
	base := strings.Repeat("a", 80)
	got := ClusterName(base)
	if len(got) != 63 {
		t.Fatalf("ClusterName(80x'a') length = %d, want 63", len(got))
	}
	if got != strings.Repeat("a", 63) {
		t.Errorf("ClusterName(80x'a') = %q, want 63x'a'", got)
	}
}

// TestClusterNameTrimsTrailingDashAfterTruncation verifies that when
// truncation would leave a trailing dash, it is trimmed off.
func TestClusterNameTrimsTrailingDashAfterTruncation(t *testing.T) {
	base := strings.Repeat("a", 62) + "-tail"
	want := strings.Repeat("a", 62)
	got := ClusterName(base)
	if got != want {
		t.Errorf("ClusterName(%q) = %q (len %d), want %q (len %d)", base, got, len(got), want, len(want))
	}
}

// TestClusterNameFallback verifies that when nothing valid remains, a stable
// non-empty fallback name is returned.
func TestClusterNameFallback(t *testing.T) {
	const want = "dhc"
	if got := ClusterName("///"); got != want {
		t.Errorf("ClusterName(%q) = %q, want %q", "///", got, want)
	}
}
