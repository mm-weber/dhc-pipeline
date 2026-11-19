package inputs

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
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

// The provenance coverage the rescan measured (Req 2.29, 2.30; task 18.4):
// what scripts/check-provenance.sh printed on stdout, one line per reference.
func TestLoadProvenance(t *testing.T) {
	const (
		grafana = "ghcr.io/acme/dhc/grafana@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		grafArm = "ghcr.io/acme/dhc/grafana@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
		valkey  = "ghcr.io/acme/dhc/valkey@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
		valkArm = "ghcr.io/acme/dhc/valkey@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
		reason  = "no attestation: gh attestation verify found none covered by the policy"
	)
	dir := t.TempDir()
	n := 0
	write := func(t *testing.T, content string) string {
		t.Helper()
		n++
		path := filepath.Join(dir, "provenance-"+strconv.Itoa(n)+".tsv")
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		return path
	}
	absent := filepath.Join(dir, "absent.tsv")
	mixed := "covered\t" + valkey + "\n" +
		"uncovered\t" + valkArm + "\t" + reason + "\n" +
		"covered\t" + grafana + "\n" +
		"uncovered\t" + grafArm + "\t" + reason + "\n"

	read := []struct {
		name, mode, content string
		covered, total      int
		uncovered           []string
		json                string
	}{
		{"report, covered and uncovered mixed", "report", mixed, 2, 4, []string{valkArm, grafArm},
			`{"mode":"report","covered":2,"total":4,"uncovered":["` + valkArm + `","` + grafArm + `"]}`},
		{"required, the same file", "required", mixed, 2, 4, []string{valkArm, grafArm},
			`{"mode":"required","covered":2,"total":4,"uncovered":["` + valkArm + `","` + grafArm + `"]}`},
		{"required, all covered", "required", "covered\t" + grafana + "\ncovered\t" + grafArm + "\n", 2, 2, []string{},
			`{"mode":"required","covered":2,"total":2,"uncovered":[]}`},
		{"report, the one reference uncovered", "report", "uncovered\t" + grafana + "\t" + reason + "\n", 0, 1, []string{grafana},
			`{"mode":"report","covered":0,"total":1,"uncovered":["` + grafana + `"]}`},
	}
	for _, tc := range read {
		t.Run(tc.name, func(t *testing.T) {
			got, err := LoadProvenance(tc.mode, write(t, tc.content))
			if err != nil {
				t.Fatalf("what the check printed is read: %v", err)
			}
			if got == nil {
				t.Fatalf("mode %s reads the file; got no result", tc.mode)
			}
			if got.Mode != tc.mode || got.Covered != tc.covered || got.Total != tc.total {
				t.Errorf("mode %s, %d of %d covered; got %+v", tc.mode, tc.covered, tc.total, *got)
			}
			if got.Uncovered == nil || !slices.Equal(got.Uncovered, tc.uncovered) {
				t.Errorf("the uncovered references in file order, empty and not nil when there are none: want %q, got %#v", tc.uncovered, got.Uncovered)
			}
			if data, err := json.Marshal(got); err != nil || string(data) != tc.json {
				t.Errorf("the published form:\nwant %s\n got %s (%v)", tc.json, data, err)
			}
		})
	}

	off := []struct{ name, file string }{
		{"off, a path that does not exist", absent},
		{"off, the empty path", ""},
		{"off, a file with lines is not read", write(t, mixed)},
		{"off, a file that would not parse is not read", write(t, "nonsense\n")},
	}
	for _, tc := range off {
		t.Run(tc.name, func(t *testing.T) {
			got, err := LoadProvenance("off", tc.file)
			if err != nil {
				t.Fatalf("with the mode off nothing is read, so nothing can fail: %v", err)
			}
			if got == nil {
				t.Fatalf("the mode off is a result of its own (Req 2.30), not an absent one")
			}
			if got.Mode != "off" || got.Covered != 0 || got.Total != 0 || got.Uncovered == nil || len(got.Uncovered) != 0 {
				t.Errorf("off: nothing verified, 0 of 0, an empty list that is not nil; got %#v", *got)
			}
			if data, err := json.Marshal(got); err != nil || string(data) != `{"mode":"off","covered":0,"total":0,"uncovered":[]}` {
				t.Errorf("the published form of off: %s (%v)", data, err)
			}
		})
	}

	for _, file := range []string{absent, "", write(t, mixed), write(t, "nonsense\n")} {
		if got, err := LoadProvenance("", file); got != nil || err != nil {
			t.Errorf("no mode given (file %q): nil and no error, nothing read; got %+v, %v", file, got, err)
		}
	}

	for _, word := range []string{"REPORT", "on", "Off", "require", "enforced"} {
		got, err := LoadProvenance(word, write(t, mixed))
		if err == nil {
			t.Errorf("mode %q is none of off, report, required: an error, not a guess; got %+v", word, got)
			continue
		}
		if got != nil {
			t.Errorf("mode %q: no result beside the error; got %+v", word, *got)
		}
		if !strings.Contains(err.Error(), strconv.Quote(word)) {
			t.Errorf("mode %q: the error holds the word, quoted: %v", word, err)
		}
	}

	good := "covered\t" + grafana + "\n"
	bad := []struct {
		name, mode, content string
		line                int // the bad line's number, 0 when the file as a whole is at fault
	}{
		{"an empty file", "report", "", 0},
		{"an empty file, required", "required", "", 0},
		{"a file of one line end", "report", "\n", 0},
		{"a first field that is neither word", "report", good + good + "maybe\t" + valkey + "\n" + good, 3},
		{"a first field in another case", "required", good + "Covered\t" + valkey + "\n", 2},
		{"a first field with a blank before it", "report", " covered\t" + valkey + "\n", 1},
		{"a covered line with a third field", "report", good + "covered\t" + valkey + "\t" + reason + "\n" + good, 2},
		{"an uncovered line without a third field", "report", good + good + "uncovered\t" + valkey + "\n", 3},
		{"an uncovered line without a third field, required", "required", "uncovered\t" + valkey + "\n" + good, 1},
		{"a covered line without a reference", "report", good + "covered\n" + good, 2},
		{"a covered line with an empty reference", "report", good + "covered\t\n", 2},
		{"an uncovered line with an empty reference", "report", good + good + good + "uncovered\t\t" + reason + "\n", 4},
		{"the fields separated by blanks", "report", good + "uncovered " + valkey + " " + reason + "\n", 2},
		{"a blank line in the middle", "report", good + "\n" + good, 2},
		{"a blank line in the middle, required", "required", good + good + "\n" + "uncovered\t" + valkey + "\t" + reason + "\n", 3},
	}
	for _, tc := range bad {
		t.Run(tc.name, func(t *testing.T) {
			path := write(t, tc.content)
			got, err := LoadProvenance(tc.mode, path)
			if err == nil {
				t.Fatalf("an error, not a coverage read past it; got %+v", got)
			}
			if got != nil {
				t.Errorf("never a partial result beside an error; got %+v", *got)
			}
			if !strings.Contains(err.Error(), path) {
				t.Errorf("the error names the file %s: %v", path, err)
			}
			rest := strings.ReplaceAll(err.Error(), path, "")
			if tc.line != 0 && !regexp.MustCompile(`\b`+strconv.Itoa(tc.line)+`\b`).MatchString(rest) {
				t.Errorf("the error names line %d: %v", tc.line, err)
			}
		})
	}
	for _, mode := range []string{"report", "required"} {
		got, err := LoadProvenance(mode, "")
		if err == nil || got != nil {
			t.Errorf("mode %s without a file: an error and no result; got %+v, %v", mode, got, err)
		}
		got, err = LoadProvenance(mode, absent)
		if err == nil || got != nil {
			t.Errorf("mode %s with a file that does not exist: an error and no result; got %+v, %v", mode, got, err)
		} else if !strings.Contains(err.Error(), absent) {
			t.Errorf("mode %s: the error names the file %s: %v", mode, absent, err)
		}
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
