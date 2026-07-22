package checks

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
)

// ArtifactsDir is where DumpDiagnostics writes; the e2e workflow (task 6.5)
// points DHC_ARTIFACTS at a path it uploads as a build artifact.
func ArtifactsDir() string {
	if d := os.Getenv("DHC_ARTIFACTS"); d != "" {
		return d
	}
	return "_artifacts"
}

// DumpDiagnostics writes the namespace's pods, events, and deployments as JSON
// under outDir so a failed e2e run preserves why a workload never became healthy
// — image-pull errors, scheduling failures, and crash loops all surface in pod
// status and events (Req 5.7). Best-effort: each collection is independent and a
// failure is aggregated into the returned error rather than aborting the rest.
func DumpDiagnostics(ctx context.Context, r *resources.Resources, namespace, outDir string) error {
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return fmt.Errorf("mkdir %s: %w", outDir, err)
	}

	var errs []string
	dump := func(name string, list k8s.ObjectList) {
		if err := r.List(ctx, list); err != nil {
			errs = append(errs, fmt.Sprintf("list %s: %v", name, err))
			return
		}
		b, err := json.MarshalIndent(list, "", "  ")
		if err != nil {
			errs = append(errs, fmt.Sprintf("marshal %s: %v", name, err))
			return
		}
		f := filepath.Join(outDir, fmt.Sprintf("%s-%s.json", namespace, name))
		if err := os.WriteFile(f, b, 0o644); err != nil {
			errs = append(errs, fmt.Sprintf("write %s: %v", name, err))
		}
	}

	dump("pods", &corev1.PodList{})
	dump("events", &corev1.EventList{})
	dump("deployments", &appsv1.DeploymentList{})

	if len(errs) > 0 {
		return fmt.Errorf("diagnostics for namespace %s: %s", namespace, strings.Join(errs, "; "))
	}
	return nil
}
