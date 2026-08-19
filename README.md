# coretex-memory

Sync the live CoreTex memory state and use it in an agent. This is not a mining tool.

## Install

Needs a stable CPython 3.10+ (`python3 --version` should not say `rc`). Then:

```bash
curl -fsSLO https://github.com/botcoinmoney/coretex-memory/releases/download/adapter-0.1.12/install.sh
bash ./install.sh
source ./coretex-venv/bin/activate
coretex sync
```

`install.sh` is safe to re-run. It reuses `./coretex-venv` if that path is already a venv.

`coretex` is the base coordinator URL, with no `/coretex/v5` suffix:

```
https://coordinator.agentmoney.net
```

## Use

```python
from coretex_memory_agent import AgentMemory

memory = AgentMemory.open()
memory.sync_turn(messages=[{"role": "user", "content": "The deploy window moved to Tuesday 09:00."}])
print(memory.prefetch("when is the deploy window?", budget=256).render())
memory.flush_session()
memory.close()
```

Neutral eval comparisons use the same last-synced composition — no per-run manifest or root pin:

```python
from coretex_memory_agent.backend import CoreTexBackend

backend = CoreTexBackend.from_synced(workdir="./eval-runs")
backend.reset("longmemeval-v1-run")
backend.ingest(record_or_trajectory)
result = backend.context(question, token_budget=512)
backend.checkpoint()
backend.close()
```

`from_synced` before any `coretex sync` raises `PipelineNotSyncedError` naming the command that fixes it. Offline conformance can still pass a minted `manifest_path` + `manifest_root`; that path is a fixture, not live CoreTex.

`health()["release_id"]` and `health()["active_release"]` are the serving module. The bundled WASM retrieval policy is `health()["retrieval_policy"]` (its `release_id` may be null). `coretex init --show` reports `initialized` when a config file is already present; `wrote` is whether that invocation wrote.

## Pins

Wheels are content-addressed. The live kit at
`https://coordinator.agentmoney.net/coretex/v5/kit/file/<sha256>` is byte authority for the
runtime and Hermes wheels. Agent 0.1.12 is this GitHub release (the mining kit still serves
0.1.11; 0.1.12 adds `CoreTexBackend.from_synced`).

```
b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d  coretex_memory-0.1.5-py3-none-any.whl
1d9a69215a4d880baf74319c435ccb0c1767d7f4e6b69174a78a31ff977b224b  coretex_memory_agent-0.1.12-py3-none-any.whl
4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438  coretex_hermes_provider-0.1.4-py3-none-any.whl
```

Full configuration, sync model, and air-gapped install: [ADAPTER.md](ADAPTER.md).

Apache-2.0 ([LICENSE](LICENSE)).
