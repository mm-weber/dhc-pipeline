package inputs

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSupported(t *testing.T) {
	dir := t.TempDir()
	const (
		repo  = "ghcr.io/acme/dhc/grafana"
		index = "sha256:837727cbdb7058ee72e8a67c78cd2110677746127cc4da969abc2733ec514569"
		amd   = "sha256:cc46dc5b6979328a9cadc135f3877d1b1ee15b5eb1d7f085557853329d898170"
		arm   = "sha256:5cd9002a2e453d1134f8f028bb173cab19a3870171dbba5ce85baf6da2791690"
		old   = "sha256:6e3918484d9b4257881a0411268d55519f1c2abcbe5d1775fb79e4798e4b817d"
	)
	tsv := repo + "\t13.1.5-alpine3.23\t" + index + "\tlinux/amd64\t" + amd + "\tsupported\n" +
		repo + "\t13-alpine3.23\t" + index + "\tlinux/amd64\t" + amd + "\tsupported\n" +
		repo + "\t13.1.5-alpine3.23\t" + index + "\tlinux/arm64\t" + arm + "\tsupported\n" +
		repo + "\t13.1.2-alpine3.23\t" + old + "\tlinux/amd64\tsha256:5d2e\tsuperseded\n"
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(os.WriteFile(filepath.Join(dir, "enumeration.tsv"), []byte(tsv), 0o644))
	must(os.MkdirAll(filepath.Join(dir, "reattest", "grafana__837727cbdb70", "out"), 0o755))
	must(os.WriteFile(filepath.Join(dir, "reattest", "grafana__837727cbdb70", "out", "grafana.openvex.json"),
		[]byte(`{"@id":"x","statements":[{"vulnerability":{"name":"CVE-1"},"status":"affected","timestamp":"2026-09-03T00:00:00Z"}]}`), 0o644))
	must(os.MkdirAll(filepath.Join(dir, "trivy"), 0o755))
	must(os.WriteFile(filepath.Join(dir, "trivy", "grafana__837727cbdb70__linux-amd64.json"),
		[]byte(`{"CreatedAt":"2026-09-05T06:00:00Z","ArtifactName":"`+repo+`@`+amd+`","Results":[]}`), 0o644))
	must(os.MkdirAll(filepath.Join(dir, "vex"), 0o755))
	must(os.WriteFile(filepath.Join(dir, "vex", "grafana__837727cbdb70.report.json"), []byte(`{"image":"grafana","digest":"","compiled":0}`), 0o644))

	ds, err := LoadSupported(filepath.Join(dir, "enumeration.tsv"), filepath.Join(dir, "reattest"), filepath.Join(dir, "trivy"), filepath.Join(dir, "vex"))
	must(err)
	if len(ds) != 1 {
		t.Fatalf("one supported digest, the superseded row skipped; got %+v", ds)
	}
	d := ds[0]
	if d.Repository != repo || d.Digest != index || len(d.Tags) != 2 || len(d.Manifests) != 2 || d.Manifests[1] != arm {
		t.Errorf("tags and platform manifests deduplicated from the enumeration: %+v", d)
	}
	if len(d.Platforms) != 2 || d.Platforms[0] != "linux/amd64" || d.Platforms[1] != "linux/arm64" {
		t.Errorf("platforms read from the enumeration, deduplicated, in order (Req 6.61): %+v", d.Platforms)
	}
	if d.Document == nil || d.Document.Statements[0].Vulnerability.Name != "CVE-1" {
		t.Errorf("the attested document is read by the work-directory naming: %+v", d.Document)
	}
	if len(d.Reports) != 1 || d.Reports[0].ArtifactName != repo+"@"+amd {
		t.Errorf("reports are read by the <name>__<12 hex>__ prefix: %+v", d.Reports)
	}
	if !d.VEXUnresolved {
		t.Errorf("a compile report with an empty digest marks the VEX unresolved")
	}
	if _, err := LoadSupported(filepath.Join(dir, "enumeration.tsv"), "", filepath.Join(dir, "trivy"), ""); err != nil {
		t.Errorf("documents and compile reports are optional: %v", err)
	}
	must(os.WriteFile(filepath.Join(dir, "trivy", "grafana__837727cbdb70__linux-arm64.json"), []byte("not json"), 0o644))
	if _, err := LoadSupported(filepath.Join(dir, "enumeration.tsv"), "", filepath.Join(dir, "trivy"), ""); err == nil {
		t.Errorf("a report that does not parse is an error, not an empty input")
	}
}

// The catalogue page's inputs (Req 6.61; task 15.8).

func TestLoadDefinitions(t *testing.T) {
	dir := t.TempDir()
	tsv := "grafana\tactive\tghcr.io/acme/dhc/grafana\t13-alpine3.23,13.1.5-alpine3.23\n" +
		"valkey-compat\tinactive\tghcr.io/acme/dhc/valkey\t9-alpine3.23-compat\n" +
		"empty\tactive\tghcr.io/acme/dhc/empty\t\n"
	path := filepath.Join(dir, "definitions.tsv")
	if err := os.WriteFile(path, []byte(tsv), 0o644); err != nil {
		t.Fatal(err)
	}
	defs, err := LoadDefinitions(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(defs) != 3 || defs[0].Name != "grafana" || !defs[0].Active || defs[0].Repository != "ghcr.io/acme/dhc/grafana" || len(defs[0].Tags) != 2 || defs[0].Tags[1] != "13.1.5-alpine3.23" {
		t.Errorf("name, active flag, repository and tags per row, declared order: %+v", defs)
	}
	if defs[1].Active || defs[1].Tags[0] != "9-alpine3.23-compat" {
		t.Errorf("inactive reads as inactive: %+v", defs[1])
	}
	if len(defs[2].Tags) != 0 {
		t.Errorf("an empty tag list is empty, not one empty tag: %+v", defs[2])
	}
	if err := os.WriteFile(path, []byte("grafana\tmaybe\tghcr.io/acme/dhc/grafana\t13-alpine3.23\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadDefinitions(path); err == nil {
		t.Errorf("a flag other than active or inactive is an error, not a guess")
	}
	if err := os.WriteFile(path, []byte("grafana\tactive\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadDefinitions(path); err == nil {
		t.Errorf("a short row is an error")
	}
}

func TestLoadAdmission(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "verify-catalogue.json")
	doc := `{"control": "ghcr.io/acme/dhc/grafana@sha256:46", "resources": [
	  {"name": "admit-001", "ref": "ghcr.io/acme/dhc/grafana@sha256:aa", "tags": "13-alpine3.23", "result": "pass", "message": ""},
	  {"name": "admit-002", "ref": "ghcr.io/acme/dhc/valkey@sha256:bb", "tags": "9-alpine3.23", "result": "fail", "message": "no signature"},
	  {"name": "control-must-reject", "ref": "ghcr.io/acme/dhc/grafana@sha256:46", "tags": "(declared control)", "result": "fail", "message": ""}],
	  "failures": [], "warnings": []}`
	if err := os.WriteFile(path, []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	adm, err := LoadAdmission(path)
	if err != nil {
		t.Fatal(err)
	}
	if v, ok := adm["ghcr.io/acme/dhc/grafana@sha256:aa"]; !ok || !v {
		t.Errorf("a pass verdict reads as admitted: %+v", adm)
	}
	if v, ok := adm["ghcr.io/acme/dhc/valkey@sha256:bb"]; !ok || v {
		t.Errorf("a fail verdict reads as not admitted: %+v", adm)
	}
	if _, ok := adm["ghcr.io/acme/dhc/grafana@sha256:46"]; ok {
		t.Errorf("the control is the policy's proof, not a catalogue digest: %+v", adm)
	}
	if err := os.WriteFile(path, []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadAdmission(path); err == nil {
		t.Errorf("a proof that does not parse is an error")
	}
}

func TestLoadExpiries(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "accepted-risk.txt")
	report := "lint-accepted-risk: 13 entries\n" +
		"::warning file=triage/accepted-risk/grafana.yaml,line=12::risk treatment: CVE-2026-1 expires in 9 days (2026-09-18) \u2014 owner mm-weber\n" +
		"::error file=triage/accepted-risk/valkey.yaml,line=4::risk treatment (Req 6.11): CVE-2026-2 expired_at 2026-09-01 is in the past \u2014 Trivy already counts this finding again, so re-decide the risk or drop the entry\n" +
		"::error file=triage/accepted-risk/grafana.yaml,line=30::risk treatment (Req 6.7): decided_at is missing\n" +
		"all good otherwise\n"
	if err := os.WriteFile(path, []byte(report), 0o644); err != nil {
		t.Fatal(err)
	}
	ex, err := LoadExpiries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(ex) != 2 {
		t.Fatalf("only the lapsing and lapsed lines, keyed by the exception file's definition: %+v", ex)
	}
	if ex[0].Definition != "grafana" || ex[0].Lapsed || ex[0].Message != "CVE-2026-1 expires in 9 days (2026-09-18) \u2014 owner mm-weber" {
		t.Errorf("a warning is a lapsing exception with the lint's own words: %+v", ex[0])
	}
	if ex[1].Definition != "valkey" || !ex[1].Lapsed || ex[1].Message == "" {
		t.Errorf("an expired_at in the past is a lapsed exception: %+v", ex[1])
	}
	if _, err := LoadExpiries(filepath.Join(dir, "absent.txt")); err == nil {
		t.Errorf("an absent report is an error, not an empty list")
	}
}

func TestCountSuperseded(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "enumeration.tsv")
	tsv := "r\t1.0\tsha256:a\tlinux/amd64\tsha256:a1\tsuperseded\n" +
		"r\t1.0\tsha256:a\tlinux/arm64\tsha256:a2\tsuperseded\n" +
		"r\t1.1\tsha256:b\tlinux/amd64\tsha256:b1\tsupported\n" +
		"r\t0.9\tsha256:c\t-\tsha256:c\tsuperseded\n"
	if err := os.WriteFile(path, []byte(tsv), 0o644); err != nil {
		t.Fatal(err)
	}
	n, err := CountSuperseded(path)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("superseded tags counted once whatever their platforms: got %d", n)
	}
	if _, err := CountSuperseded(filepath.Join(dir, "absent.tsv")); err == nil {
		t.Errorf("an absent enumeration is an error")
	}
}
