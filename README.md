# coretex-memory

Sync the live CoreTex memory state and use it in an agent. This is not a mining tool.

## Install

Needs a stable CPython 3.10+ (`python3 --version` should not say `rc`). Then:

```bash
curl -fsSLO https://github.com/botcoinmoney/coretex-memory/releases/download/adapter-0.1.10/install.sh
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

The live module is `health()["serving_champion"]`. Ignore `health()["active_release"]` — that is the bundled WASM runtime policy (`release_id` is null by design).

## Pins

Wheels are content-addressed. The live kit at
`https://coordinator.agentmoney.net/coretex/v5/kit/file/<sha256>` is byte authority;
GitHub `adapter-0.1.10` is the fallback.

```
b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d  coretex_memory-0.1.5-py3-none-any.whl
1f8e47d6b41ae60b900f172aae4694b9e0aaa3f9ff07a1776f45d3fe67daff17  coretex_memory_agent-0.1.10-py3-none-any.whl
4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438  coretex_hermes_provider-0.1.4-py3-none-any.whl
```

Full configuration, sync model, and air-gapped install: [ADAPTER.md](ADAPTER.md).

Apache-2.0 ([LICENSE](LICENSE)).
