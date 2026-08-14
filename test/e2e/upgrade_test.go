package e2e

import (
	"fmt"
	"os"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// The upgrade-path spec verifies Req 5.6: on a component bump the workflow (task
// 6.5) passes the base state — DHC_UPGRADE_FROM=<base chart version> on a chart
// bump, DHC_UPGRADE_VALUES_FROM=<base values snapshot path> on an image bump
// (the ordinary Renovate path: a definition bump publishes a new image and the
// chart-pin manager moves the values file, task 8.7), either or both — and the
// suite installs that currently-pinned state, upgrades to the proposed (PR)
// state, and re-asserts rollout completion, readiness, the restricted
// securityContext, and the functional probe — rollout completion first, so
// the re-asserts see the proposed pods, not the base release's (issue #75).
// It is mutually exclusive with the install spec (which
// skips when either variable is set), so a run never installs the same release
// twice. Owned charts have no chart version to move, so only the values path
// triggers them.
var _ = Describe("hardened catalogue component upgrade path", func() {
	for _, s := range componentSpecs {
		s := s
		Context(s.Name, func() {
			var fromVersion, fromValues string
			BeforeEach(func() {
				if cfg == nil {
					Skip("requires a kind cluster (set DHC_E2E=1 and -chart=" + s.Name + ")")
				}
				if selected.Name != s.Name {
					Skip("this run targets -chart=" + selected.Name)
				}
				fromVersion = os.Getenv("DHC_UPGRADE_FROM")
				fromValues = os.Getenv("DHC_UPGRADE_VALUES_FROM")
				if fromVersion == "" && fromValues == "" {
					Skip("not a bump PR — DHC_UPGRADE_FROM and DHC_UPGRADE_VALUES_FROM unset (Req 5.6)")
				}
			})

			It("installs the base state, upgrades to the proposed state, and re-asserts", func(ctx SpecContext) {
				r := cfg.Client().Resources(s.Namespace)

				By(fmt.Sprintf("install the currently pinned base state (chart version %q, values snapshot %q)", fromVersion, fromValues))
				Expect(helmDeploy(ctx, "install", s, fromVersion, fromValues)).To(Succeed())
				assertReadyHardened(ctx, r, s)

				By("helm upgrade to the proposed state and re-assert")
				Expect(helmDeploy(ctx, "upgrade", s, "", "")).To(Succeed())
				assertHealthy(ctx, r, s)
			})
		})
	}
})
