# coretex-memory

Standalone memory-IR adapter for agents and other consumers: it syncs the canonical CoreTex memory
state from the live coordinator and Base mainnet and renders it into an agent's context. It is
entirely separate from mining — you do not need it to mine, and it does not mine.

## Quickstart

```bash
curl -fsSLO https://github.com/botcoinmoney/coretex-memory/releases/download/adapter-0.1.10/install.sh
bash ./install.sh
```

Then, in the venv the installer prints:

```bash
coretex init --coordinator https://coordinator.agentmoney.net \
             --rpc https://mainnet.base.org --profile event.schema.v1
coretex sync
```

The live frontier is the current CoreTex package (`manifest_schema_version=4`,
`wrapper_format=3` on all three routed slots). `coretex sync` activates that state; see
ADAPTER.md §"Live frontier note".

## Audit pin

The product identity is the sha256 of the three wheels. The live kit at
`https://coordinator.agentmoney.net/coretex/v5/kit/file/<sha256>` is the byte authority
(runtime 0.1.5, agent **0.1.10**, hermes 0.1.4). `install.sh` falls back to this GitHub
release only on a kit miss:

```
b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d  coretex_memory-0.1.5-py3-none-any.whl
1f8e47d6b41ae60b900f172aae4694b9e0aaa3f9ff07a1776f45d3fe67daff17  coretex_memory_agent-0.1.10-py3-none-any.whl
4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438  coretex_hermes_provider-0.1.4-py3-none-any.whl
```

Full manual (configuration, sync model, Hermes wiring, offline/air-gapped install, verification):
[ADAPTER.md](ADAPTER.md).

Licensed under Apache-2.0 ([LICENSE](LICENSE)).
