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
