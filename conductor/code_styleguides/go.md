# Go style

- `gofmt` and `go vet` clean; `go.mod` and `go.sum` equal to what `go mod tidy` writes (validate checks both modules).
- `test/`: Ginkgo v2 with Gomega against kind through `sigs.k8s.io/e2e-framework`; without `DHC_E2E=1` the suite is a cluster-free no-op so `go test ./...` stays fast. Components are registered in `test/harness`; probes in the `probes` registry in `test/e2e`, keyed by the name a chart declares, and a unit test holds declarations and registrations equal both ways.
- `triage/rescan`: standard library only; pure functions with table-driven tests; the workflow drives it.
- Errors wrap with context and are returned, not logged and swallowed; a function that reads a declared value fails on a missing or malformed one.
- Comments cite the criterion and task like the shell scripts do.
