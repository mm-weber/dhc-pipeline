package e2e

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/klient/wait"

	"github.com/mm-weber/dhc-pipeline/test/checks"
	"github.com/mm-weber/dhc-pipeline/test/harness"
	"github.com/mm-weber/dhc-pipeline/test/install"
)

// probeFunc runs a component's functional probe against the live cluster (Req 5.5).
type probeFunc func(ctx context.Context, r *resources.Resources, c harness.Component) error

// probes is the registry of functional probes, keyed by the registration name
// a chart declares as `probe:` in chart/<c>/chart.yaml (task 14.3). A chart
// deploys one or more definitions (`deploys:`) and declares one probe, so a
// registration shared by several definitions executes once per install
// (Req 5.5): the three cert-manager images are proved by one Certificate
// issuance, the valkey pair by one SET and GET. The four reference
// registrations are today's probes; a fork adds a line here and names it in
// its chart. TestProbeDeclarations holds the two sides equal both ways, and
// scripts/lint-probes.sh fails validate for an active definition whose chart
// names no probe (Req 5.8). There is no no-op registration on purpose.
var probes = map[string]probeFunc{
	"certificate-issuance": probeCertManager,
	"http-health":          httpProbe("/api/health"),
	"http-200":             httpProbe("/healthz"),
	"set-get":              probeValkey,
}

// probeFor resolves the probe a component's chart declares, by name, through
// the registry. A chart naming no probe or an unregistered one is an error
// naming the chart file, never a silently skipped probe.
func probeFor(c harness.Component) (probeFunc, error) {
	rel := filepath.Join(c.ChartDir, "chart.yaml")
	b, err := os.ReadFile(filepath.Join(repoRoot(), rel))
	if err != nil {
		return nil, err
	}
	d, err := install.ParseDeclaration(b)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", rel, err)
	}
	if d.Probe == "" {
		return nil, fmt.Errorf("%s declares no functional probe (probe:), and no active definition goes without one (Req 5.5, 5.8)", rel)
	}
	p, ok := probes[d.Probe]
	if !ok {
		return nil, fmt.Errorf("%s declares probe %q, which test/e2e registers no probe under (Req 5.5)", rel, d.Probe)
	}
	return p, nil
}

func ptr[T any](v T) *T { return &v }

// probeImage is the HTTP-probe container. It defaults to a curl tag for local
// runs but is overridden by DHC_PROBE_IMAGE, which the e2e workflow (task
// 6.5) sets to the tag it pulled by digest and loaded into kind: the pin
// lives in the workflow, the pod references the loaded name, because a
// loaded image cannot match an index digest (review D4). Test scaffolding,
// not a shipped image; tracked by its own Renovate manager.
func probeImage() string {
	if img := os.Getenv("DHC_PROBE_IMAGE"); img != "" {
		return img
	}
	return "ghcr.io/curl/curl-container/curl-multi:8.11.1"
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

// probeValkey proves a SET/GET round-trip through the Service (Req 5.5): a Job
// writes a key and asserts that reading it back returns what was written, so a
// server that answers PING but stores nothing still fails.
//
// Two deliberate choices. The image is read off the live Deployment rather than
// re-derived from the chart values, so the probe can only ever exercise the
// image that is actually running. And it runs `sh -c`, which the runtime image
// has no answer for — but this chart already deploys the compat variant for its
// init container (chart/valkey/README.md), so the shell is present either way
// and no probe-only image enters the picture.
func probeValkey(ctx context.Context, r *resources.Resources, c harness.Component) error {
	var dep appsv1.Deployment
	if err := r.Get(ctx, c.Release, c.Namespace, &dep); err != nil {
		return fmt.Errorf("get deployment %s: %w", c.Release, err)
	}
	if len(dep.Spec.Template.Spec.Containers) == 0 {
		return fmt.Errorf("deployment %s renders no containers", c.Release)
	}

	host := fmt.Sprintf("%s.%s.svc.cluster.local", c.Release, c.Namespace)
	cli := fmt.Sprintf("valkey-cli -h %s -p 6379", host)
	// `test` decides the exit code, so correctness never rests on valkey-cli's
	// exit status for an error reply.
	script := fmt.Sprintf(`%s set dhc-e2e ok >/dev/null && test "$(%s get dhc-e2e)" = ok`, cli, cli)

	name := "probe-" + c.Name
	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: c.Namespace},
		Spec: batchv1.JobSpec{
			BackoffLimit: ptr(int32(2)),
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					RestartPolicy: corev1.RestartPolicyNever,
					Containers: []corev1.Container{{
						Name:    "valkey-cli",
						Image:   dep.Spec.Template.Spec.Containers[0].Image,
						Command: []string{"sh", "-c", script},
						SecurityContext: &corev1.SecurityContext{
							RunAsNonRoot:             ptr(true),
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
