// Package harness holds the pure, dependency-free helpers the kind e2e suite
// builds on: the registry of provisionable components, the --chart selector
// that resolves a flag value to a component, and kind cluster-name derivation.
package harness

// Component is one deployable unit the kind e2e suite provisions and installs.
type Component struct {
	Name      string // canonical id; the value accepted by the suite's --chart flag
	ChartDir  string // repo-relative chart directory
	Owned     bool   // true = owned chart (Chart.yaml); false = adapted chart (chart.yaml pin + values overlay)
	Release   string // helm release name
	Namespace string // install namespace
}

// Components is the registry of components the e2e suite knows how to provision.
var Components []Component // STUB: leave nil/empty in RED

// Lookup resolves a --chart value to its Component, or errors on an unknown name.
func Lookup(name string) (Component, error) { return Component{}, nil } // STUB

// ClusterName derives a kind-safe cluster name from base (RFC1123 label:
// lowercase, [a-z0-9-], starts/ends alphanumeric, <= 63 chars).
func ClusterName(base string) string { return "" } // STUB
