// Package e2e holds the Ginkgo v2 + Gomega integration suite that installs the
// hardened charts on an ephemeral kind cluster (provisioned via
// sigs.k8s.io/e2e-framework) and asserts the hardening claims on live workloads
// rather than rendered YAML alone (Req 5). The pure, unit-tested provisioning
// helpers it builds on live in the sibling ../harness package.
package e2e
