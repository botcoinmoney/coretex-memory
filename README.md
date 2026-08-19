# coretex-memory

Standalone memory-IR adapter for agents and other consumers: it syncs the canonical CoreTex memory
state from the live coordinator and Base mainnet and renders it into an agent's context. It is
entirely separate from mining — you do not need it to mine, and it does not mine.

## Quickstart

```bash
curl -fsSLO https://github.com/botcoinmoney/coretex-memory/releases/download/adapter-0.1.9/install.sh
bash ./install.sh
```

Then, in the venv the installer prints:

```bash
coretex init --coordinator https://coordinator.agentmoney.net \
             --rpc https://mainnet.base.org --profile event.schema.v1
coretex sync
```

Heads-up: live sync is currently gated on an operator-side release re-cut — see ADAPTER.md
"Live frontier note".

## Audit pin

The product identity is the sha256 of the three wheels (also their content address in the live
kit at `https://coordinator.agentmoney.net/coretex/v5/kit/file/<sha256>`):

```
b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d  coretex_memory-0.1.5-py3-none-any.whl
4122a98216f1a559ac69818afd7828d73854f9365aa1f0d7f3bbfa50338729a6  coretex_memory_agent-0.1.9-py3-none-any.whl
4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438  coretex_hermes_provider-0.1.4-py3-none-any.whl
```

Full manual (configuration, sync model, Hermes wiring, offline/air-gapped install, verification):
[ADAPTER.md](ADAPTER.md).

Licensed under Apache-2.0 ([LICENSE](LICENSE)).
