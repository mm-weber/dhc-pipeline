// Package harness holds the pure, dependency-free helpers the kind e2e suite
// builds on: the registry of provisionable components, the --chart selector
// that resolves a flag value to a component, and kind cluster-name derivation.
package harness

import (
	"fmt"
	"strings"
)

// Component is one deployable unit the kind e2e suite provisions and installs.
type Component struct {
	Name      string // canonical id; the value accepted by the suite's --chart flag
	ChartDir  string // repo-relative chart directory
	Owned     bool   // true = owned chart (Chart.yaml); false = adapted chart (chart.yaml pin + values overlay)
	Release   string // helm release name
	Namespace string // install namespace
}

// Components is the registry of components the e2e suite knows how to provision.
var Components = []Component{
	{Name: "cert-manager", ChartDir: "chart/cert-manager", Owned: false, Release: "cert-manager", Namespace: "cert-manager"},
	{Name: "grafana", ChartDir: "chart/grafana", Owned: false, Release: "grafana", Namespace: "grafana"},
	{Name: "hardened-app", ChartDir: "chart/hardened-app", Owned: true, Release: "hardened-app", Namespace: "hardened-app"},
	{Name: "valkey", ChartDir: "chart/valkey", Owned: false, Release: "valkey", Namespace: "valkey"},
}

// Lookup resolves a --chart value to its Component, or errors on an unknown name.
func Lookup(name string) (Component, error) {
	for _, c := range Components {
		if c.Name == name {
			return c, nil
		}
	}
	return Component{}, fmt.Errorf("unknown component %q", name)
}

// maxLabelLen is the RFC1123 DNS label limit ClusterName truncates to.
const maxLabelLen = 63

// ClusterName derives a kind-safe cluster name from base (RFC1123 label:
// lowercase, [a-z0-9-], starts/ends alphanumeric, <= 63 chars). Every run of
// characters outside [a-z0-9] collapses to a single dash; leading/trailing
// dashes are trimmed; the result is truncated to 63 chars with any trailing
// dash left by truncation removed. Falls back to "dhc" if nothing valid remains.
func ClusterName(base string) string {
	var b strings.Builder
	prevDash := false
	for _, r := range strings.ToLower(base) {
		switch {
		case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			b.WriteRune(r)
			prevDash = false
		case b.Len() > 0 && !prevDash:
			b.WriteByte('-')
			prevDash = true
		}
	}

	s := strings.Trim(b.String(), "-")
	if len(s) > maxLabelLen {
		s = strings.TrimRight(s[:maxLabelLen], "-")
	}
	if s == "" {
		return "dhc"
	}
	return s
}
