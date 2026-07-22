// Package install builds the helm invocations the kind e2e suite runs to deploy
// a component's chart — an owned chart from its local directory, or an adapted
// chart from its pinned upstream — and the upgrade to a proposed version
// (Req 5.6). Pure: no cluster, no exec, so it is unit-tested in isolation.
package install

import (
	"fmt"

	"sigs.k8s.io/yaml"
)

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
func ParsePin(data []byte) (Pin, error) {
	var doc struct {
		Upstream Pin `json:"upstream"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return Pin{}, err
	}
	p := doc.Upstream
	if p.Name == "" || p.Repository == "" || p.Version == "" {
		return Pin{}, fmt.Errorf("incomplete upstream pin: %+v", p)
	}
	return p, nil
}

// Args builds the argv for `helm <Verb> ...`.
func Args(spec Spec) []string {
	args := []string{spec.Verb, spec.Release}
	if spec.Owned {
		args = append(args, spec.ChartPath)
	} else {
		version := spec.Version
		if version == "" {
			version = spec.Pin.Version
		}
		args = append(args,
			spec.Pin.Name,
			"--repo", spec.Pin.Repository,
			"--version", version,
			"-f", spec.ValuesFile,
		)
	}
	args = append(args, "--namespace", spec.Namespace, "--kubeconfig", spec.Kubeconfig)
	if spec.Verb == "install" {
		args = append(args, "--create-namespace")
	}
	args = append(args, spec.Extra...)
	return args
}
