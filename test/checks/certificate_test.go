package checks

import (
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

// cert builds an unstructured cert-manager Certificate carrying the given
// status.conditions list, mirroring how cert-manager writes conditions as a
// list of maps with string type/status.
func cert(conditions []interface{}) *unstructured.Unstructured {
	status := map[string]interface{}{}
	if conditions != nil {
		status["conditions"] = conditions
	}
	return &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "cert-manager.io/v1",
		"kind":       "Certificate",
		"status":     status,
	}}
}

// TestCertificateReady exercises the cert-manager Certificate readiness
// predicate the e2e specs assert on: ready iff status.conditions has an entry
// with type "Ready" and status "True" (Req 5.5).
func TestCertificateReady(t *testing.T) {
	cases := []struct {
		name string
		obj  *unstructured.Unstructured
		want bool
	}{
		{
			name: "ready true",
			obj: cert([]interface{}{
				map[string]interface{}{"type": "Ready", "status": "True"},
			}),
			want: true,
		},
		{
			name: "ready false",
			obj: cert([]interface{}{
				map[string]interface{}{"type": "Ready", "status": "False"},
			}),
			want: false,
		},
		{
			name: "non-ready condition only",
			obj: cert([]interface{}{
				map[string]interface{}{"type": "Issuing", "status": "True"},
			}),
			want: false,
		},
		{
			name: "no status",
			obj: &unstructured.Unstructured{Object: map[string]interface{}{
				"apiVersion": "cert-manager.io/v1",
				"kind":       "Certificate",
			}},
			want: false,
		},
		{
			name: "no conditions key",
			obj:  cert(nil),
			want: false,
		},
		{
			name: "empty conditions list",
			obj:  cert([]interface{}{}),
			want: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := CertificateReady(tc.obj); got != tc.want {
				t.Errorf("CertificateReady() = %v, want %v", got, tc.want)
			}
		})
	}
}
