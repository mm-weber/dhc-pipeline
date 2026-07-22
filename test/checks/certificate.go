package checks

import "k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"

// CertificateReady reports whether a cert-manager Certificate (as an
// unstructured object) has a Ready status condition set to True — the
// cert-manager functional probe. (stub — GREEN implements)
func CertificateReady(obj *unstructured.Unstructured) bool { return false }
