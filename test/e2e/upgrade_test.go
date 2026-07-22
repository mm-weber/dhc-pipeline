package e2e

import (
	"os"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// The upgrade-path spec verifies Req 5.6: on a component bump the workflow (task
// 6.5) passes DHC_UPGRADE_FROM=<base version>, and the suite installs that
// currently-pinned version, upgrades to the proposed (PR) version, and
// re-asserts readiness, the restricted securityContext, and the functional
// probe. It is mutually exclusive with the install spec (which skips when
// DHC_UPGRADE_FROM is set), so a run never installs the same release twice.
// Scoped to adapted charts, whose upgrade is a chart --version change; owned
// image-digest upgrades are a follow-up.
var _ = Describe("hardened catalogue component upgrade path", func() {
	for _, s := range componentSpecs {
		s := s
		Context(s.Name, func() {
			var fromVersion string
			BeforeEach(func() {
				if cfg == nil {
					Skip("requires a kind cluster (set DHC_E2E=1 and -chart=" + s.Name + ")")
				}
				if selected.Name != s.Name {
					Skip("this run targets -chart=" + selected.Name)
				}
				if s.Owned {
					Skip("upgrade-path covers adapted (chart-versioned) components; owned image bumps are a follow-up")
				}
				fromVersion = os.Getenv("DHC_UPGRADE_FROM")
				if fromVersion == "" {
					Skip("not a bump PR — DHC_UPGRADE_FROM unset (Req 5.6)")
				}
			})

			It("installs the base version, upgrades to the proposed version, and re-asserts", func(ctx SpecContext) {
				r := cfg.Client().Resources(s.Namespace)

				By("install the currently pinned base version " + fromVersion)
				Expect(helmDeploy(ctx, "install", s, fromVersion)).To(Succeed())
				assertReadyHardened(ctx, r, s)

				By("helm upgrade to the proposed version and re-assert")
				Expect(helmDeploy(ctx, "upgrade", s, "")).To(Succeed())
				assertHealthy(ctx, r, s)
			})
		})
	}
})
