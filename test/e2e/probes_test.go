package e2e

import (
	"context"
	"fmt"
	"os"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/klient/wait"

	"github.com/mm-weber/dhc-pipeline/test/checks"
	"github.com/mm-weber/dhc-pipeline/test/harness"
)

// probeFunc runs a component's functional probe against the live cluster (Req 5.5).
type probeFunc func(ctx context.Context, r *resources.Resources, c harness.Component) error

func ptr[T any](v T) *T { return &v }

// probeImage is the HTTP-probe container. It defaults to a curl tag but is
// overridden by DHC_PROBE_IMAGE, which the e2e workflow (task 6.5) sets to a
// digest-pinned reference it has already loaded into kind — same pattern as
// KIND_NODE_IMAGE. Kept out of the catalogue's pinned surface: it is test
// scaffolding, not a shipped image.
func probeImage() string {
	if img := os.Getenv("DHC_PROBE_IMAGE"); img != "" {
		return img
	}
	return "curlimages/curl:8.11.1"
}

// httpProbe returns a probe that runs an in-cluster curl Job against the
// component's Service and asserts a 2xx (curl -f), i.e. grafana answers HTTP
// health and hardened-app returns HTTP 200 (Req 5.5). Running the probe as a
// Job inside the cluster avoids port-forward flakiness and needs no ingress.
func httpProbe(path string) probeFunc {
	return func(ctx context.Context, r *resources.Resources, c harness.Component) error {
		url := fmt.Sprintf("http://%s.%s.svc.cluster.local:80%s", c.Release, c.Namespace, path)
		name := "probe-" + c.Name
		job := &batchv1.Job{
			ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: c.Namespace},
			Spec: batchv1.JobSpec{
				BackoffLimit: ptr(int32(2)),
				Template: corev1.PodTemplateSpec{
					Spec: corev1.PodSpec{
						RestartPolicy: corev1.RestartPolicyNever,
						Containers: []corev1.Container{{
							Name:  "curl",
							Image: probeImage(),
							// Retry so a just-Ready pod that is not yet serving does
							// not flake the probe; -f makes non-2xx a curl failure.
							Command: []string{
								"curl", "-sSf", "--max-time", "10",
								"--retry", "30", "--retry-delay", "2", "--retry-connrefused",
								url,
							},
							SecurityContext: &corev1.SecurityContext{
								RunAsNonRoot: ptr(true),
								// Explicit numeric UID: with only RunAsNonRoot set, kubelet
								// cannot verify a non-root image whose USER is a name
								// (curlimages/curl's curl_user) and rejects the container
								// with CreateContainerConfigError. curl needs no writes for
								// an HTTP GET, so any non-root UID works.
								RunAsUser:                ptr(int64(65532)),
								AllowPrivilegeEscalation: ptr(false),
								ReadOnlyRootFilesystem:   ptr(true),
								Capabilities:             &corev1.Capabilities{Drop: []corev1.Capability{"ALL"}},
								SeccompProfile:           &corev1.SeccompProfile{Type: corev1.SeccompProfileTypeRuntimeDefault},
							},
						}},
					},
				},
			},
		}
		if err := r.Create(ctx, job); err != nil {
			return fmt.Errorf("create probe job: %w", err)
		}
		return waitJobSucceeded(ctx, r, name, c.Namespace)
	}
}

// waitJobSucceeded polls until the probe Job completes successfully (checks.JobSucceeded).
func waitJobSucceeded(ctx context.Context, r *resources.Resources, name, namespace string) error {
	return wait.For(func(ctx context.Context) (bool, error) {
		var job batchv1.Job
		if err := r.Get(ctx, name, namespace, &job); err != nil {
			return false, nil
		}
		return checks.JobSucceeded(&job), nil
	}, wait.WithTimeout(3*time.Minute), wait.WithContext(ctx))
}

// probeCertManager exercises cert-manager end to end: a SelfSigned Issuer signs
// a Certificate, and the probe waits for that Certificate to go Ready — i.e.
// cert-manager actually issues a certificate (Req 5.5). Objects are unstructured
// so the suite needs no cert-manager Go module. Create is retried: right after
// the CRDs install, the client's REST mapper can briefly not know the kinds.
func probeCertManager(ctx context.Context, r *resources.Resources, c harness.Component) error {
	issuer := certManagerObject("Issuer", "e2e-selfsigned", c.Namespace, map[string]interface{}{
		"selfSigned": map[string]interface{}{},
	})
	cert := certManagerObject("Certificate", "e2e-cert", c.Namespace, map[string]interface{}{
		"secretName": "e2e-cert-tls",
		"dnsNames":   []interface{}{"e2e.dhc.local"},
		"issuerRef": map[string]interface{}{
			"name": "e2e-selfsigned",
			"kind": "Issuer",
		},
	})
	if err := createWithRetry(ctx, r, issuer); err != nil {
		return fmt.Errorf("create Issuer: %w", err)
	}
	if err := createWithRetry(ctx, r, cert); err != nil {
		return fmt.Errorf("create Certificate: %w", err)
	}
	return wait.For(func(ctx context.Context) (bool, error) {
		got := &unstructured.Unstructured{}
		got.SetGroupVersionKind(schema.GroupVersionKind{Group: "cert-manager.io", Version: "v1", Kind: "Certificate"})
		if err := r.Get(ctx, "e2e-cert", c.Namespace, got); err != nil {
			return false, nil
		}
		return checks.CertificateReady(got), nil
	}, wait.WithTimeout(2*time.Minute), wait.WithContext(ctx))
}

// certManagerObject builds a cert-manager.io/v1 object as unstructured.
func certManagerObject(kind, name, namespace string, spec map[string]interface{}) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "cert-manager.io/v1",
		"kind":       kind,
		"metadata": map[string]interface{}{
			"name":      name,
			"namespace": namespace,
		},
		"spec": spec,
	}}
}

// createWithRetry tolerates the transient "no matches for kind" window while the
// client's REST mapper catches up with a freshly installed CRD.
func createWithRetry(ctx context.Context, r *resources.Resources, obj *unstructured.Unstructured) error {
	return wait.For(func(ctx context.Context) (bool, error) {
		if err := r.Create(ctx, obj); err != nil {
			return false, nil
		}
		return true, nil
	}, wait.WithTimeout(1*time.Minute), wait.WithContext(ctx))
}
