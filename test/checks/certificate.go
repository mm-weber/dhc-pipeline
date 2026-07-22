package checks

import "k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"

// CertificateReady reports whether a cert-manager Certificate (as an
// unstructured object) has a Ready status condition set to True — the
// cert-manager functional probe.
func CertificateReady(obj *unstructured.Unstructured) bool {
	conditions, found, err := unstructured.NestedSlice(obj.Object, "status", "conditions")
	if err != nil || !found {
		return false
	}
	for _, c := range conditions {
		m, ok := c.(map[string]interface{})
		if !ok {
			continue
		}
		condType, _ := m["type"].(string)
		condStatus, _ := m["status"].(string)
		if condType == "Ready" && condStatus == "True" {
			return true
		}
	}
	return false
}
