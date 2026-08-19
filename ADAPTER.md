This is the consumer manual from coretex-portable-adapter-dist.tar.gz (identical content).

# CoreTex portable memory-IR adapter — standalone distribution

Everything needed to run the CoreTex agent memory adapter on a **fresh Linux box** against the
**live** CoreTex v5 coordinator and Base mainnet, and to wire it into a Hermes agent harness.

This distribution carries only wheels, checksums, the one compatibility lock a Hermes install
consumes, this README, a verify script and the Apache-2.0 license. No source tree, no tests, no
internal documents.

| file | what it is |
|---|---|
| `wheels/coretex_memory-0.1.5-py3-none-any.whl` | the trusted local runtime (memory store, hook worker, renderer) |
| `wheels/coretex_memory_agent-0.1.9-py3-none-any.whl` | the portable adapter: `AgentMemory`, chain/coordinator sync, activation, adapters, sidecar, `coretex` CLI |
| `wheels/coretex_hermes_provider-0.1.4-py3-none-any.whl` | the Hermes `MemoryProvider` and its discovery-shim installer |
| `wheels/SHA256SUMS` | `sha256sum -c`-able digests of the three wheels |
| `compatibility/compatibility-lock-0.1.5.json` | the runtime/ABI compatibility lock **as a file path**, which the Hermes provider config requires (see §5) |
| `install.sh` | one-command consumer install: fetch/verify the three wheels, venv, install in order |
| `verify.sh` | reproducible from-scratch install + offline self-check |
| `LICENSE` | Apache-2.0 (identical text ships inside all three wheels) |

The wheels are byte copies from the frozen runtime packet
`9d91ae3afd8f92ddcca6c6be1c34bbdf66b63748d113d835272b3e2e8c4c051f`
(preservation tag `coretex-runtime-cef-20260731-r12`), and their digests were verified against
that packet's own manifest before copying:

```
b06c9b2c70297b7003ba1a21e7cde3721ed605c3fc3b7bcb04512a96dfaea32d  coretex_memory-0.1.5-py3-none-any.whl
4122a98216f1a559ac69818afd7828d73854f9365aa1f0d7f3bbfa50338729a6  coretex_memory_agent-0.1.9-py3-none-any.whl
4a3409cb72123bdfe1b7fe5c5481d1a0e35430be85c235e74d58183e6e854438  coretex_hermes_provider-0.1.4-py3-none-any.whl
```

---

## 1. Install (fresh box, Python 3.10+ and pip only)

`./install.sh [VENV_DIR]` does everything in this section for you — it uses the local `wheels/`
copy when its digests already match, otherwise fetches the same wheel bytes from the live kit by
content hash, verifies all three fail-closed, installs them in dependency order and prints
`coretex init --show`. The manual equivalent:

```bash
python3 -m venv ~/coretex-venv
source ~/coretex-venv/bin/activate

cd /path/to/coretex-portable-adapter-dist
(cd wheels && sha256sum -c SHA256SUMS)

pip install wheels/coretex_memory-0.1.5-py3-none-any.whl
pip install wheels/coretex_memory_agent-0.1.9-py3-none-any.whl
pip install wheels/coretex_hermes_provider-0.1.4-py3-none-any.whl
```

Dependency order matters only because each wheel pins the one below it
(`coretex-memory-agent` requires `coretex-memory>=0.1.5,<0.2`; `coretex-hermes-provider` requires
`coretex-memory-agent>=0.1.9,<0.2`).

**One external dependency.** `coretex-memory` requires `wasmtime>=46.0.1,<47`, which pip pulls
from PyPI (9.8 MB). That is the only download the install needs. For an air-gapped box, fetch it
first on a connected machine:

```bash
pip download 'wasmtime>=46.0.1,<47' -d wheels/     # on a networked box
pip install --no-index --find-links wheels coretex-memory coretex-memory-agent coretex-hermes-provider
```

Three console scripts are installed: `coretex` (the adapter), `coretex-memory` (the runtime), and
`coretex-hermes-provider` (the Hermes shim installer).

## 2. Configure — the live coordinator and Base mainnet

```bash
coretex init \
  --coordinator https://coordinator.agentmoney.net \
  --rpc         https://mainnet.base.org \
  --profile     event.schema.v1

coretex init --show      # prints every resolved value and where it came from; writes nothing
```

`coretex init` writes `~/.config/coretex/config.json` (or `$XDG_CONFIG_HOME/coretex/config.json`)
and creates the state dir and the store's parent dir. It is idempotent — running it twice is
running it once; add `--force` to merge new flags over an existing file.

> **`coordinator` is the BASE URL, without the route prefix.** The adapter appends
> `/coretex/v5/frontier/{root}`, `/coretex/v5/release/{root}`, `/coretex/v5/eval/{root}` and
> `/coretex/v5/object/{root}` itself. Setting `coordinator` to
> `https://coordinator.agentmoney.net/coretex/v5` produces doubled paths and 404s.

### Config file keys (`~/.config/coretex/config.json`)

Written and read by `coretex_memory_agent.config`. An unknown key is a hard error, never a silent
ignore. Precedence everywhere: explicit CLI flag > config file > built-in default.

| key | flag | built-in default | meaning |
|---|---|---|---|
| `format` | — | `coretex-agent-config/v1` | the only accepted format string |
| `rpc` | `--rpc` | `https://mainnet.base.org` | keyless Base mainnet JSON-RPC endpoint |
| `coordinator` | `--coordinator` | `https://coordinator.agentmoney.net` | base URL serving the immutable `/coretex/v5` routes |
| `state_dir` | `--state-dir` | `~/.local/share/coretex/state` | verified canonical state (the pipeline) |
| `store` | `--store` (on `init`) | `~/.local/share/coretex/memory.db` | **your** local sqlite memory; sync never touches it |
| `profile` | `--profile` (on `init`) | `event.schema.v1` | which composition slot `AgentMemory.open()` serves |
| `snapshot` | `--snapshot` | — | published resolver snapshot; presence routes `coretex sync` into the DEEP flow |
| `artifact_dir` | `--artifact-dir` | — | local artifact store for deep reconstruction only |
| `compatibility_lock` | (internal flag) | packaged in the wheel | override; not needed by a consumer |
| `runtime_record` | (internal flag) | — | deep-flow validator input |
| `strict` | — | — | boolean, reserved |

Example file for this deployment:

```json
{
  "format": "coretex-agent-config/v1",
  "coordinator": "https://coordinator.agentmoney.net",
  "rpc": "https://mainnet.base.org",
  "profile": "event.schema.v1",
  "state_dir": "/home/OPERATOR/.local/share/coretex/state",
  "store": "/home/OPERATOR/.local/share/coretex/memory.db"
}
```

### What is NOT configurable (and why)

The **trust anchors** ship inside the agent wheel as `coretex_memory_agent/anchors.json`. There is
no env var, no CLI flag and no config key that can redirect them — a config file that could point
the registry somewhere else would make every downstream verification vacuous. `coretex config`
prints them; they are exactly the Base mainnet facts for this deployment:

| anchor | value |
|---|---|
| chain id | `8453` (base-mainnet) |
| `coreTexRegistry` | `0xa4d8a7Bb3Ba2D023af29Bf77601A61673ED89ad3` |
| `coreTexVerifier` | `0x82384E4DA334a4e3E1d8d2623359dC8c4d931Ed4` |
| `mining` | `0xB61BC7487424172CB9fa9dD381a9eC06C7067dCd` |
| registry view calls | `currentEpoch()`, `coreTexEpochContextSet(uint64)`, `epochFinalized(uint64)`, `liveStateRoot(uint64)`, `transitionCount(uint64)` |
| confirmation depth / lookback | 15 blocks / 64 epochs |

The **compatibility lock** likewise ships inside the wheel, keyed by runtime version
(`coretex_memory_agent/compatibility-lock-0.1.5.json`). The consumer path never supplies one.

Two environment variables exist and neither is part of the consumer path:

- `CORETEX_INTERNAL_FLAGS=1` — registers the operator/test-lane flags (`--compatibility-lock`,
  `--no-canary`, `--no-strict-validator`, `--transition-index`, `--frontier-artifact`,
  `--deployment-dir`, `--reconstructed-snapshot`, `--prefer-subprocess`,
  `--allow-prospective-genesis`). Without it argparse rejects them as unrecognised arguments.
- `CORETEX_SIDECAR_ALLOW_NONLOCAL=1` — required before `SidecarServer` will bind anything but
  loopback. Do not set it for this test.

`XDG_CONFIG_HOME` / `XDG_DATA_HOME` relocate the config and data directories if set.

## 3. Sync and activate the current state, then verify it

```bash
coretex sync                # thin consumer flow: one chain read, then bytes
coretex state status        # what is active now + state health
coretex state verify        # rehash + re-verify the active state (local, offline)
```

`coretex sync` (thin, the default) does exactly this, in order:

1. **one logical chain read** — five paced `eth_call`s at `block_number - 15` against the anchored
   registry, yielding `finalized_epoch`, `liveStateRoot`, `transitionCount`;
2. **fetch by published root** from the coordinator's immutable content-addressed routes — the
   frontier artifact at the live state root, the composition/deployment manifest at the frontier's
   `default_composition_root`, then each non-baseline profile's release manifest + `module.py`,
   plus any published canary corpus;
3. **re-hash everything locally** — the frontier must hash to the chain's root under the
   activation canonicalization, each manifest to its own self-hash root, each module to its
   manifest's `module_sha256`;
4. **refuse non-schema-v4 releases** at the earliest point the schema is knowable;
5. **canary** — every routed release is installed and served through a sandboxed hook worker
   (`in_process=False`) on a throwaway store, with the profile's own published corpus when one
   exists;
6. **atomically activate** — the only commit point.

Every command prints one JSON line: `{"ok": true, "result": {...}}` on success,
`{"ok": false, "error": "...", "reason": "..."}` on stderr with exit code 2 on refusal.

**Trust model, stated as the code states it.** Thin sync trusts the RPC endpoint for the *value*
of the live state root and nothing else. A hostile or stale RPC can pin you to a real-but-not-
current canonical state; it cannot make you run bytes nobody published, and it never reads,
writes, migrates or replaces your local sqlite store. The activation records this in its own
qualification block: `status: "THIN_CHAIN_READ"`, `production_authority: false`,
`independent_reconstruction: false`.

`coretex verify` is the independent-reconstruction audit path. It needs the optional resolver
extra (`coretex-validator==0.4.0`, not shipped here) and a published resolver snapshot, and it
stops before the commit point unless `--activate` is passed. It is **not** a prerequisite for the
e2e test.

Then the product surface is four lines:

```python
from coretex_memory_agent import AgentMemory

memory = AgentMemory.open()                       # last-synced composition, default scope + store
memory.sync_turn(messages=[{"role": "user", "content": "The deploy window moved to Tuesday 09:00."}])
served = memory.prefetch("when is the deploy window?", budget=256)
print(served.render())
memory.flush_session(); memory.close()
```

`AgentMemory.open()` with no arguments resolves the state dir, profile, scope
(`tenant=local, user=local, agent=coretex-agent`) and store path from the config file and the
activated state. If nothing has been activated it raises `PipelineNotSyncedError` naming
`coretex sync` rather than degrading to a reference-only mode.

## 4. What to expect from the live surface right now

- **As of 2026-08-19 the live epoch is 180**, and its confirmed head is **inherited from epoch 179
  via `lazy_inheritance`** — the active root is
  `0x803c90ceb0e2cbfb663c564b912ecd9f4dea6485da3ca97f71b7b8c4961051ef`. Epoch numbers move on
  their own clock; the root is the thing to compare. Read both from
  `GET /coretex/v5/status` → `epoch.head` (`epoch`, `root`, `source`, `inheritedFromEpoch`).
- **Bind `epoch.head.root` from `/coretex/v5/status` — never `composition.epoch` or
  `composition.parentFrontierRoot`.** Right after an epoch roll the composition/frontier documents
  legitimately report an *earlier* epoch than `epoch.head.epoch` (at the time of writing,
  `composition.epoch` is `179` while `epoch.head.epoch` is `180`): a new epoch that has accepted no
  transition yet inherits the previous epoch's frontier unchanged, so the document published at
  that root still carries the epoch it was minted in. That is inheritance, not a failed sync and
  not a stale coordinator. `composition.parentFrontierRoot` is the *predecessor* root and is never
  the thing to activate against. `coretex state status` likewise reports the epoch its chain read
  resolved (the most recent finalized epoch at the confirmed block, which can lag `epoch.head.epoch`
  by one after a roll); what must match is the root.
- The surface is essentially a **starter surface with no mining history**. Expect profiles bound to
  the **baseline release** — i.e. no mined improvement has yet displaced it as the current CoreTex
  state: the canary block reports `{"baseline": true}` for those, `health()`'s
  `current_release_root` is `null`, and `capabilities()` lists no mined hooks. That is the correct,
  non-degraded state for a fresh frontier — not a failure.
- **This is an operations test, not a content-richness test.** What it proves: install, config
  resolution, the chain read, content-addressed fetch and local re-hashing, strict-v4 enforcement,
  the sandboxed canary, atomic activation, ingest/serve round trips, Hermes lifecycle wiring,
  restart recovery and rollback. Retrieval quality on a starter surface tells you nothing.
- The four composition slots the runtime knows are `conv.pref.v1`, `doc.tool.v1`,
  `event.schema.v1` and `legacy.structured.v1` (baseline). The configured `profile` must be one the
  **activated** composition actually routes; if it is not, the open refuses and names what is
  routed. Read the routed set from `coretex state status` (the staged `profiles` map) or from
  `coretex sync`'s `fetch.profiles` and set `profile` to match.
- Sync is safe to re-run. It replaces the pipeline only; your `memory.db` is untouched by it.

## 5. Wire the Hermes provider into a Hermes harness

The provider is a real `agent.memory_provider.MemoryProvider` subclass. Its integration contract:

**(a) Same interpreter.** Hermes must be importable from the venv the three wheels are installed
into. Without it, `HERMES_AVAILABLE` is `False`, the shim installer still works, and constructing a
provider raises `HermesUnavailableError` naming Hermes `0.19.1` / source commit
`cc4cab2f592e60a197e796506de9168f74baf3ea` — the exact release this provider build
(`0.1.4+hermes.cc4cab2.chain-content-state`) is pinned to. The recorded qualification environment
for this integration was x86_64 / CPython 3.12 with an effective Python intersection of
`>=3.11,<3.14`; the adapter itself supports 3.10+, so build the Hermes venv on 3.11–3.13.

**(b) Install the discovery shim** into the Hermes home:

```bash
coretex-hermes-provider install --hermes-home "$HERMES_HOME"
# -> $HERMES_HOME/plugins/coretex/{__init__.py,plugin.yaml}
```

The shim's `register(ctx)` calls `ctx.register_memory_provider(CoreTexHermesMemoryProvider())`.
The provider's `name` is `coretex`.

**(c) Write the provider config** at `$HERMES_HOME/coretex/config.json` — either through Hermes's
own setup flow (the provider publishes a config schema for `state_dir`, `compatibility_lock`,
`profile_id`, `token_budget`, `consolidation_policy`) or directly. Format `…/v2`, every field
below is required, and an unknown or missing field is refused by name:

```json
{
  "format": "coretex-hermes-provider-config/v2",
  "state_dir": "/home/OPERATOR/.local/share/coretex/state",
  "compatibility_lock": "/path/to/coretex-portable-adapter-dist/compatibility/compatibility-lock-0.1.5.json",
  "profile_id": "event.schema.v1",
  "token_budget": 4096,
  "consolidation_policy": "session_end+event_delta=256+logical_storage_pressure=0.75+operator_maintenance",
  "tenant": "hermes",
  "counter_id": null,
  "allow_prospective_genesis": false
}
```

- `state_dir` **must be the directory `coretex sync` activated** — the provider opens a
  `CanonicalStateManager` over it and refuses with `no verified canonical state is active` if
  nothing was synced.
- `compatibility_lock` must be a **path to a file**. That is the only reason
  `compatibility/compatibility-lock-0.1.5.json` is shipped here; it is byte-identical to the copy
  inside the agent wheel (`verify.sh` step 6 proves the equality), so
  `python -c "from coretex_memory_agent.config import packaged_lock_path; print(packaged_lock_path())"`
  is an equally valid value.
- `profile_id` defaults to `conv.pref.v1` in the config schema, but it must name a profile the
  activated composition routes — set it to the same profile you configured in §2.
- `is_available()` returns `False` (silently, by design) unless the config format matches,
  `state_dir` is a directory and `compatibility_lock` is a file. If Hermes reports the provider as
  unavailable, check those three first.

**(d) Runtime behaviour inside Hermes.** `initialize(session_id, hermes_home=…, agent_identity=…,
user_id=…, agent_context=…)` builds the runtime for the `primary` agent context only. Per-run state
lives at `$HERMES_HOME/coretex/providers/<run_id>.json` with the backing store under
`$HERMES_HOME/coretex/runtime/<state_id>/<generation>/runs/<run_id>/memory.db`; `run_id` is derived
from `{tenant, user, identity, profile}`. `prefetch` injects the rendered context (previously
injected memory blocks are stripped before ingest, so served memory is never re-ingested as
evidence); `sync_turn` ingests user/assistant messages plus this turn's tool calls and results;
`on_memory_write` maps to supersede/retract/document-ingest. Four tools are exposed to the model:
`coretex_memory_status`, `coretex_memory_correct`, `coretex_memory_retract`,
`coretex_memory_hard_delete`.

**(e) State transitions under Hermes.** `sync_state(...)` and `rollback_state(...)` stage a new
canonical state, probe it, write a `…pending.json` transition record, activate, then swap the live
backend and close the old one. A crash between those steps is recovered on the next construction
from the durable pointer. A failure before the atomic pointer change leaves the previous state
active.

## 6. Troubleshooting (all strings below are the code's own)

| symptom | what it means / what to do |
|---|---|
| `the configured coordinator did not serve the requested CoreTex v5 artifact. An HTTP status alone cannot distinguish route policy, an unpublished exact root, rollout skew, or temporary service unavailability. Sync refuses closed: no pipeline activation was committed and the local memory store was not changed.` | 403/404/501/502/503 from the coordinator. Nothing was activated. Check `GET /coretex/v5/status` and that the **exact** requested root is published before retrying or changing endpoints. |
| `coordinator base URL must be http(s), got …` | `coordinator` is malformed. It must be a scheme + host base, **not** ending in `/coretex/v5`. |
| `… reports chain id N, but the packaged trust anchors name 8453 (base-mainnet); refusing to read canonical state from another chain` | the RPC is not Base mainnet. |
| `cannot reach the RPC endpoint …` / `… was refused by …` | endpoint down or rate-limiting. The read is paced; retry, or use another public Base RPC. |
| `currentEpoch() at block N returned no data — the anchored address … may hold no contract on this endpoint's chain` | RPC is serving a chain/fork without the deployed contracts. |
| `no finalized epoch within 64 epochs below …` | no finalized epoch in the lookback window at the confirmed block. |
| `epoch N reports a zero live state root; there is no canonical state to activate at this position` | nothing published at that position yet. |
| `frontier artifact hashes to X under the activation canonicalization but was published at Y` / `… does not hash to its requested root` | the coordinator served bytes that do not match the requested root. Hard refusal — never override. |
| `release manifest self-hash … does not match its publication root …` | same class of failure, at the release layer. |
| `this coretex-memory-agent wheel ships no compatibility lock for the installed coretex-memory X (it pins ['0.1.5'])` | the runtime version does not match the agent wheel. Install exactly `coretex-memory 0.1.5` from `wheels/`. |
| `the packaged compatibility lock at … does not describe the installed runtime` | mixed/patched installs. Rebuild the venv from these wheels only. |
| `no canonical state is active in '…': run \`coretex sync\` to fetch and activate the current pipeline` (`PipelineNotSyncedError`) | `AgentMemory.open()` before a successful sync, or a different `state_dir` than the one synced. |
| `the active composition routes no profile 'X' (it routes [...]); set 'profile' in the config file or pass profile= explicitly` | your configured profile is not in the activated composition. Use one it names. |
| `canary refused profile 'X': …` | the staged release did not load/serve through the sandboxed worker. The pointer did **not** move; the incumbent is still active. |
| `release destination … is not empty; refusing to inherit stale bundle files` | a leftover work tree. Re-run sync (it uses a fresh temp dir per run) rather than reusing one. |
| `unrecognized arguments: --no-canary` (or `--compatibility-lock`) | those are operator/test-lane flags. They exist only with `CORETEX_INTERNAL_FLAGS=1`, and the consumer path needs none of them. |
| `Hermes Agent is not importable in this environment (…), so a CoreTex Hermes provider cannot be constructed` | Hermes is not in this interpreter. Install Hermes 0.19.1 into the same venv, or install only the shim for a Hermes that lives elsewhere. |
| `invalid CoreTex Hermes config: unknown=[…], missing=[…], format=…` | `$HERMES_HOME/coretex/config.json` field set is wrong — see §5(c). |
| `no verified canonical state is active` (`ProviderConfigError`) | the provider's `state_dir` has no activation. Run `coretex sync` against that same directory. |
| `provider runtime binding disagrees with canonical state` / `bound provider runtime store is missing` | the state pointer moved (or the runtime tree was deleted) underneath a recorded provider binding. |
| `cannot transition canonical state without the recursion-fence serve log` | the per-run `memory.db.servelog.json` is missing; do not hand-copy provider runtime trees. |
| `refusing to bind the CoreTex sidecar to '…'` | the sidecar is loopback-only by design; it has no authentication. |
| `the deep flow needs a published resolver snapshot to reconstruct` | you landed in `coretex verify` / `--deep` without a snapshot. The thin path needs no snapshot at all. |

### Known cosmetic issues

- `coretex init --show` prints a `default_state_dir` computed from the real home directory even
  when `XDG_CONFIG_HOME`/`XDG_DATA_HOME` are set. It is a display of the built-in default, not a
  path anything opens. The `state_dir` value in the same output is the resolved path actually
  used; trust that one.

## 7. Verification transcript (this distribution, as built)

`./verify.sh [VENV_DIR]` was **executed** against these exact wheels on Linux x86_64 with
CPython 3.10.12, in a throwaway venv with `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`HERMES_HOME` pointed
at a temp sandbox so no real config or state was read or written. Result: **VERIFY OK**, no live
coordinator or RPC call made.

```
1.  wheel checksums ................ 3/3 OK (sha256sum -c SHA256SUMS)
2.  python ......................... Python 3.10.12 (>= 3.10 required)
3.  fresh virtualenv ............... created
4.  install (dependency order) ..... coretex-memory 0.1.5 (+ wasmtime 46.0.1 from PyPI)
                                     coretex-memory-agent 0.1.9
                                     coretex-hermes-provider 0.1.4
5.  imports + identities
      coretex_memory ............... 0.1.5
      coretex_memory_agent ......... 0.1.9   build 0.1.9+one.shape
      coretex_hermes_provider ...... 0.1.4   build 0.1.4+hermes.cc4cab2.chain-content-state
      hermes_available ............. False   (no Hermes in this venv, as expected)
      runtime_compatibility ........ runtime 0.1.5 / agent 0.1.9+one.shape /
                                     module_abi coretex-memory/miner-module/v1 v2 /
                                     policy_abi 1 / store_schema 1
      chain_id ..................... 8453
      anchors ...................... registry 0xa4d8a7Bb…9ad3, verifier 0x82384E4D…1Ed4,
                                     mining 0xB61BC748…7dCd
6.  packaged lock == shipped lock .. sha256 a87f7ac8e3e24d7eb2c1b5209e90358e903caecd338e17a9cff0122ee9f31a75
                                     and packaged_compatibility_lock() validated against the
                                     installed runtime
7.  agent CLI ..................... `coretex --help` -> {init,state,config,sync,verify}
                                     `coretex config` and `coretex init --show` returned
                                     {"ok": true, ...} with coordinator
                                     https://coordinator.agentmoney.net, rpc
                                     https://mainnet.base.org, profile event.schema.v1
8.  hermes shim ................... `coretex-hermes-provider --help` -> {install};
                                     `install --hermes-home …` wrote plugins/coretex/
                                     {__init__.py, plugin.yaml}
9.  runtime CLI ................... `coretex-memory --version` -> coretex-memory 0.1.5
10. local store round trip ........ ingest + context served 1 item; integrity ok, in_sync True
```
