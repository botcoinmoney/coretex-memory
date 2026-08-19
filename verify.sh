#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Reproducible install + offline self-check for the CoreTex portable memory-IR adapter.
#
#   ./verify.sh [VENV_DIR]
#
# Creates a fresh virtualenv, installs the three wheels in dependency order, imports every
# package, and exercises the offline surface of both CLIs. It makes NO call to the coordinator
# and NO call to a chain RPC. The only network access is pip resolving the runtime's single
# external dependency (wasmtime) from PyPI; set CORETEX_VERIFY_OFFLINE=1 and drop a wasmtime
# wheel into wheels/ to run with --no-index instead.
#
# Interpreter: same picker as install.sh. A stable CPython 3.10+ (releaselevel=final).
# CORETEX_PYTHON=rc1 exits 1 and names MemoryStore._create_schema; it does not build a venv.
set -euo pipefail

DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEELS="$DIST_DIR/wheels"
VENV="${1:-$(mktemp -d)/venv}"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# Hermetic: never read or write the invoking user's real coretex config/state.
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
export HERMES_HOME="$SANDBOX/hermes"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$HERMES_HOME"

say() { printf '\n== %s ==\n' "$1"; }
die() { printf 'verify.sh: %s\n' "$1" >&2; exit 1; }

python_is_final_310() {
  "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) and sys.version_info.releaselevel == "final" else 1)' \
    >/dev/null 2>&1
}

pick_python() {
  local py
  if [ -n "${CORETEX_PYTHON:-}" ]; then
    command -v "$CORETEX_PYTHON" >/dev/null || die "CORETEX_PYTHON=$CORETEX_PYTHON is not executable"
    python_is_final_310 "$CORETEX_PYTHON" \
      || die "CORETEX_PYTHON=$CORETEX_PYTHON is not a stable CPython 3.10+ (got $("$CORETEX_PYTHON" -V 2>&1)). Hermes 0.20.4 on 3.11.0rc1 segfaults in MemoryStore._create_schema; use /usr/bin/python3.10 or a final 3.11/3.12."
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
  die "no stable CPython 3.10+ on PATH (releaselevel=final). PATH's python3 is often Hermes' 3.11.0rc1, which segfaults in coretex_memory.store with no JSON refusal. Install python3.10 (distro) or set CORETEX_PYTHON to a final 3.10–3.13 binary. Do not host this runtime inside a 3.11.0rc1 Hermes venv."
}

say "1. wheel checksums"
(cd "$WHEELS" && sha256sum -c SHA256SUMS)

say "2. python"
PY="$(pick_python)"
echo "$PY ($("$PY" -V 2>&1))"

say "3. fresh virtualenv at $VENV"
"$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

say "4. install the three wheels in dependency order"
PIP_ARGS=()
if [ "${CORETEX_VERIFY_OFFLINE:-0}" = "1" ]; then
  PIP_ARGS=(--no-index --find-links "$WHEELS")
fi
pip install --disable-pip-version-check "${PIP_ARGS[@]}" \
  "$WHEELS/coretex_memory-0.1.5-py3-none-any.whl"
pip install --disable-pip-version-check "${PIP_ARGS[@]}" \
  "$WHEELS/coretex_memory_agent-0.1.12-py3-none-any.whl"
pip install --disable-pip-version-check "${PIP_ARGS[@]}" \
  "$WHEELS/coretex_hermes_provider-0.1.4-py3-none-any.whl"

say "5. imports + identities"
python3 - <<'PY'
import coretex_memory, coretex_memory_agent, coretex_hermes_provider
from coretex_memory_agent import AgentMemory, CoreTexBackend, CanonicalStateManager
from coretex_memory_agent.config import anchors, chain_id, packaged_lock_path
from coretex_memory_agent.state import runtime_compatibility
print("coretex_memory        ", coretex_memory.__version__)
print("coretex_memory_agent  ", coretex_memory_agent.__version__, coretex_memory_agent.AGENT_BUILD)
print("coretex_hermes_provider", coretex_hermes_provider.__version__,
      coretex_hermes_provider.PROVIDER_BUILD)
print("hermes_available      ", coretex_hermes_provider.HERMES_AVAILABLE)
print("runtime_compatibility ", runtime_compatibility())
a = anchors()
print("chain_id              ", chain_id())
for name in ("coreTexRegistry", "coreTexVerifier", "mining"):
    print(f"anchor {name:<16}", a["contracts"][name])
print("packaged lock         ", packaged_lock_path())
PY

say "6. packaged compatibility lock == the copy shipped in compatibility/"
python3 - "$DIST_DIR/compatibility/compatibility-lock-0.1.5.json" <<'PY'
import hashlib, sys
from coretex_memory_agent.config import packaged_compatibility_lock, packaged_lock_path
shipped, packaged = sys.argv[1], str(packaged_lock_path())
a = hashlib.sha256(open(shipped, "rb").read()).hexdigest()
b = hashlib.sha256(open(packaged, "rb").read()).hexdigest()
assert a == b, f"shipped lock {a} != packaged lock {b}"
lock = packaged_compatibility_lock()          # validates it against the INSTALLED runtime
print("lock sha256           ", a)
print("lock compatibility    ", lock["compatibility"])
PY

say "7. agent CLI (offline surface only)"
coretex --help | head -20
coretex config
coretex init --show

say "8. hermes provider console script + discovery shim (no Hermes needed)"
coretex-hermes-provider --help || true
coretex-hermes-provider install --hermes-home "$HERMES_HOME"
ls -1 "$HERMES_HOME/plugins/coretex"

say "9. runtime CLI"
coretex-memory --version

say "10. local store round-trip (no network, throwaway store)"
python3 - "$SANDBOX/selfcheck.db" <<'PY'
import sys
from coretex_memory import Memory
m = Memory.open(sys.argv[1])
try:
    m.ingest("verify.sh", "The verify script ran a local store round-trip.")
    pack = m.context("what did the verify script do?", 128)
    print("served items          ", len(pack.items))
    status = m.status()
    print("store integrity       ", status["integrity"], "in_sync:", status["in_sync"])
finally:
    m.close()
PY

say "VERIFY OK"
echo "venv: $VENV"
