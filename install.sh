#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Consumer installer for the CoreTex portable memory-IR adapter.
#
#   ./install.sh [VENV_DIR]        # default: ./coretex-venv
#
# Creates a fresh virtualenv, makes sure the three product wheels are present as RAW BYTES
# (using the local wheels/ copy when it already matches, otherwise fetching them from the live
# kit by content hash), verifies all three digests fail-closed, and installs them in dependency
# order. The only other download is the runtime's single external dependency, wasmtime, from
# PyPI. Air-gapped boxes: pre-run `pip download wasmtime==46.0.1 -d wheels/` on a connected
# machine, then re-run this script.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS="$HERE/wheels"
VENV="${1:-$PWD/coretex-venv}"
KIT="https://coordinator.agentmoney.net/coretex/v5/kit/file"

# wheel filename : sha256 (also the kit's content address) — the product's identity.
W1="coretex_memory-0.1.5-py3-none-any.whl";        H1="b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d"
W2="coretex_memory_agent-0.1.9-py3-none-any.whl";  H2="4122a98216f1a559ac69818afd7828d73854f9365aa1f0d7f3bbfa50338729a6"
W3="coretex_hermes_provider-0.1.4-py3-none-any.whl"; H3="4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438"

say() { printf '\n== %s ==\n' "$1"; }
die() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 not found"
command -v sha256sum >/dev/null || die "sha256sum not found"
command -v curl >/dev/null || die "curl not found"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
  || die "python 3.10+ required, found $(python3 --version 2>&1)"

say "1. wheels in $WHEELS"
mkdir -p "$WHEELS"
for pair in "$W1 $H1" "$W2 $H2" "$W3 $H3"; do
  set -- $pair
  name="$1"; want="$2"
  if [ -f "$WHEELS/$name" ] && [ "$(sha256sum "$WHEELS/$name" | cut -d' ' -f1)" = "$want" ]; then
    echo "have  $name"
  else
    echo "fetch $name"
    curl -fsSL --retry 3 -o "$WHEELS/$name.part" "$KIT/$want" \
      || die "download failed for $name ($KIT/$want)"
    mv "$WHEELS/$name.part" "$WHEELS/$name"
  fi
done

say "2. checksums (fail-closed)"
SUMS="$(mktemp)"
trap 'rm -f "$SUMS"' EXIT
printf '%s  %s\n%s  %s\n%s  %s\n' "$H1" "$W1" "$H2" "$W2" "$H3" "$W3" >"$SUMS"
(cd "$WHEELS" && sha256sum -c "$SUMS") \
  || die "WHEEL DIGEST MISMATCH — refusing to install. Delete the bad file(s) in $WHEELS and re-run; do not override."

say "3. fresh virtualenv at $VENV"
[ -e "$VENV" ] && die "$VENV already exists; remove it or pass another path"
python3 -m venv "$VENV"
# shellcheck disable=SC1091
. "$VENV/bin/activate"

say "4. install the three wheels in dependency order"
# wasmtime>=46.0.1,<47 is resolved from PyPI here (the one external dependency).
pip install --disable-pip-version-check "$WHEELS/$W1"
pip install --disable-pip-version-check "$WHEELS/$W2"
pip install --disable-pip-version-check "$WHEELS/$W3"

say "4b. edge User-Agent shim"
# The live coordinator sits behind an edge that rejects Python-urllib/* User-Agents (Cloudflare
# rule 1010). coretex-memory-agent 0.1.9 fetches artifacts with urllib's default UA, so `coretex
# sync` would 403 refuse-closed without this. The shim is envelope-only: it patches nothing in any
# wheel, is scoped to this virtualenv, and is a no-op once the edge rule is relaxed.
#
# It is delivered as a module + a site .pth that imports it, NOT as sitecustomize.py: Debian and
# Ubuntu ship their own /usr/lib/pythonX.Y/sitecustomize.py, and the stdlib directory precedes
# site-packages on sys.path, so a sitecustomize.py written here would be silently shadowed and
# never run. A .pth in site-packages is executed by `site` on every interpreter start for this
# venv, including the sandboxed canary worker subprocess.
PURELIB="$("$VENV/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" \
  || die "could not resolve the venv site-packages directory"
[ -d "$PURELIB" ] || die "resolved site-packages '$PURELIB' is not a directory"
cat >"$PURELIB/coretex_edge_ua_shim.py" <<'PYSHIM'
# coretex_edge_ua_shim.py — installed by the coretex-memory adapter's install.sh (envelope shim,
# not part of any wheel). The live coordinator's edge blocks Python-urllib/* User-Agents
# (Cloudflare rule 1010); coretex-memory-agent 0.1.9 fetches artifacts via urllib with the
# default UA, so `coretex sync` would 403 without this. Installs a default opener whose UA
# identifies the adapter. Scoped to this virtualenv; harmless if the edge rule is relaxed.
# Loaded by zzz-coretex-edge-ua-shim.pth in the same directory.
# Opt out: export CORETEX_ADAPTER_UA_SHIM=0
import os
if os.environ.get("CORETEX_ADAPTER_UA_SHIM", "1") != "0":
    import urllib.request as _u
    _o = _u.build_opener()
    _o.addheaders = [("User-Agent",
        "coretex-memory-adapter/0.1.9 (+https://github.com/botcoinmoney/coretex-memory)")]
    _u.install_opener(_o)
PYSHIM
printf 'import coretex_edge_ua_shim\n' >"$PURELIB/zzz-coretex-edge-ua-shim.pth"
echo "wrote $PURELIB/coretex_edge_ua_shim.py + zzz-coretex-edge-ua-shim.pth"
if [ "${CORETEX_ADAPTER_UA_SHIM:-1}" = "0" ]; then
  echo "CORETEX_ADAPTER_UA_SHIM=0 — shim installed but disabled by request; not verifying"
else
  # Fail closed: a shim that did not load (e.g. a site that ignores .pth files) would hand the
  # consumer a venv whose `coretex sync` 403s on its first artifact fetch.
  "$VENV/bin/python" -c 'import urllib.request as u; ua = dict(getattr(u._opener, "addheaders", []) or {}).get("User-Agent", ""); raise SystemExit(0 if ua.startswith("coretex-memory-adapter/") else 1)' \
    || die "edge User-Agent shim did not take effect in $PURELIB — refusing to hand over a venv whose \`coretex sync\` would 403 on its first artifact fetch"
  echo "verified: urllib default opener now sends a coretex-memory-adapter User-Agent"
fi

say "5. resolved configuration"
coretex init --show

say "INSTALL OK"
cat <<EOF
Activate this environment with:

    source "$VENV/bin/activate"

Then configure it against the live deployment (see README §2):

    coretex init --coordinator https://coordinator.agentmoney.net \\
                 --rpc https://mainnet.base.org --profile event.schema.v1
    coretex sync
EOF
