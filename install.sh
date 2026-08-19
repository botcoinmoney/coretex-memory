#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Consumer installer for the CoreTex portable memory-IR adapter.
#
#   ./install.sh [VENV_DIR]        # default: ./coretex-venv
#   CORETEX_PYTHON=/usr/bin/python3.10 ./install.sh
#
# Fetches and verifies the three product wheels (local wheels/ if the digests already
# match, otherwise the live kit by content hash, then GitHub release adapter-0.1.11),
# then installs them into VENV_DIR. Safe to re-run: an existing venv is reused.
# The only other download is wasmtime from PyPI. Air-gapped boxes: pre-run
# `pip download 'wasmtime>=46.0.1,<47' -d wheels/` on a connected machine.
#
# Interpreter: stable CPython 3.10+ (releaselevel=final). Prerelease interpreters
# (for example 3.11.0rc1) are refused. Override with CORETEX_PYTHON.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS="$HERE/wheels"
VENV="${1:-$PWD/coretex-venv}"
KIT="https://coordinator.agentmoney.net/coretex/v5/kit/file"

# wheel filename : sha256 (also the kit's content address) — the product's identity.
W1="coretex_memory-0.1.5-py3-none-any.whl";        H1="b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d"
W2="coretex_memory_agent-0.1.11-py3-none-any.whl"; H2="2e05f1741aa2a297bbdfb786980937a9ad754d577d1b177d546effe290153907"
W3="coretex_hermes_provider-0.1.4-py3-none-any.whl"; H3="4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438"

say() { printf '\n== %s ==\n' "$1"; }
die() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }

python_is_final_310() {
  "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) and sys.version_info.releaselevel == "final" else 1)' \
    >/dev/null 2>&1
}

pick_python() {
  local py
  if [ -n "${CORETEX_PYTHON:-}" ]; then
    command -v "$CORETEX_PYTHON" >/dev/null || die "CORETEX_PYTHON=$CORETEX_PYTHON is not executable"
    python_is_final_310 "$CORETEX_PYTHON" \
      || die "CORETEX_PYTHON=$CORETEX_PYTHON is not a stable CPython 3.10+ (got $("$CORETEX_PYTHON" -V 2>&1)). Prerelease builds (rc/a/b) are refused."
    printf '%s\n' "$CORETEX_PYTHON"
    return 0
  fi
  for py in python3.12 python3.11 python3.10 python3; do
    command -v "$py" >/dev/null 2>&1 || continue
    if python_is_final_310 "$py"; then
      printf '%s\n' "$py"
      return 0
    fi
  done
  die "no stable CPython 3.10+ on PATH (releaselevel=final). Install python3.10+ from your distro, or set CORETEX_PYTHON to a final 3.10–3.13 binary."
}

command -v sha256sum >/dev/null || die "sha256sum not found"
command -v curl >/dev/null || die "curl not found"
PY="$(pick_python)"
say "0. interpreter $PY ($("$PY" -V 2>&1))"

say "1. wheels in $WHEELS"
mkdir -p "$WHEELS"
for pair in "$W1 $H1" "$W2 $H2" "$W3 $H3"; do
  set -- $pair
  name="$1"; want="$2"
  if [ -f "$WHEELS/$name" ] && [ "$(sha256sum "$WHEELS/$name" | cut -d' ' -f1)" = "$want" ]; then
    echo "have  $name"
  else
    echo "fetch $name"
    GH="https://github.com/botcoinmoney/coretex-memory/releases/download/adapter-0.1.11/$name"
    if curl -fsSL --retry 3 -o "$WHEELS/$name.part" "$KIT/$want" 2>/dev/null; then
      echo "  (kit $want)"
    elif curl -fsSL --retry 3 -o "$WHEELS/$name.part" "$GH"; then
      echo "  (kit miss; fetched $name from GitHub release adapter-0.1.11)"
    else
      die "download failed for $name (tried $KIT/$want and $GH)"
    fi
    mv "$WHEELS/$name.part" "$WHEELS/$name"
  fi
done

say "2. checksums (fail-closed)"
SUMS="$(mktemp)"
trap 'rm -f "$SUMS"' EXIT
printf '%s  %s\n%s  %s\n%s  %s\n' "$H1" "$W1" "$H2" "$W2" "$H3" "$W3" >"$SUMS"
(cd "$WHEELS" && sha256sum -c "$SUMS") \
  || die "WHEEL DIGEST MISMATCH — refusing to install. Delete the bad file(s) in $WHEELS and re-run; do not override."

say "3. virtualenv at $VENV"
if [ -x "$VENV/bin/python" ]; then
  echo "reusing existing venv"
elif [ -e "$VENV" ] && [ -z "$(ls -A "$VENV" 2>/dev/null || true)" ]; then
  "$PY" -m venv "$VENV"
elif [ -e "$VENV" ]; then
  die "$VENV exists and is not a virtualenv. Pass another path, or remove it."
else
  "$PY" -m venv "$VENV"
fi
# shellcheck disable=SC1091
. "$VENV/bin/activate"
command -v pip >/dev/null || die "this venv has no pip. Rebuild with '$PY -m venv $VENV' or run '$PY -m ensurepip'."

say "4. install the three wheels in dependency order"
# wasmtime>=46.0.1,<47 is resolved from PyPI here (the one external dependency).
pip install --disable-pip-version-check "$WHEELS/$W1"
pip install --disable-pip-version-check "$WHEELS/$W2"
pip install --disable-pip-version-check "$WHEELS/$W3"

say "4b. packaged compatibility lock"
# curl-only installs have no tarball compatibility/ directory. Hermes config needs a file path;
# the agent wheel already ships the lock. Copy it next to install.sh when the directory is writable.
LOCK="$("$VENV/bin/python" -c 'from coretex_memory_agent.config import packaged_lock_path; print(packaged_lock_path())')"
echo "packaged_lock_path() = $LOCK"
if mkdir -p "$HERE/compatibility" 2>/dev/null && cp "$LOCK" "$HERE/compatibility/compatibility-lock-0.1.5.json" 2>/dev/null; then
  echo "wrote $HERE/compatibility/compatibility-lock-0.1.5.json"
else
  echo "could not copy next to install.sh; Hermes config.compatibility_lock can use packaged_lock_path() above"
fi

say "4c. edge User-Agent shim (defense in depth)"
# Live GET /coretex/v5/* allows default Python-urllib. GET /v1/* still 403s that UA. The shim
# identifies the adapter; it is inert on the v5 path and harmless if the /v1 carve-out stays.
# Envelope-only: patches nothing in any wheel. Opt out: CORETEX_ADAPTER_UA_SHIM=0.
#
# Delivered as a module + a site .pth, NOT sitecustomize.py: Debian/Ubuntu ship
# /usr/lib/pythonX.Y/sitecustomize.py ahead of site-packages.
PURELIB="$("$VENV/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" \
  || die "could not resolve the venv site-packages directory"
[ -d "$PURELIB" ] || die "resolved site-packages '$PURELIB' is not a directory"
cat >"$PURELIB/coretex_edge_ua_shim.py" <<'PYSHIM'
# coretex_edge_ua_shim.py — envelope shim, not part of any wheel.
# Live /coretex/v5 allows Python-urllib; /v1 still 403s it. Opt out: CORETEX_ADAPTER_UA_SHIM=0
import os
if os.environ.get("CORETEX_ADAPTER_UA_SHIM", "1") != "0":
    import urllib.request as _u
    _o = _u.build_opener()
    _o.addheaders = [("User-Agent",
        "coretex-memory-adapter/0.1.11 (+https://github.com/botcoinmoney/coretex-memory)")]
    _u.install_opener(_o)
PYSHIM
printf 'import coretex_edge_ua_shim\n' >"$PURELIB/zzz-coretex-edge-ua-shim.pth"
echo "wrote $PURELIB/coretex_edge_ua_shim.py + zzz-coretex-edge-ua-shim.pth"
if [ "${CORETEX_ADAPTER_UA_SHIM:-1}" = "0" ]; then
  echo "CORETEX_ADAPTER_UA_SHIM=0 — shim installed but disabled by request; not verifying"
else
  "$VENV/bin/python" -c 'import urllib.request as u; ua = dict(getattr(u._opener, "addheaders", []) or {}).get("User-Agent", ""); raise SystemExit(0 if ua.startswith("coretex-memory-adapter/") else 1)' \
    || die "edge User-Agent shim did not take effect in $PURELIB"
  echo "verified: urllib default opener now sends a coretex-memory-adapter User-Agent"
fi

say "5. write default config (idempotent)"
coretex init --coordinator https://coordinator.agentmoney.net \
             --rpc https://mainnet.base.org --profile event.schema.v1

say "INSTALL OK"
cat <<EOF
Activate this environment with:

    source "$VENV/bin/activate"

Then sync the live CoreTex state:

    coretex sync

coordinator is the base URL (https://coordinator.agentmoney.net) — do not append /coretex/v5.
EOF
