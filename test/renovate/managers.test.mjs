// Fixture test for the custom Renovate managers in renovate.json5 (Req 3.2).
//
// renovate-config-validator proves the config is *valid*; it does not prove the
// regex managers actually extract the right dependency from a definition. This
// runs each manager's matchStrings against the real definitions plus a
// synthetic fixture and asserts the captured datasource / depName / version /
// digest — so a regex that silently stops matching fails CI.
//
// Emulates Renovate's regex extraction: each matchString is a global regex with
// named groups; datasource comes from the manager's datasourceTemplate.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

// json5 ships with the renovate install; resolve it via CommonJS require so
// NODE_PATH (set by CI / local run) is honored, which ESM import ignores.
const require = createRequire(import.meta.url);
const JSON5 = require("json5");

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const config = JSON5.parse(readFileSync(join(root, "renovate.json5"), "utf8"));

// Extract deps the way Renovate would for one manager against one file.
function extract(manager, content) {
  const deps = [];
  for (const pattern of manager.matchStrings) {
    const re = new RegExp(pattern, "g");
    let m;
    while ((m = re.exec(content)) !== null) {
      const g = m.groups ?? {};
      deps.push({
        datasource: manager.datasourceTemplate,
        depName: g.depName,
        currentValue: g.currentValue,
        currentDigest: g.currentDigest,
      });
    }
  }
  return deps;
}

const read = (rel) => readFileSync(join(root, rel), "utf8");
const [sourceMgr, dockerMgr] = config.customManagers;

let failures = 0;
function check(name, cond, detail) {
  if (cond) {
    console.log(`ok   ${name}`);
  } else {
    console.log(`FAIL ${name}${detail ? `: ${detail}` : ""}`);
    failures++;
  }
}
const has = (deps, want) =>
  deps.some((d) =>
    Object.entries(want).every(([k, v]) => d[k] === v),
  );

// --- source manager: the upstream version knob ---
// Version-agnostic on purpose: a Renovate bump must NOT break this test, so it
// asserts the manager extracts the right depName + a well-formed tag/digest,
// never the exact pinned version (which changes on every bump).
const dep = (deps, want) => deps.find((d) => Object.entries(want).every(([k, v]) => d[k] === v));
// v-optional: some upstreams tag with a leading v (cert-manager), some without (valkey).
const isTag = (v) => /^v?\d+\.\d+\.\d+/.test(v ?? "");
const is64 = (h) => /^sha256:[a-f0-9]{64}$/.test(h ?? "");

const sHardened = extract(sourceMgr, read("image/hardened-app/image.yaml"));
{
  const d = dep(sHardened, { datasource: "github-tags", depName: "mm-weber/hardened-app" });
  check("source: hardened-app → github-tags mm-weber/hardened-app", !!d && isTag(d.currentValue), JSON.stringify(sHardened));
}
check("source: hardened-app yields exactly one dep", sHardened.length === 1, `${sHardened.length}`);

for (const role of ["controller", "webhook", "cainjector"]) {
  const deps = extract(sourceMgr, read(`image/cert-manager-${role}/image.yaml`));
  const d = dep(deps, { datasource: "github-tags", depName: "cert-manager/cert-manager" });
  check(`source: cert-manager-${role} → cert-manager/cert-manager`, !!d && isTag(d.currentValue), JSON.stringify(deps));
}

// valkey tags have no leading 'v' (#9.0.5) — proves the v-optional regex tracks it
{
  const deps = extract(sourceMgr, read("image/valkey/image.yaml"));
  const d = dep(deps, { datasource: "github-tags", depName: "valkey-io/valkey" });
  check("source: valkey → github-tags valkey-io/valkey (no-v tag)", !!d && isTag(d.currentValue), JSON.stringify(deps));
}

// generic owner/repo + a two-digit-minor tag, via a frozen fixture (safe to pin exactly)
const sOther = extract(sourceMgr, read("test/renovate/fixtures/other-owner.yaml"));
check(
  "source: fixture → grafana/grafana v11.2.0",
  has(sOther, { depName: "grafana/grafana", currentValue: "v11.2.0" }),
  JSON.stringify(sOther),
);
// the source manager must NOT capture the dhi.io lines
check(
  "source: ignores dhi.io build-layer lines",
  sOther.every((d) => d.depName && d.depName.includes("/") && !d.depName.startsWith("dhi.io")),
  JSON.stringify(sOther),
);

// --- docker manager: the dhc build layer (version-agnostic) ---
const dHardened = extract(dockerMgr, read("image/hardened-app/image.yaml"));
{
  const b = dep(dHardened, { datasource: "docker", depName: "dhi.io/build" });
  check(
    "docker: captures dhi.io/build with tag + digest",
    !!b && /^\d+-alpine3\.23$/.test(b.currentValue ?? "") && is64(b.currentDigest),
    JSON.stringify(dHardened),
  );
  const g = dep(dHardened, { datasource: "docker", depName: "dhi.io/golang" });
  check(
    "docker: captures dhi.io/golang builder with digest",
    !!g && /-alpine3\.23-dev$/.test(g.currentValue ?? "") && is64(g.currentDigest),
    JSON.stringify(dHardened),
  );
}
// every docker capture carries a digest (pinDigests invariant) and is a dhi.io image
check(
  "docker: every capture is a digest-pinned dhi.io image",
  dHardened.length > 0 && dHardened.every((d) => d.depName?.startsWith("dhi.io/") && is64(d.currentDigest)),
  JSON.stringify(dHardened),
);
// the docker manager must NOT capture upstream git sources or bare actions
check(
  "docker: ignores upstream git source + go/build actions",
  dHardened.every((d) => !d.depName?.includes("github.com") && !d.depName?.startsWith("go/")),
  JSON.stringify(dHardened),
);

if (failures > 0) {
  console.error(`\n${failures} test(s) failed`);
  process.exit(1);
}
console.log("\nall renovate manager tests passed");
