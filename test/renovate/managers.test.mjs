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
        // Custom capture groups first (the chart tag@digest manager composes
        // depName from registry+repository by template, so the parts must be
        // visible to assertions), then the fields Renovate itself derives.
        ...g,
        // A manager either captures the datasource from the file (the scanner
        // manager, whose `# renovate:` comment states it the way Renovate's own
        // inline convention does) or fixes it as a template.
        datasource: g.datasource ?? manager.datasourceTemplate,
        // A manager either captures depName from the file (the git-source and
        // docker managers) or states it as a template — constant (grafana
        // tarball) or composed from capture groups (chart tag@digest). This
        // emulation does not render templates; assertions check the template
        // string and the captured parts separately.
        depName: g.depName ?? manager.depNameTemplate,
        currentValue: g.currentValue,
        currentDigest: g.currentDigest,
      });
    }
  }
  return deps;
}

const read = (rel) => readFileSync(join(root, rel), "utf8");
const [sourceMgr, dockerMgr, grafanaMgr, scannerMgr, workflowMgr, chartDigestMgr, chartTagMgr, pipMgr, goBumpMgr, helmMgr] =
  config.customManagers;

// managerFilePatterns is the half extract() cannot exercise: a pattern that
// stops matching a file means Renovate silently reads nothing from it, with
// every matchString still green here. Renovate's /…/-delimited strings are
// regexes over repo-relative paths.
function filePatternMatches(manager, path) {
  return manager.managerFilePatterns.some((p) => {
    const re = /^\/(.*)\/$/.exec(p);
    return re ? new RegExp(re[1]).test(path) : p === path;
  });
}

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

// valkey tags have no leading 'v' (#9.0.5) — proves the v-optional regex tracks it.
// Both definitions, because the compat variant carries a byte-equal source pin and
// a bump has to move the pair: tracked separately they diverge, and the runtime
// and compat images stop being the same valkey.
for (const def of ["valkey", "valkey-compat"]) {
  const deps = extract(sourceMgr, read(`image/${def}/image.yaml`));
  const d = dep(deps, { datasource: "github-tags", depName: "valkey-io/valkey" });
  check(`source: ${def} → github-tags valkey-io/valkey (no-v tag)`, !!d && isTag(d.currentValue), JSON.stringify(deps));
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

// --- grafana manager: the tarball-repackage archetype (ADR 0002) ---
// Grafana ships a prebuilt tarball from dl.grafana.com, so there is no
// `git+https://…#vX.Y.Z` ref for the source manager to latch onto and Renovate
// tracked nothing. This manager reads the version out of the download url and
// looks it up against grafana/grafana releases — download host and version
// datasource are deliberately separate concerns.
const gGrafana = extract(grafanaMgr, read("image/grafana/image.yaml"));
{
  const d = dep(gGrafana, { datasource: "github-releases", depName: "grafana/grafana" });
  check(
    "grafana: tarball url → github-releases grafana/grafana",
    !!d && isTag(d.currentValue),
    JSON.stringify(gGrafana),
  );
  // the pinned url has no leading 'v'; upstream tags do — extractVersionTemplate
  // bridges that, so assert it is present and actually strips the prefix.
  const ev = grafanaMgr.extractVersionTemplate;
  const extractV = (tag) => (ev ? new RegExp(ev).exec(tag)?.groups?.version : undefined);
  check(
    "grafana: extractVersionTemplate strips upstream 'v' prefix",
    extractV("v13.1.1") === "13.1.1",
    `extractVersionTemplate=${ev}`,
  );
  // Grafana ships out-of-band fixes as semver build metadata
  // (v13.0.1+security-01, v12.4.3+security-02). Anchoring extractVersion at
  // the patch digit silently drops every one of them, so a security release
  // would never reach us.
  check(
    "grafana: extractVersionTemplate keeps the +security build suffix",
    extractV("v13.0.1+security-01") === "13.0.1+security-01",
    `extractVersionTemplate=${ev}`,
  );
  // …without letting junk tags through: grafana/grafana carries a stray
  // `vtest-new-release-pipeline` tag that the releases feed does not list.
  check(
    "grafana: extractVersionTemplate rejects non-version tags",
    extractV("vtest-new-release-pipeline") === undefined,
    `extractVersionTemplate=${ev}`,
  );
}
check("grafana: yields exactly one dep", gGrafana.length === 1, `${gGrafana.length}`);

// A definition pinned to an out-of-band security build must stay tracked — the
// same one url shape carries it, so the manager keeps matching and the next
// release stays visible.
{
  const deps = extract(grafanaMgr, read("test/renovate/fixtures/grafana-security-pin.yaml"));
  const d = dep(deps, { datasource: "github-releases", depName: "grafana/grafana" });
  check(
    "grafana: security-pinned definition stays tracked",
    d?.currentValue === "13.0.1+security-01",
    JSON.stringify(deps),
  );
  check("grafana: security pin yields exactly one dep", deps.length === 1, `${deps.length}`);
}

// no cross-talk in either direction: the git-source manager must ignore the
// tarball url, and the grafana manager must ignore git-source definitions.
check(
  "grafana: source manager ignores the dl.grafana.com tarball",
  extract(sourceMgr, read("image/grafana/image.yaml")).length === 0,
  JSON.stringify(extract(sourceMgr, read("image/grafana/image.yaml"))),
);
for (const other of ["cert-manager-controller", "hardened-app", "valkey", "valkey-compat"]) {
  const deps = extract(grafanaMgr, read(`image/${other}/image.yaml`));
  check(`grafana: manager ignores ${other}`, deps.length === 0, JSON.stringify(deps));
}
// the build layer is still tracked in the grafana definition (it has a
// `# syntax=` pin like every other image) — the new manager must not shadow it.
check(
  "grafana: docker manager still captures its dhi.io build layer",
  extract(dockerMgr, read("image/grafana/image.yaml")).some(
    (d) => d.depName === "dhi.io/build" && is64(d.currentDigest),
  ),
  JSON.stringify(extract(dockerMgr, read("image/grafana/image.yaml"))),
);

// --- grafana versioning: out-of-band security builds must sort as upgrades ---
// Under plain semver, build metadata is IGNORED for precedence: 13.0.1 and
// 13.0.1+security-01 rank equal, so Renovate would report us up to date right
// through a security release — the exact failure this catalogue exists to
// prevent. Asserted against renovate's own versioning implementation rather
// than a reading of the docs, because the docs are easy to misread: the
// `revision` capture group is only honoured when `build` is also present.
{
  let getVersioning;
  try {
    ({ get: getVersioning } = require("renovate/dist/modules/versioning/index.js"));
  } catch (e) {
    check("grafana versioning: renovate versioning module loadable", false, `${e.message} — path moved on a renovate major?`);
  }
  const scheme = grafanaMgr.versioningTemplate;
  check("grafana: manager declares a versioningTemplate", !!scheme, `versioningTemplate=${scheme}`);
  if (getVersioning && scheme) {
    const api = getVersioning(scheme);
    const gt = (b, a, want) =>
      check(`grafana versioning: ${b} > ${a} === ${want}`, api.isGreaterThan(b, a) === want);

    // the bug this scheme exists to fix
    gt("13.0.1+security-01", "13.0.1", true);
    // successive security builds on the same base
    gt("13.0.1+security-02", "13.0.1+security-01", true);
    gt("13.0.1+security-10", "13.0.1+security-09", true);
    // a later regular patch supersedes a security build (grafana's real pattern:
    // v13.0.1+security-01 was followed by v13.0.2)
    gt("13.0.2", "13.0.1+security-01", true);
    // and ordinary ordering is untouched
    gt("13.1.1", "13.0.4", true);
    gt("13.0.4", "13.1.1", false);
    gt("13.0.1", "13.0.1+security-01", false);

    for (const [v, want] of [
      ["13.0.4", true],
      ["13.0.1+security-01", true],
      ["v13.0.1", false], // extractVersion has already stripped the prefix
      ["vtest-new-release-pipeline", false],
    ]) {
      check(`grafana versioning: isValid(${v}) === ${want}`, api.isValid(v) === want);
    }
  }
}

// --- quarantine and automerge truth (Req 3.5, 3.7; task 11.1) ---------------
// The age rule is the whole quarantine: one datasource-scoped packageRule.
// Its shape is asserted here because a rule that silently loses a datasource
// or gains matchUpdateTypes stops aging exactly the bumps it should. Whether a
// datasource can be aged at all is a property of the pinned renovate/dist
// (releaseTimestampSupport); the offline harness cannot observe network
// timestamps, so that flag is the strongest local evidence (review 1.7).
{
  const ageRules = config.packageRules.filter((r) => r.minimumReleaseAge !== undefined);
  check("quarantine: exactly one packageRule carries minimumReleaseAge", ageRules.length === 1, `${ageRules.length}`);
  const age = ageRules[0] ?? {};
  check('quarantine: minimumReleaseAge is "3 days"', age.minimumReleaseAge === "3 days", `${age.minimumReleaseAge}`);
  check('quarantine: a release without a timestamp waits (timestamp-required)', age.minimumReleaseAgeBehaviour === "timestamp-required", `${age.minimumReleaseAgeBehaviour}`);
  const aged = ["github-tags", "github-releases", "npm", "pypi", "helm", "go"];
  check("quarantine: every third-party version datasource is aged", JSON.stringify([...(age.matchDatasources ?? [])].sort()) === JSON.stringify([...aged].sort()), `${age.matchDatasources}`);
  check("quarantine: docker is exempt (catalogue digests and the build layer flow same-day)", !(age.matchDatasources ?? []).includes("docker"));
  check("quarantine: no matchUpdateTypes, so minors and majors age too", age.matchUpdateTypes === undefined, `${age.matchUpdateTypes}`);
  check("quarantine: the age rule is not the automerge rule", age.automerge === undefined);

  let getDatasources;
  try {
    ({ getDatasources } = require("renovate/dist/modules/datasource/index.js"));
  } catch (e) {
    check("quarantine: renovate datasource module loadable", false, `${e.message}: path moved on a renovate major?`);
  }
  if (getDatasources) {
    const ds = getDatasources();
    for (const name of aged) {
      const d = ds.get(name);
      check(`quarantine: datasource ${name} exists in the pinned renovate`, !!d);
      check(`quarantine: datasource ${name} reports release timestamps (releaseTimestampSupport)`, d?.releaseTimestampSupport === true, `${d?.releaseTimestampSupport}`);
    }
  }

  // Req 3.5 and 3.12, the decided scope: automerge is patch and digest of
  // the github-tags datasource, and digest-only bumps of the catalogue's own
  // image pins under chart/; nothing else in the config says automerge: true.
  const automerging = config.packageRules.filter((r) => r.automerge === true);
  check("automerge: exactly two rules enable it", automerging.length === 2, `${automerging.length}`);
  const am = automerging.find((r) => JSON.stringify(r.matchDatasources) === JSON.stringify(["github-tags"])) ?? {};
  check("automerge: one is scoped to github-tags (compile-from-source upstreams)", !!am.matchDatasources, JSON.stringify(automerging));
  check("automerge: patch and digest only", JSON.stringify([...(am.matchUpdateTypes ?? [])].sort()) === JSON.stringify(["digest", "patch"]), `${am.matchUpdateTypes}`);
  const chartDigests = automerging.find((r) => JSON.stringify(r.matchDatasources) === JSON.stringify(["docker"])) ?? {};
  check("automerge: the other is docker digest-only", JSON.stringify(chartDigests.matchUpdateTypes) === JSON.stringify(["digest"]), `${chartDigests.matchUpdateTypes}`);
  check("automerge: scoped to the catalogue's own images", JSON.stringify(chartDigests.matchPackageNames) === JSON.stringify(["ghcr.io/mm-weber/dhc/**"]), `${chartDigests.matchPackageNames}`);
  const buildLayer = config.packageRules.findIndex((r) => r.groupName === "dhi.io build layer");
  check("automerge: the build-layer rule (automerge: false) is ordered after the digest rule, so it wins", buildLayer > config.packageRules.indexOf(chartDigests) && config.packageRules[buildLayer].automerge === false, `${buildLayer}`);
  check("automerge: the config's top level does not enable it", config.automerge !== true);
  const repackage = config.packageRules.find((r) => JSON.stringify(r.matchDepNames) === JSON.stringify(["grafana/grafana"]) && r.automerge === false);
  check("automerge: the repackage rule says automerge: false explicitly", !!repackage);
  const helmRule = config.packageRules.find((r) => JSON.stringify(r.matchDatasources) === JSON.stringify(["helm"]) && r.automerge === false);
  check("automerge: a chart release is never automerged, stated (Req 3.11)", !!helmRule);
}

// --- upstream chart versions (Req 3.11; task 11.4) ---------------------------
// The three upstream charts are pinned in chart/<name>/chart.yaml. The manager
// must capture the chart name, the pinned version and, as the registryUrl, the
// chart repository: the helm datasource's default registry is a frozen decoy
// (independent review 1.8), so a lost registryUrl reports every chart up to
// date forever. hardened-app's own Chart.yaml is not an upstream pin.
//
// The pinned version is read out of the file rather than written here: the
// bump PR this manager opens changes that line, and a fixture carrying the
// old literal turned every chart bump red (#167, #168, 2026-09-08). What the
// fixture proves is that the manager captures exactly what the file pins and
// that the value has a version's shape, not which version it is today.
{
  check("charts: a tenth custom manager tracks the upstream chart versions", !!helmMgr && helmMgr.datasourceTemplate === "helm", JSON.stringify(helmMgr));
  const pinnedVersion = (text) => (text.match(/^\s*version:\s*"?([^\s"'#]+)/m) ?? [])[1];
  const isChartVersion = (v) => /^v?[0-9]+\.[0-9]+\.[0-9]+$/.test(v ?? "");
  for (const [file, name, registry] of [
    ["chart/cert-manager/chart.yaml", "cert-manager", "https://charts.jetstack.io"],
    ["chart/grafana/chart.yaml", "grafana", "https://grafana.github.io/helm-charts"],
    ["chart/valkey/chart.yaml", "valkey", "https://valkey-io.github.io/valkey-helm"],
  ]) {
    check(`charts: manager file pattern matches ${file}`, !!helmMgr && filePatternMatches(helmMgr, file));
    const text = read(file);
    const version = pinnedVersion(text);
    check(`charts: ${file} pins a semver chart version`, isChartVersion(version), `${version}`);
    const deps = helmMgr ? extract(helmMgr, text) : [];
    check(`charts: ${name} yields exactly one dep`, deps.length === 1, `${deps.length}`);
    const d = deps[0] ?? {};
    check(`charts: ${name} tracked by chart name`, d.depName === name, `${d.depName}`);
    check(`charts: ${name} pinned version captured as the file pins it (${version})`, d.currentValue === version, `${d.currentValue}`);
    check(`charts: ${name} repository captured as the registryUrl`, d.registryUrl === registry, `${d.registryUrl}`);
  }
  check("charts: hardened-app's own Chart.yaml is not captured (case differs, it is ours)", !!helmMgr && !filePatternMatches(helmMgr, "chart/hardened-app/Chart.yaml"));
  check("charts: a values file is not a chart pin", !!helmMgr && !filePatternMatches(helmMgr, "chart/grafana/config/values-hardened.yaml"));
}

// --- scanner pins (Req 7.5, 7.6) --------------------------------------------
// The gate's own trivy and grype are pinned by version + sha256. If this manager
// silently stops matching, nothing bumps them, and a stale scanner reports fewer
// findings without ever reporting that it is stale — a green gate that means
// less than it did last month. That is the exact silent failure Req 7.6 exists
// to prevent, which is why the pin format is asserted here as well as in
// scripts/install-scanners_test.sh.
{
  const pins = extract(scannerMgr, read("scripts/install-scanners.sh"));
  check("scanner: yields exactly two deps", pins.length === 2, `${pins.length}`);

  for (const [tool, depName] of [
    ["trivy", "aquasecurity/trivy"],
    ["grype", "anchore/grype"],
  ]) {
    const dep = pins.find((d) => d.depName === depName);
    check(`scanner: ${tool} is tracked as ${depName}`, !!dep);
    check(
      `scanner: ${tool} resolves against github-releases`,
      dep?.datasource === "github-releases",
      dep?.datasource,
    );
    check(
      `scanner: ${tool} pin is bare semver (no v prefix)`,
      /^\d+\.\d+\.\d+$/.test(dep?.currentValue ?? ""),
      dep?.currentValue,
    );
  }

  // Upstream tags are v-prefixed and our pins are bare, so extractVersion has to
  // bridge them. Get this wrong and Renovate compares "v0.73.0" against "0.72.0"
  // as strings and either never bumps or bumps to a value the script cannot use.
  const ev = new RegExp(scannerMgr.extractVersionTemplate);
  check(
    "scanner: extractVersion strips the v prefix",
    ev.exec("v0.72.0")?.groups?.version === "0.72.0",
  );
  check("scanner: extractVersion rejects an unprefixed tag", ev.exec("0.72.0") === null);
}

// --- tool pins: kind + kyverno via the same manager (Req 7.5, 7.6) -----------
// install-tool.sh carries the same pin-block shape as install-scanners.sh and
// the same manager reads both files — kyverno is the Req 4.6 policy engine, so
// a pin nobody bumps silently stops gaining checks while every gate stays
// green (issue #55).
{
  for (const [file, tools] of [
    ["scripts/install-scanners.sh", ["trivy", "grype"]],
    ["scripts/install-tool.sh", ["kind", "kyverno"]],
  ]) {
    check(
      `tool pins: manager file pattern matches ${file}`,
      filePatternMatches(scannerMgr, file),
      JSON.stringify(scannerMgr.managerFilePatterns),
    );
  }

  const pins = extract(scannerMgr, read("scripts/install-tool.sh"));
  // Every pinned tool, counted: a pin the manager does not see is a pin nobody
  // bumps, and a stale tool fails silently (Req 7.6). syft joined with the
  // release arm's per-manifest SBOMs (task 9.1), crane with the rescan's
  // enumeration (9.3), vexctl with the rescan's re-attestation merge (10.3),
  // tag enumeration (task 9.3).
  check("tool pins: install-tool.sh yields exactly seven deps", pins.length === 7, `${pins.length}`);

  for (const [tool, depName] of [
    ["kind", "kubernetes-sigs/kind"],
    ["kyverno", "kyverno/kyverno"],
    ["helm", "helm/helm"],
    ["ct", "helm/chart-testing"],
    ["syft", "anchore/syft"],
    ["crane", "google/go-containerregistry"],
    ["vexctl", "openvex/vexctl"],
  ]) {
    const dep = pins.find((d) => d.depName === depName);
    check(`tool pins: ${tool} is tracked as ${depName}`, !!dep);
    check(
      `tool pins: ${tool} resolves against github-releases`,
      dep?.datasource === "github-releases",
      dep?.datasource,
    );
    // Bare, like trivy/grype, so the shared extractVersionTemplate bridges the
    // v-prefixed upstream tags — both projects tag vX.Y.Z.
    check(
      `tool pins: ${tool} pin is bare semver (no v prefix)`,
      /^\d+\.\d+\.\d+$/.test(dep?.currentValue ?? ""),
      dep?.currentValue,
    );
  }
}

// --- workflow env pins: govulncheck + renovate/json5 (Req 7.5, 7.6) ----------
// The pins whose checksum control lives outside this repo (Go sumdb, npm
// registry integrity) sit as env vars in the workflows themselves, under the
// same `# renovate:` comment convention in YAML assignment form (issue #63
// recorded the pins; this manager is what keeps them from staling, issue #55).
{
  for (const wf of ["build.yml", "validate.yml"]) {
    check(
      `workflow pins: file pattern matches .github/workflows/${wf}`,
      filePatternMatches(workflowMgr, `.github/workflows/${wf}`),
      JSON.stringify(workflowMgr.managerFilePatterns),
    );
  }

  const build = extract(workflowMgr, read(".github/workflows/build.yml"));
  {
    const d = dep(build, { datasource: "go", depName: "golang.org/x/vuln" });
    // v-prefixed, matching the go datasource's native version format — this
    // manager deliberately has no extractVersionTemplate to bridge anything.
    check(
      "workflow pins: govulncheck → go golang.org/x/vuln, v-prefixed",
      !!d && /^v\d+\.\d+\.\d+$/.test(d.currentValue ?? ""),
      JSON.stringify(build),
    );
  }
  check("workflow pins: build.yml yields exactly one dep", build.length === 1, `${build.length}`);

  const validate = extract(workflowMgr, read(".github/workflows/validate.yml"));
  for (const [name, re] of [
    ["renovate", /^\d+\.\d+\.\d+$/],
    ["json5", /^\d+\.\d+\.\d+$/],
  ]) {
    const d = dep(validate, { datasource: "npm", depName: name });
    check(
      `workflow pins: ${name} → npm, bare semver`,
      !!d && re.test(d.currentValue ?? ""),
      JSON.stringify(validate),
    );
  }
  check(
    "workflow pins: validate.yml yields exactly two deps",
    validate.length === 2,
    `${validate.length}`,
  );

  // The other direction: env vars without a marker comment stay invisible.
  // e2e.yml is all unmarked env (CLUSTER, PROBE_IMAGE, …) now that the kind
  // pin lives in install-tool.sh.
  const e2e = extract(workflowMgr, read(".github/workflows/e2e.yml"));
  check("workflow pins: unmarked workflow env is ignored", e2e.length === 0, JSON.stringify(e2e));
}

// --- chart image pins: the values files the charts deploy with (Req 4.2, 7.6) --
// A definition bump publishes a new image, but until task 8.7 nothing read
// chart/, so the deployed pins silently fell behind what the catalogue
// publishes (issue #64: cert-manager a version behind, grafana two, valkey and
// hardened-app behind on digest alone). Two spellings, one manager each:
// repository/tag/digest on separate keys (cert-manager ×3, hardened-app) and
// tag@digest in one value under registry/repository (grafana, valkey — the
// grafana chart strips the @sha… suffix for its version label itself, which is
// why the awkward bare-hex `sha:` field could be retired).
{
  const isChartTag = (v) => /^\d+\.\d+\.\d+-alpine\d+\.\d+(-[a-z0-9]+)?$/.test(v ?? "");

  for (const [mgr, name, file] of [
    [chartDigestMgr, "digest-keyed", "chart/cert-manager/config/values-hardened.yaml"],
    [chartDigestMgr, "digest-keyed", "chart/hardened-app/values.yaml"],
    [chartTagMgr, "tag@digest", "chart/grafana/config/values-hardened.yaml"],
    [chartTagMgr, "tag@digest", "chart/valkey/config/values-hardened.yaml"],
  ]) {
    check(
      `chart pins: ${name} manager file pattern matches ${file}`,
      !!mgr && filePatternMatches(mgr, file),
      mgr && JSON.stringify(mgr.managerFilePatterns),
    );
  }

  // cert-manager: all three images, tracked with tag AND digest so both a
  // version bump and a same-tag rebuild (digest drift) reach the chart.
  const cm = chartDigestMgr ? extract(chartDigestMgr, read("chart/cert-manager/config/values-hardened.yaml")) : [];
  check("chart pins: cert-manager yields exactly three deps", cm.length === 3, `${cm.length}`);
  for (const role of ["controller", "webhook", "cainjector"]) {
    const d = dep(cm, { datasource: "docker", depName: `ghcr.io/mm-weber/dhc/cert-manager-${role}` });
    check(
      `chart pins: cert-manager-${role} tracked with tag + digest`,
      !!d && isChartTag(d.currentValue) && is64(d.currentDigest),
      JSON.stringify(cm),
    );
  }

  // hardened-app: the owned chart's baked-in values carry the same spelling.
  const ha = chartDigestMgr ? extract(chartDigestMgr, read("chart/hardened-app/values.yaml")) : [];
  {
    const d = dep(ha, { datasource: "docker", depName: "ghcr.io/mm-weber/dhc/hardened-app" });
    check(
      "chart pins: hardened-app tracked with tag + digest",
      !!d && isChartTag(d.currentValue) && is64(d.currentDigest),
      JSON.stringify(ha),
    );
  }
  check("chart pins: hardened-app yields exactly one dep", ha.length === 1, `${ha.length}`);

  // grafana + valkey: registry/repository on separate keys, digest riding on
  // the tag. depName is composed from both keys by template.
  for (const [name, file, compat] of [
    ["grafana", "chart/grafana/config/values-hardened.yaml", ""],
    ["valkey", "chart/valkey/config/values-hardened.yaml", "-compat"],
  ]) {
    const deps = chartTagMgr ? extract(chartTagMgr, read(file)) : [];
    const d = deps[0];
    check(
      `chart pins: ${name} tag@digest tracked with tag + digest`,
      !!d && d.datasource === "docker" && isChartTag(d.currentValue) && is64(d.currentDigest),
      JSON.stringify(deps),
    );
    check(
      `chart pins: ${name} depName composed as ghcr.io/mm-weber/dhc/${name}`,
      !!chartTagMgr &&
        chartTagMgr.depNameTemplate === "{{{registry}}}/{{{repository}}}" &&
        d?.registry === "ghcr.io" &&
        d?.repository === `mm-weber/dhc/${name}`,
      JSON.stringify({ template: chartTagMgr?.depNameTemplate, dep: d }),
    );
    check(
      `chart pins: ${name} pin keeps its compatibility suffix${compat && ` (${compat})`}`,
      !!d && (d.currentValue ?? "").endsWith(`-alpine3.23${compat}`),
      d?.currentValue,
    );
    check(`chart pins: ${name} yields exactly one dep`, deps.length === 1, `${deps.length}`);
  }

  // The other direction: neither chart manager may read image definitions
  // (the docker manager owns those), and the digest-keyed manager must not
  // double-capture the tag@digest files or vice versa.
  for (const mgr of [chartDigestMgr, chartTagMgr]) {
    check(
      "chart pins: managers do not read image definitions",
      !!mgr && !filePatternMatches(mgr, "image/grafana/image.yaml"),
      mgr && JSON.stringify(mgr.managerFilePatterns),
    );
  }
  check(
    "chart pins: digest-keyed manager ignores tag@digest files",
    chartDigestMgr && extract(chartDigestMgr, read("chart/grafana/config/values-hardened.yaml")).length === 0,
    chartDigestMgr && JSON.stringify(extract(chartDigestMgr, read("chart/grafana/config/values-hardened.yaml"))),
  );
  check(
    "chart pins: tag@digest manager ignores digest-keyed files",
    chartTagMgr && extract(chartTagMgr, read("chart/cert-manager/config/values-hardened.yaml")).length === 0,
    chartTagMgr && JSON.stringify(extract(chartTagMgr, read("chart/cert-manager/config/values-hardened.yaml"))),
  );
}

// --- CI python pins: the hash-verified requirements file (Req 7.5, 7.6) ------
// yamllint is the Req 7.2 gate, yamale serves ct lint, pyyaml/pathspec are
// their pinned transitive deps (issue #74). The manager bumps versions only;
// the --hash set stays behind for a human, so extraction losing a dep means
// that pin silently stales — the exact failure this file exists to catch.
{
  check(
    "pip pins: manager file pattern matches .github/requirements-ci.txt",
    !!pipMgr && filePatternMatches(pipMgr, ".github/requirements-ci.txt"),
    pipMgr && JSON.stringify(pipMgr.managerFilePatterns),
  );

  const pip = pipMgr ? extract(pipMgr, read(".github/requirements-ci.txt")) : [];
  check("pip pins: requirements-ci.txt yields exactly four deps", pip.length === 4, `${pip.length}`);
  for (const name of ["yamllint", "yamale", "pathspec", "pyyaml"]) {
    const d = dep(pip, { datasource: "pypi", depName: name });
    check(
      `pip pins: ${name} → pypi, bare PEP 440 pin`,
      !!d && /^\d+(\.\d+)+$/.test(d.currentValue ?? ""),
      JSON.stringify(pip),
    );
  }

  // The other direction: the --hash continuation lines must contribute no
  // deps of their own, and the manager reads nothing but the requirements
  // file (the pin scripts and workflows have their own managers above).
  check(
    "pip pins: hash lines add no phantom deps",
    pip.every((d) => d.depName && !d.depName.startsWith("--")),
    JSON.stringify(pip),
  );
  for (const other of ["scripts/install-tool.sh", ".github/workflows/validate.yml"]) {
    check(
      `pip pins: manager does not read ${other}`,
      !!pipMgr && !filePatternMatches(pipMgr, other),
      pipMgr && JSON.stringify(pipMgr.managerFilePatterns),
    );
  }
}

// --- go/bump security pins inside definitions (Req 7.6; LOG 2026-09-02) ----
// The between-releases CVE patch lane: a module bumped in the frontend fetch
// phase is a real pin, and a pin the manager does not see is a pin nobody
// retires when upstream catches up.
{
  for (const role of ["controller", "webhook", "cainjector"]) {
    const deps = extract(goBumpMgr, read(`image/cert-manager-${role}/image.yaml`));
    check(
      `go-bump pins: cert-manager-${role} tracks golang.org/x/crypto via go datasource`,
      has(deps, { depName: "golang.org/x/crypto", datasource: "go" }),
      JSON.stringify(deps),
    );
    const d = dep(deps, { depName: "golang.org/x/crypto" });
    check(
      `go-bump pins: cert-manager-${role} pin is v-prefixed semver`,
      /^v\d+\.\d+\.\d+$/.test(d?.currentValue ?? ""),
      d?.currentValue,
    );
  }
  for (const role of ["controller", "webhook"]) {
    const deps = extract(goBumpMgr, read(`image/cert-manager-${role}/image.yaml`));
    check(
      `go-bump pins: cert-manager-${role} tracks google.golang.org/grpc`,
      has(deps, { depName: "google.golang.org/grpc", datasource: "go" }),
      JSON.stringify(deps),
    );
  }
  check(
    "go-bump pins: cainjector carries no grpc pin (no grpc in its module)",
    !has(extract(goBumpMgr, read("image/cert-manager-cainjector/image.yaml")), { depName: "google.golang.org/grpc" }),
  );
  check(
    "go-bump pins: manager reads definition files",
    filePatternMatches(goBumpMgr, "image/cert-manager-controller/image.yaml"),
  );
  check(
    "go-bump pins: nothing hides in the repackage archetype (grafana)",
    extract(goBumpMgr, read("image/grafana/image.yaml")).length === 0,
    JSON.stringify(extract(goBumpMgr, read("image/grafana/image.yaml"))),
  );
}

// --- the tracking scope (task 14.2; Req 1.14, 3.2, 3.11) --------------------
// Renovate cannot read catalogue-policy.yaml, so scripts/render-tracking.sh
// renders the active set into the delimited ignorePaths block. Three things
// are worth proving here: the committed block matches the active set, a
// deactivation renders the paths one expects, and Renovate's OWN file filter
// (the function the extract phase runs before any manager reads a file)
// drops every package file under them.
{
  const { spawnSync } = require("node:child_process");
  const { mkdtempSync, cpSync, writeFileSync, rmSync } = require("node:fs");
  const { tmpdir } = require("node:os");
  check("tracking scope: the committed block is an ignorePaths array", Array.isArray(config.ignorePaths), JSON.stringify(config.ignorePaths));
  const chk = spawnSync(join(root, "scripts/render-tracking.sh"), ["--check", root], { encoding: "utf8" });
  check("tracking scope: the committed block matches the active set (render-tracking --check)", chk.status === 0, `${chk.stdout}${chk.stderr}`);
  // The reference instance activates everything (design Decision 11), so it ignores nothing.
  check("tracking scope: the reference instance ignores no path", (config.ignorePaths ?? []).length === 0, JSON.stringify(config.ignorePaths));

  const sb = mkdtempSync(join(tmpdir(), "dhc-tracking-"));
  for (const d of ["image", "chart"]) cpSync(join(root, d), join(sb, d), { recursive: true });
  cpSync(join(root, "renovate.json5"), join(sb, "renovate.json5"));
  const policy = read("catalogue-policy.yaml");
  check("tracking scope: the fixture deactivates a listed definition", policy.includes("  - grafana\n"));
  writeFileSync(join(sb, "catalogue-policy.yaml"), policy.replace("  - grafana\n", ""));
  const r = spawnSync(join(root, "scripts/render-tracking.sh"), [sb], { encoding: "utf8" });
  check("tracking scope: rendering with grafana inactive exits 0", r.status === 0, `${r.stdout}${r.stderr}`);
  let rendered;
  try {
    rendered = JSON5.parse(readFileSync(join(sb, "renovate.json5"), "utf8"));
    check("tracking scope: the rendered block is JSON5 the config loader reads", true);
  } catch (e) {
    check("tracking scope: the rendered block is JSON5 the config loader reads", false, e.message);
  }
  const want = ["image/grafana/**", "chart/grafana/**"];
  check(
    "tracking scope: the inactive definition's directory and the chart deploying only it are ignored",
    !!rendered && JSON.stringify(rendered.ignorePaths) === JSON.stringify(want),
    JSON.stringify(rendered?.ignorePaths),
  );
  try {
    const fm = require("renovate/dist/workers/repository/extract/file-match.js");
    const files = [
      "image/grafana/image.yaml",
      "chart/grafana/chart.yaml",
      "chart/grafana/config/values-hardened.yaml",
      "image/valkey/image.yaml",
      "chart/valkey/config/values-hardened.yaml",
      "scripts/install-tool.sh",
    ];
    const kept = fm.getFilteredFileList({ ignorePaths: rendered?.ignorePaths ?? [] }, files);
    check(
      "tracking scope: renovate's own file filter drops every package file under an ignored path (measured 41.173.1)",
      JSON.stringify(kept) === JSON.stringify(["image/valkey/image.yaml", "chart/valkey/config/values-hardened.yaml", "scripts/install-tool.sh"]),
      JSON.stringify(kept),
    );
    const none = fm.getFilteredFileList({ ignorePaths: [] }, files);
    check("tracking scope: an empty block ignores nothing", none.length === files.length, JSON.stringify(none));
  } catch (e) {
    check("tracking scope: renovate file-match module loadable", false, `${e.message}: path moved on a renovate major?`);
  }
  rmSync(sb, { recursive: true, force: true });
}

if (failures > 0) {
  console.error(`\n${failures} test(s) failed`);
  process.exit(1);
}
console.log("\nall renovate manager tests passed");
