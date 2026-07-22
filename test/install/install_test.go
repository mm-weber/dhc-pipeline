package install

import "testing"

// contains reports whether args includes x.
func contains(args []string, x string) bool {
	for _, a := range args {
		if a == x {
			return true
		}
	}
	return false
}

// containsPair reports whether a appears immediately followed by b in args
// (e.g. a flag and its value: "--version" then "10.5.15").
func containsPair(args []string, a, b string) bool {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == a && args[i+1] == b {
			return true
		}
	}
	return false
}

// TestParsePin exercises the adapted chart.yaml upstream pin parser (Req 4.1):
// a complete upstream block yields the pin, an absent/empty one is an error.
func TestParsePin(t *testing.T) {
	t.Run("valid upstream block", func(t *testing.T) {
		data := []byte("upstream:\n  name: grafana\n  repository: https://grafana.github.io/helm-charts\n  version: 10.5.15\n")
		got, err := ParsePin(data)
		if err != nil {
			t.Fatalf("ParsePin returned error: %v", err)
		}
		want := Pin{Name: "grafana", Repository: "https://grafana.github.io/helm-charts", Version: "10.5.15"}
		if got != want {
			t.Errorf("ParsePin = %+v, want %+v", got, want)
		}
	})

	t.Run("missing upstream block is an error", func(t *testing.T) {
		if _, err := ParsePin([]byte("other: x\n")); err == nil {
			t.Error("ParsePin(no upstream) returned nil error, want error")
		}
	})
}

// TestArgs exercises the helm argv builder (Req 5.6): owned charts install from
// a local directory, adapted charts from --repo/--version with a hardened values
// overlay, upgrades take a version override, only install creates the namespace,
// and extra flags are appended.
func TestArgs(t *testing.T) {
	t.Run("owned install uses the chart directory", func(t *testing.T) {
		args := Args(Spec{
			Verb:       "install",
			Release:    "hardened-app",
			Namespace:  "hardened-app",
			Kubeconfig: "/kc",
			Owned:      true,
			ChartPath:  "/repo/chart/hardened-app",
		})
		if len(args) < 3 || args[0] != "install" || args[1] != "hardened-app" || args[2] != "/repo/chart/hardened-app" {
			t.Fatalf("prefix = %v, want [install hardened-app /repo/chart/hardened-app ...]", args)
		}
		if !containsPair(args, "--namespace", "hardened-app") {
			t.Errorf("missing pair --namespace hardened-app in %v", args)
		}
		if !containsPair(args, "--kubeconfig", "/kc") {
			t.Errorf("missing pair --kubeconfig /kc in %v", args)
		}
		if !contains(args, "--create-namespace") {
			t.Errorf("missing --create-namespace in %v", args)
		}
		if contains(args, "--repo") {
			t.Errorf("owned install must not contain --repo: %v", args)
		}
		if contains(args, "--version") {
			t.Errorf("owned install must not contain --version: %v", args)
		}
	})

	t.Run("adapted install uses upstream repo/version and values overlay", func(t *testing.T) {
		args := Args(Spec{
			Verb:       "install",
			Release:    "grafana",
			Namespace:  "grafana",
			Kubeconfig: "/kc",
			Owned:      false,
			Pin:        Pin{Name: "grafana", Repository: "https://grafana.github.io/helm-charts", Version: "10.5.15"},
			ValuesFile: "/repo/chart/grafana/config/values-hardened.yaml",
		})
		if len(args) < 3 || args[0] != "install" || args[1] != "grafana" || args[2] != "grafana" {
			t.Fatalf("prefix = %v, want [install grafana grafana ...] (verb, release, upstream chart name)", args)
		}
		if !containsPair(args, "--repo", "https://grafana.github.io/helm-charts") {
			t.Errorf("missing pair --repo https://grafana.github.io/helm-charts in %v", args)
		}
		if !containsPair(args, "--version", "10.5.15") {
			t.Errorf("missing pair --version 10.5.15 in %v", args)
		}
		if !containsPair(args, "-f", "/repo/chart/grafana/config/values-hardened.yaml") {
			t.Errorf("missing pair -f <values overlay> in %v", args)
		}
		if !contains(args, "--create-namespace") {
			t.Errorf("missing --create-namespace in %v", args)
		}
	})

	t.Run("adapted upgrade honors the version override", func(t *testing.T) {
		args := Args(Spec{
			Verb:       "upgrade",
			Release:    "grafana",
			Namespace:  "grafana",
			Kubeconfig: "/kc",
			Owned:      false,
			Pin:        Pin{Name: "grafana", Repository: "https://grafana.github.io/helm-charts", Version: "10.5.15"},
			ValuesFile: "/repo/chart/grafana/config/values-hardened.yaml",
			Version:    "10.4.0",
		})
		if len(args) < 2 || args[0] != "upgrade" || args[1] != "grafana" {
			t.Fatalf("prefix = %v, want [upgrade grafana ...]", args)
		}
		if !containsPair(args, "--version", "10.4.0") {
			t.Errorf("missing pair --version 10.4.0 (override) in %v", args)
		}
		if contains(args, "10.5.15") {
			t.Errorf("override must win: pinned version 10.5.15 must not appear in %v", args)
		}
		if contains(args, "--create-namespace") {
			t.Errorf("upgrade must not create the namespace: %v", args)
		}
	})

	t.Run("extra flags are appended", func(t *testing.T) {
		args := Args(Spec{
			Verb:       "install",
			Release:    "cert-manager",
			Namespace:  "cert-manager",
			Kubeconfig: "/kc",
			Owned:      false,
			Pin:        Pin{Name: "cert-manager", Repository: "https://charts.jetstack.io", Version: "1.16.2"},
			ValuesFile: "/repo/chart/cert-manager/config/values-hardened.yaml",
			Extra:      []string{"--set", "crds.enabled=true"},
		})
		if !containsPair(args, "--set", "crds.enabled=true") {
			t.Errorf("missing appended pair --set crds.enabled=true in %v", args)
		}
	})
}
