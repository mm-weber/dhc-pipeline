// Package install builds the helm invocations the kind e2e suite runs to deploy
// a component's chart — an owned chart from its local directory, or an adapted
// chart from its pinned upstream — and the upgrade to a proposed version
// (Req 5.6). Pure: no cluster, no exec, so it is unit-tested in isolation.
package install

// Pin is an adapted chart's pinned upstream (the chart.yaml `upstream:` block, Req 4.1).
type Pin struct {
	Name       string `json:"name"`
	Repository string `json:"repository"`
	Version    string `json:"version"`
}

// Spec describes one `helm install|upgrade` invocation.
type Spec struct {
	Verb       string // "install" or "upgrade"
	Release    string
	Namespace  string
	Kubeconfig string
	Owned      bool
	ChartPath  string   // owned: local chart directory
	Pin        Pin      // adapted: upstream coordinates
	ValuesFile string   // adapted: hardened values overlay
	Version    string   // adapted: overrides Pin.Version when non-empty (the upgrade-from version)
	Extra      []string // extra flags, e.g. []string{"--set", "crds.enabled=true"}
}

// ParsePin extracts the upstream pin from an adapted chart's chart.yaml bytes.
func ParsePin(data []byte) (Pin, error) { return Pin{}, nil } // STUB

// Args builds the argv for `helm <Verb> ...`.
func Args(spec Spec) []string { return nil } // STUB
