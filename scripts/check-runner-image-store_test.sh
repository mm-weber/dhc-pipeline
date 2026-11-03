#!/usr/bin/env bash
# Tests for scripts/check-runner-image-store.sh, the e2e workflow's guard run
# before `kind load docker-image`. Contract: the guard learns Docker facts only
# through the docker command on PATH (the server version via `docker version`,
# the storage driver and its status via `docker info`), and names the runner
# image from the ImageOS and ImageVersion variables GitHub-hosted runners set,
# joined as <ImageOS>/<ImageVersion>. Under the classic graph driver
# (overlay2) it exits 0 and prints one ::notice:: line naming the runner
# image, the Docker server version and the storage driver. Under Docker's
# containerd image store (DriverStatus carries io.containerd.snapshotter) it
# exits 1 and prints one ::error:: line naming the runner image, the Docker
# server version, the phrase "containerd image store" and "kind issue 3795".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-runner-image-store.sh"
FAILURES=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; shift; [ $# -gt 0 ] && printf '%s\n' "$@" | sed 's/^/    /'; FAILURES=$((FAILURES+1)); }
expect() { # name, expected rc, actual rc, output, needles...
  local name="$1" want="$2" rc="$3" out="$4"; shift 4
  if [ "$rc" -ne "$want" ]; then fail "$name" "exit=$rc, wanted $want" "$out"; return; fi
  local n; for n in "$@"; do
    if ! grep -qF -- "$n" <<<"$out"; then fail "$name" "missing '$n'" "$out"; return; fi
  done
  pass "$name"
}

# The docker shim answers each format string the guard may ask for; anything
# else is a refusal, so the guard cannot learn facts by another route.
SB=$(mktemp -d); mkdir -p "$SB/bin"
cat >"$SB/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'{{range .DriverStatus}}'*) echo "Backing Filesystem=extfs;Supports d_type=true;" ;;
  *'{{.Server.Version}}'*)     echo "28.0.4" ;;
  *'{{.Driver}}'*)             echo "overlay2" ;;
  *) echo "docker shim: unexpected arguments: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$SB/bin/docker"
export ImageOS=ubuntu24 ImageVersion=20261101.360.1
run() { PATH="$SB/bin:$PATH" "$CHECK" 2>&1; }

# 1: the classic graph driver passes, the notice names image, version, driver
out=$(run); rc=$?
expect "graph driver: passes and names the image" 0 "$rc" "$out" "::notice::" "ubuntu24/20261101.360.1" "28.0.4" "overlay2"

# 2: the containerd image store fails by name. A second shim answers as a
# daemon running the containerd snapshotter does (`{{.Driver}}` is overlayfs,
# the DriverStatus names io.containerd.snapshotter); this test's runner image
# is set on its one command line, so test 1's exported values stay as they are.
mkdir -p "$SB/bin2"
cat >"$SB/bin2/docker" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'{{range .DriverStatus}}'*) echo "driver-type=io.containerd.snapshotter.v1;" ;;
  *'{{.Server.Version}}'*)     echo "29.4.2" ;;
  *'{{.Driver}}'*)             echo "overlayfs" ;;
  *) echo "docker shim: unexpected arguments: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$SB/bin2/docker"
out=$(ImageOS=ubuntu26 ImageVersion=20261026.180.1 PATH="$SB/bin2:$PATH" "$CHECK" 2>&1); rc=$?
expect "containerd image store: fails by name" 1 "$rc" "$out" "::error::" "ubuntu26/20261026.180.1" "29.4.2" "containerd image store" "kind issue 3795"

echo
if [ "$FAILURES" -gt 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all check-runner-image-store tests passed"
