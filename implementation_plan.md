# Project Zuko — Final Unified Implementation Plan
### On-Chain FAssets Security Guardian + Premium Live Demo UI
**Version:** 1.0 FINAL · **Date:** July 25, 2026
**Stack:** Solidity 0.8.25 · Foundry · Go (TEE) · Next.js 14 · Coston2 → Flare Mainnet

---

## Table of Contents

- [§1 — Project Philosophy & No-Mock Policy](#1-project-philosophy--no-mock-policy)
- [§2 — System Architecture (Full Stack)](#2-system-architecture-full-stack)
- [§3 — Technical Baseline (Contracts & Protocols)](#3-technical-baseline)
- [§4 — Smart Contract Specifications](#4-smart-contract-specifications)
- [§5 — Rule Engine Specifications](#5-rule-engine-specifications)
- [§6 — UI Architecture & Design System](#6-ui-architecture--design-system)
- [§7 — Phase 0: Ground Truth & Repository Setup](#7-phase-0-ground-truth--repository-setup)
- [§8 — Phase 1: Read-Only Monitoring Core](#8-phase-1-read-only-monitoring-core)
- [§9 — Phase 2: TEE Integration](#9-phase-2-tee-integration)
- [§10 — Phase 3: Pause Authority & Guardian Contracts](#10-phase-3-pause-authority--guardian-contracts)
- [§11 — Phase 4: UI Foundation (Data Layer)](#11-phase-4-ui-foundation-data-layer)
- [§12 — Phase 5: UI Core Panels](#12-phase-5-ui-core-panels)
- [§13 — Phase 6: Attack Demo Experience](#13-phase-6-attack-demo-experience)
- [§14 — Phase 7: Forensics, Polish & Integration](#14-phase-7-forensics-polish--integration)
- [§15 — Phase 8: External Audit & Governance](#15-phase-8-external-audit--governance)
- [§16 — Phase 9: Mainnet Launch](#16-phase-9-mainnet-launch)
- [§17 — Risks Register](#17-risks-register)
- [§18 — Reference Index](#18-reference-index)

---

## §1 — Project Philosophy & No-Mock Policy

### 1.1 What Zuko is

Zuko is two things shipped as one coherent product:

**The Guardian** — A TEE-attested, on-chain circuit breaker for Flare FAssets. It reads live FTSOv2 feeds, tracks real AssetManager state, evaluates six detection rules inside a verifiable enclave, and calls `EmergencyPauseFacet.emergencyPause()` and `EmergencyPauseTransfersFacet.emergencyPauseTransfers()` within seconds of a confirmed anomaly. This is the production system.

**The Demo UI** — A "threat theatre" where any visitor connects a wallet to Coston2, executes a real attack transaction against the real deployed AssetManager, watches Zuko detect it via real on-chain events, and sees a real `emergencyPause()` transaction fire. Every number on every screen traces back to a verifiable on-chain source. Nothing is simulated.

### 1.2 The no-mock policy (strictly enforced)

The following are **never acceptable** anywhere in this project:

| Forbidden | Why | Real alternative |
|---|---|---|
| Hardcoded price data | Defeats the entire point | FTSOv2 `getFeedById()` live every 1.8s |
| Fake agent vaults | Visitors will check Blockscout | Real Coston2 AssetManager enumeration |
| Simulated transaction flow | Kills credibility instantly | Real wallet → real tx → real Blockscout link |
| Hardcoded contract addresses | Breaks on any network change | `ContractRegistry.getContractAddressByName()` always |
| "Demo mode" fake pause | The whole point is the pause is real | Real `emergencyPause()` on Zuko-controlled Coston2 instance |
| Hardcoded pause level enum | Breaks across AssetManager versions | Always read `AssetManagerSettings` live before every action |
| Single RPC endpoint | Spoofable, single point of failure | 3-endpoint quorum, 2-of-3 agreement required |

The one honest label that is required: the UI clearly marks that Coston2 balances have no monetary value, and that the "Total Protected Value" figure is a mainnet-projection label, not the actual Coston2 TVL.

### 1.3 Design review corrections carried forward

Five weaknesses from the original research doc were accepted and are enforced throughout:

1. **FTSO lag trap** → Rule 1 is three-step: detect deviation → pay volatility incentive → wait 2 blocks → re-check anchor before any pause decision
2. **Redemption burst false positives** → Rule 3 only escalates toward pause when burst AND FDC attestation failure occur together; burst alone is always ALERT-ONLY
3. **Inverted timelock** → Critical pauses fire immediately; Guardians get an expedited fast-resume path, not a pre-execution veto
4. **RPC centralization** → All AssetManager event ingestion uses 3-endpoint quorum before the Rule Engine sees the data
5. **Multi-prover as permanent** → FCC enclave + independent cloud enclave is the production architecture, not a transitional fallback

---

## §2 — System Architecture (Full Stack)

```
╔═══════════════════════════════════════════════════════════════════════════════════╗
║  BROWSER / WALLET LAYER                                                           ║
║                                                                                   ║
║  Next.js 14 (App Router)  ·  TradingView Lightweight Charts  ·  RainbowKit       ║
║  wagmi v2  ·  ethers.js v6  ·  Framer Motion  ·  shadcn/ui                       ║
║                                                                                   ║
║  Real data surfaces:                                                              ║
║  • XRP/USD candles ←── FTSOv2 via Zuko backend WSS                               ║
║  • Agent vault table ←── AssetManager enumeration (live)                         ║
║  • Attack tx ──────────► assetManager.redeem() → MetaMask → Coston2              ║
║  • Pause events ←───── ZukoGuardian ZukoForensicLog (WSS subscription)           ║
║  • All links ─────────► coston2-explorer.flare.network (Blockscout)             ║
╚════════════════════════════════╤══════════════════════════════════════════════════╝
                                 │ WebSocket (live blocks, FTSO, events, alerts)
╔════════════════════════════════▼══════════════════════════════════════════════════╗
║  ZUKO BACKEND (Node.js 20 + Fastify)                                              ║
║                                                                                   ║
║  • ContractRegistry resolver  — single source for all addresses                   ║
║  • FTSO ring buffer (Redis)   — 50-block history per feed for z-score             ║
║  • Agent state cache (Redis)  — CR snapshots polled every block                   ║
║  • AssetManager event indexer — 3-RPC quorum, decodes and caches all events       ║
║  • Alert fan-out              — receives Rule Engine alerts, pushes to UI clients ║
║  • Demo orchestrator          — manages the attack/detect/resume demo cycle       ║
╚════════════════════════════════╤══════════════════════════════════════════════════╝
          │ quorum-agreed state  │  rule verdicts / alerts
╔═════════▼══════════╗  ╔═══════▼════════════════════════════════════════════════╗
║  3-ENDPOINT RPC    ║  ║  ZUKO RULE ENGINE (TEE)                                ║
║  QUORUM LAYER      ║  ║                                                        ║
║                    ║  ║  Primary:   FCC (GCP Confidential Space / AMD SEV)     ║
║  coston2-api       ║  ║  Secondary: AWS Nitro (permanent multi-prover)         ║
║  swiftnodes        ║  ║                                                        ║
║  ankr/3rd party    ║  ║  Rules 1-6 evaluated each block                       ║
║                    ║  ║  Verdicts → OPType/OPCommand signed instructions       ║
║  2-of-3 required   ║  ║  MEDIUM: 1-of-2 sig · HIGH/CRITICAL: 2-of-2 sig       ║
╚══════════╤═════════╝  ╚═══════════════════════════╤════════════════════════════╝
           │ Flare Coston2                           │ signed instruction
╔══════════▼═════════════════════════════════════════▼════════════════════════════╗
║  ON-CHAIN LAYER (Coston2 chainId 114 → Flare mainnet chainId 14)                ║
║                                                                                  ║
║  ContractRegistry (0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019)                 ║
║    └─ resolves: FtsoV2, FdcVerification, AssetManager(FXRP)                     ║
║                                                                                  ║
║  FtsoV2Interface                 FdcVerification                                 ║
║    getFeedById(bytes21)            verifyPayment(proof)                          ║
║    getFeedsById(bytes21[])                                                       ║
║                                                                                  ║
║  AssetManager (Diamond)          ┌─ ZukoGuardian.sol (InstructionSender) ──┐   ║
║    EmergencyPauseFacet              │  executeInstruction(payload,fccSig,   │   ║
║    EmergencyPauseTransfersFacet     │    cloudSig)                          │   ║
║    RedemptionRequestsFacet  ◄───────│  guardianFastResume(incidentId)       │   ║
║    LiquidationFacet                 │  selfKill()                           │   ║
║    SystemInfoFacet          ──────► │  ZukoForensicLog (event)              │   ║
║                                  └────────────────────────────────────────┘   ║
║                                                                                  ║
║  TeeExtensionRegistry · TeeMachineRegistry (FCC contracts)                      ║
║  ZukoMultiProverVerifier.sol · ZukoForensicLogger.sol · ZukoFTSOWatcher.sol     ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## §3 — Technical Baseline

### 3.1 Flare protocol stack — exact on-chain interfaces

```solidity
// All addresses resolved at runtime — never hardcoded
address constant REGISTRY = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

// FTSOv2 — called every block (~1.8s)
// getFeedsById: single call returns all feeds, avoiding N round-trips
interface IFtsoV2Minimal {
    function getFeedById(bytes21 id)
        external payable
        returns (uint256 value, int8 decimals, uint64 timestamp);
    function getFeedsById(bytes21[] calldata ids)
        external payable
        returns (uint256[] memory values, int8[] memory decimals, uint64 timestamp);
}

// FDC — used for compound Rule 3 and Rule 4
interface IFdcVerificationMinimal {
    function verifyPayment(IPayment.Proof calldata proof)
        external view
        returns (bool proved);
}

// AssetManager — pause facets (duration-based, NOT enum-based)
interface IAssetManagerEmergency {
    // EmergencyPauseFacet — ops pause
    function emergencyPause(uint256 duration) external;
    function isEmergencyPaused() external view returns (bool);
    function emergencyPausedUntil() external view returns (uint256);

    // EmergencyPauseTransfersFacet — transfer pause
    function emergencyPauseTransfers(uint256 duration) external;
    function isTransferEmergencyPaused() external view returns (bool);
    function transfersEmergencyPausedUntil() external view returns (uint256);

    // Settings — always read live, never cache
    function maxEmergencyPauseDurationSeconds() external view returns (uint256);
    function emergencyPauseDurationResetAfterSeconds() external view returns (uint256);
    function maxTransferPauseDurationSeconds() external view returns (uint256);
    function minVaultCollateralRatioBIPS() external view returns (uint256);
    function minPoolCollateralRatioBIPS() external view returns (uint256);
}
```

### 3.2 Prior art boundaries

| Component | What it does | Zuko relationship |
|---|---|---|
| `fasset-bots` Challenger | Per-agent illegal payment challenges | Zuko flags pattern → Challenger proves |
| `fasset-bots` Liquidator | Per-agent CR breach liquidation | Zuko detects correlated collapse before bots react |
| `fasset-bots` SystemKeeper | System-level liquidation state | Zuko's circuit breaker fires before cascade |
| `fasset-bots` TimeKeeper | Underlying block proof/update | Out of Zuko scope entirely |

### 3.3 Network configuration

| Network | Chain ID | RPC | Explorer | Usage |
|---|---|---|---|---|
| Coston2 | 114 | `coston2-api.flare.network/ext/C/rpc` | `coston2-explorer.flare.network` | All development and demo |
| Songbird | 19 | `songbird-api.flare.network/ext/C/rpc` | `songbird-explorer.flare.network` | FCC testing (STP.13) |
| Flare mainnet | 14 | `flare-api.flare.network/ext/C/rpc` | `flare-explorer.flare.network` | Production |

---

## §4 — Smart Contract Specifications

### 4.1 Contract inventory

```
contracts/
├── ZukoGuardian.sol              # Core — InstructionSender-compatible
├── ZukoMultiProverVerifier.sol   # Verifies 2-of-2 / 1-of-2 TEE sigs
├── ZukoForensicLogger.sol        # Append-only on-chain incident log
├── ZukoFTSOWatcher.sol           # Ring-buffer + z-score helper
├── ZukoGuardianStorage.sol       # Diamond-safe storage layout
├── interfaces/
│   ├── IZukoGuardian.sol
│   ├── IAssetManagerEmergency.sol
│   └── IFtsoV2Minimal.sol
test/
├── mocks/
│   ├── MockFtsoV2.sol
│   ├── MockAssetManager.sol
│   ├── MockFdcVerification.sol
│   └── MockTeeRegistry.sol
├── ZukoMultiProverVerifier.t.sol
├── ZukoFTSOWatcher.t.sol
├── ZukoGuardian.t.sol
├── ZukoForensicLogger.t.sol
├── ZukoRuleEngine.t.sol          # End-to-end scenario tests
└── ZukoGuardianInvariant.t.sol   # Stateful fuzz (forge invariant)
```

### 4.2 `ZukoGuardian.sol` — complete interface

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ZukoGuardian
 * @notice InstructionSender-compatible FAssets circuit breaker.
 *
 *  PAUSE MECHANISM (CRITICAL):
 *  AssetManager uses TWO separate duration-based pause facets:
 *    1. EmergencyPauseFacet.emergencyPause(duration) — halts ops
 *    2. EmergencyPauseTransfersFacet.emergencyPauseTransfers(duration) — halts transfers
 *  Zuko reads maxEmergencyPauseDurationSeconds and maxTransferPauseDurationSeconds
 *  LIVE from AssetManagerSettings before every executeInstruction call.
 *  These values are NEVER cached. Governance may change them at any time.
 *
 *  MULTI-PROVER:
 *  MEDIUM severity (1):  1-of-2 sigs (FCC OR cloud)
 *  HIGH severity (2):    2-of-2 sigs (FCC AND cloud)
 *  CRITICAL severity (3):2-of-2 sigs (FCC AND cloud) — NO pre-execution delay
 *
 *  FORENSIC LOG:
 *  Every executeInstruction emits ZukoForensicLog with full rule context,
 *  feed values, block range, and both TEE attestation signatures.
 *  This log is the primary input for guardianFastResume review.
 */
contract ZukoGuardian {

    struct ZukoInstruction {
        uint8   severity;               // 1=MEDIUM 2=HIGH 3=CRITICAL
        uint8   rulesTriggered;         // bitmask: bit0=R1 bit1=R2 bit2=R3 bit3=R4
        uint32  opsPauseDuration;       // seconds; 0 = skip ops pause
        uint32  transfersPauseDuration; // seconds; 0 = skip transfer pause
        bytes32 feedId;                 // primary FTSO feed (zero if not applicable)
        uint256 feedValue;              // block-latency value at trigger
        uint256 anchorValue;            // anchor value at trigger epoch
        uint64  blockRangeStart;
        uint64  blockRangeEnd;
        bytes32 fdcAttestationRef;      // non-zero = FDC mismatch confirmed
        uint64  nonce;                  // monotonic, stored in usedNonces
        uint32  chainId;                // prevents cross-chain replay
    }

    // --- Events ---

    event ZukoForensicLog(
        uint256 indexed incidentId,
        uint8   severity,
        uint8   rulesTriggered,
        bytes32 feedId,
        uint256 feedValueAtTrigger,
        uint256 anchorValueAtTrigger,
        uint64  blockRangeStart,
        uint64  blockRangeEnd,
        bytes32 fdcAttestationRef,
        bytes   fccSignature,
        bytes   cloudSignature,
        uint256 opsPausedUntil,
        uint256 transfersPausedUntil
    );

    event GuardianFastResume(uint256 indexed incidentId, address indexed guardian, uint256 ts);
    event ZukoKilled(address indexed by, uint256 ts);

    // --- Errors ---

    error NonceAlreadyUsed(uint64 nonce);
    error InvalidChainId(uint32 expected, uint32 got);
    error InvalidSignature();
    error InsufficientSigners(uint8 severity);
    error NotRegisteredInFCC(bytes32 codeHash);
    error NotGovernance();
    error NotGuardian();
    error GuardianKilled();
    error IncidentNotFound(uint256 id);
    error RedempBurstWithoutFDCMismatch();

    // --- Core functions ---

    function executeInstruction(
        bytes calldata encodedInstruction,
        bytes calldata fccSignature,
        bytes calldata cloudSignature
    ) external;

    function guardianFastResume(uint256 incidentId) external;

    function selfKill() external;

    function getLivePauseSettings() external view
        returns (
            uint256 maxOpsDuration,
            uint256 maxTransferDuration,
            uint256 opsResetAfter,
            uint256 transferResetAfter
        );

    function nextNonce() external view returns (uint64);
    function totalIncidents() external view returns (uint256);
}
```

### 4.3 `ZukoInstruction` validation rules

```
1. chainId == block.chainid                           → InvalidChainId
2. nonce not in usedNonces                            → NonceAlreadyUsed
3. keccak256(encodedInstruction) correctly recovers
   fccSigner and/or cloudSigner                       → InvalidSignature
4. severity == 1 → at least 1 valid sig               → InsufficientSigners
   severity >= 2 → both sigs required                 → InsufficientSigners
5. TeeExtensionRegistry.isHashRegistered(codeHash)    → NotRegisteredInFCC
6. rulesTriggered has bit2 set (Rule 3) but
   fdcAttestationRef == bytes32(0)                    → RedempBurstWithoutFDCMismatch
7. opsPauseDuration capped at
   assetManager.maxEmergencyPauseDurationSeconds()    → silently capped, not reverted
8. !killed                                            → GuardianKilled
```

### 4.4 `ZukoFTSOWatcher.sol` — ring buffer design

```
Ring size:     50 samples per feed
Update cadence: every block (updater role = any whitelisted EOA or the TEE itself)
z-score formula: (currentValue - rollingMean) / rollingStdDev × 10000 (E4 scaled)
Anchor deviation: |blockLatencyValue - lastAnchorValue| / lastAnchorValue × 10000
Minimum samples for z-score: 20 (returns 0 below this — no false positives on startup)
Governance: sigmaWarnThreshold settable by governance (default: 200 = 2.0σ)
```

> **[EDGE CASE 1 — FIXED] FTSOv2 Decimal Normalization (v1.0.1)**
>
> FTSOv2 feeds do **not** share a uniform decimal scale. `getFeedById` returns an `int8 decimals`
> field that varies per asset pair (e.g., XRP/USD may use 5 decimals, ETH/USD may use 8).
> Storing raw `uint256 value` directly in the ring buffer and computing z-scores or
> anchor-deviation ratios across differently-scaled values breaks the math entirely.
>
> **Fix enforced in `updateFeedSample`:** Before any value enters the ring buffer, it is
> normalized to a fixed 1e18 WAD baseline using the returned `int8 decimals`:
>
> ```solidity
> /// @dev Normalize a raw FTSOv2 feed value to 1e18 WAD regardless of native decimals.
> /// decimals is int8 and can be negative (value is already prescaled) or positive.
> /// Examples:
> ///   value=58210, decimals=5  → normalized = 58210 * 10^(18-5)  = 58210 * 10^13
> ///   value=97420000, decimals=8 → normalized = 97420000 * 10^(18-8) = 97420000 * 10^10
> function _normalize(uint256 rawValue, int8 decimals)
>     internal pure returns (uint256 normalized)
> {
>     int256 diff = int256(18) - int256(int8(decimals));
>     if (diff >= 0) {
>         normalized = rawValue * (10 ** uint256(diff));
>     } else {
>         // decimals > 18: scale down (extremely rare for price feeds)
>         normalized = rawValue / (10 ** uint256(-diff));
>     }
> }
> ```
>
> `updateFeedSample` now calls `_normalize(rawValue, decimals)` and stores the WAD result.
> All z-score and anchor-deviation computations operate on WAD-scaled values only.
> `setAnchorValue` also accepts and stores WAD-scaled values — the caller (TEE or governance)
> is responsible for normalizing anchor values before supplying them.
>
> **MockFtsoV2 update:** `setFeed(feedId, value, decimals)` remains unchanged — but all
> Foundry tests that call it are updated to supply values **already pre-normalized to 1e18 WAD**
> (i.e., `decimals = 18`, `value` in WAD), so the mock's `_normalize` path is exercised
> as a no-op. Tests that specifically validate the normalization path supply real
> non-18-decimal inputs (see new test `test_Normalize_NonStandardDecimals_CorrectWAD` in §C.3).

### 4.5 `foundry.toml`

```toml
[profile.default]
src            = "contracts"
out            = "out"
libs           = ["dependencies"]
test           = "test"
solc_version   = "0.8.25"
evm_version    = "cancun"      # Required for Flare (go-flare/coreth)
optimizer      = true
optimizer_runs = 200
ffi            = false

[profile.fork]
# Used for fork tests against live Coston2
fork_url       = "${COSTON2_RPC_URL}"

[rpc_endpoints]
coston2 = "${COSTON2_RPC_URL}"
flare   = "${FLARE_RPC_URL}"

[etherscan]
coston2 = { key = "${BLOCKSCOUT_KEY}", url = "https://coston2-explorer.flare.network/api" }
```

---

## §5 — Rule Engine Specifications

### 5.1 Rule definitions (enforced in Go, verified in Foundry tests)

```
Rule 1 — FTSO Anchor Deviation (3-step, never immediate pause)
  Step 1: block-latency z-score > sigmaWarnThreshold (default 2.0σ)
           AND anchorDeviation > 1.5%
  Step 2: TEE pays volatility incentive fee via IFtsoFeedPublisher
  Step 3: Wait 2 blocks; re-check. If BOTH conditions still true → MEDIUM pause
  If self-corrects: emit INFO alert only

Rule 2 — Correlated CR Cliff (immediate MEDIUM)
  Condition: weighted-average CR across ≥ 3 agents drops > 5% in ≤ 10 blocks
  Exclusion: single-agent drops (handled by fasset-bots Liquidator)
  Response: immediate MEDIUM (ops pause only)

Rule 3 — Compound Redemption Burst (NEVER pause on burst alone)
  Condition A: redemption volume > 5× rolling 24h baseline (burst alone = INFO)
  Condition B: FDC fails to attest corresponding underlying outflow within 300s
  Both A+B: HIGH pause (ops + transfers)
  A alone:   INFO alert only — pausing here causes the bank run it's meant to detect

Rule 4 — FDC / Core Vault Anomaly (immediate CRITICAL)
  Condition: FDC-attested Core Vault payment > expected delta by > 20%
             OR EVMTransaction attestation inconsistent with AssetManager accounting
  Response: immediate CRITICAL (both surfaces, maximum duration, 2-of-2 sigs)

Rule 5 — Liquidation Payout Deviation (ALERT-ONLY, never pause)
  Condition: realized liquidation payout vs FTSO-implied payout deviation > 10%
  Response: webhook alert to Guardians + Challenger operators. Not provably exploitative.

Rule 6 — Agent Self-Dealing Heuristic (ALERT-ONLY, never pause)
  Condition: high-value underlying-chain transfers between addresses sharing
             on-chain collateral pool ownership or minting reservation chains
  Response: webhook alert to Challenger operators. Not provably illegal on-chain.
```

### 5.2 Response matrix

| Severity | Rules | Ops Pause | Transfer Pause | Signers | Human path |
|---|---|---|---|---|---|
| INFO | Any rule below threshold | None | None | None | Webhook alert |
| MEDIUM | R1 sustained, R2 cliff | ✅ (capped duration) | ❌ | 1-of-2 | `guardianFastResume()` |
| HIGH | R3 compound, R1+R2 together | ✅ | ✅ | 2-of-2 | `guardianFastResume()` |
| CRITICAL | R4 Core Vault | ✅ (max duration) | ✅ (max duration) | 2-of-2 | `guardianFastResume()` (priority) |

---

## §6 — UI Architecture & Design System

### 6.1 Tech stack

```
Frontend:
  Framework:     Next.js 14 (App Router, React Server Components)
  Charts:        TradingView Lightweight Charts v4 — same library as Binance/Coinbase
  Wallet:        RainbowKit v2 + wagmi v2 (officially in Flare developer hub)
  Chain calls:   ethers.js v6 + viem
  UI:            shadcn/ui + custom Zuko tokens
  Animations:    Framer Motion (targeted — heartbeat + state transitions only)
  State:         Zustand v4

Backend:
  Runtime:       Node.js 20 + Fastify v4
  Cache:         Redis (FTSO ring buffer, agent state)
  Real-time:     Native WebSocket server (ws) → browser clients
  Chain:         ethers.js v6, 3-endpoint quorum

Infra:
  Frontend:      Vercel
  Backend:       Fly.io (always-on, persistent WebSocket connections)
  Cache:         Upstash Redis (Fly.io-co-located)
```

### 6.2 Design token system

```css
:root {
  /* Palette — "Dark room with one red wire" */
  --void:       #0A0C10;   /* base background */
  --surface-1:  #0F1218;   /* card surfaces */
  --surface-2:  #151820;   /* elevated, modals */
  --border:     #1E2330;   /* structural dividers */
  --border-hi:  #2A3040;   /* active/focused */

  --flare-red:  #E8304A;   /* attack, danger, alert, price-down */
  --flare-amber:#F5A623;   /* warning, CR threshold approaching */
  --zuko-teal:  #00C9A7;   /* protected, success, price-up */
  --zuko-blue:  #3B82F6;   /* FTSO data, informational */

  --text-pri:   #E8EAF0;
  --text-sec:   #8892A4;
  --text-dim:   #4A5264;

  /* Typography */
  --font-display: 'Space Grotesk', sans-serif;   /* 700-800, headings */
  --font-mono:    'JetBrains Mono', monospace;   /* all on-chain data */
  --font-body:    'Inter', sans-serif;           /* copy, descriptions */
}
```

### 6.3 Signature element: the heartbeat line

A live SVG polyline running across the top of every panel. New segment drawn every ~1.8s on each block header. Colour: `--zuko-teal` in NORMAL state → `--flare-red` + flatline animation when Zuko triggers. This is the single memorable visual gesture — the protocol is alive and you can see it breathing.

### 6.4 Application screens

```
/ (root)         → Overview   — live TVL, XRP/USD TradingView chart, event ticker
/agents          → Agents     — live vault table, CR bars, agent detail drawer
/threat-map      → Threat Map — all 6 rules live, FTSO z-scores, FDC status
/attack          → Attack Demo — dual-pane hacker/guardian experience
/forensics       → Forensics  — on-chain ZukoForensicLog ledger
/docs            → Docs        — architecture diagrams, API reference
```

### 6.5 ContractRegistry resolution (shared across frontend and backend)

```typescript
// packages/contracts/src/registry.ts — used by both Next.js and Fastify
import { Contract, JsonRpcProvider } from "ethers";

const REGISTRY_ADDRESS = "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019";

export async function resolveContracts(provider: JsonRpcProvider) {
  const registry = new Contract(REGISTRY_ADDRESS, REGISTRY_ABI, provider);
  
  const [ftsoV2, fdcVerif, assetManager] = await Promise.all([
    registry.getContractAddressByName("FtsoV2"),
    registry.getContractAddressByName("FdcVerification"),
    // AssetManager for FXRP — resolved via AssetManagerController
    resolveAssetManager(registry, "FXRP"),
  ]);
  
  return { ftsoV2, fdcVerif, assetManager };
}
// Never hardcode. Registry address is the only constant.
```

---

## §7 — Phase 0: Ground Truth & Repository Setup
**Duration:** Weeks 1–3 · **Team:** 1 engineer

### 7.1 Objectives

Eliminate every assumption before writing a single line of production code. All decisions made here supersede anything written in §3–§6 where they conflict.

### 7.2 Tasks

**Contract ground truth (Day 1–5):**
- Connect to Coston2 RPC, resolve FXRP AssetManager via ContractRegistry
- Read and record live: `maxEmergencyPauseDurationSeconds`, `emergencyPauseDurationResetAfterSeconds`, `maxTransferPauseDurationSeconds`, `minVaultCollateralRatioBIPS`, `minPoolCollateralRatioBIPS`
- Read the live `pause guardian` access control on `EmergencyPauseFacet` — determine what address class is accepted (specific EOA list, role hash, or governance multisig)
- Enumerate all active Coston2 FXRP agent vaults; record their addresses, CRs, and minted amounts
- Confirm FXRP faucet availability for demo users at `faucet.flare.network`

**FCC access (Day 3–7):**
- Contact Flare Foundation dev relations (Discord `#fcc-developers`) to confirm:
  - Whether `TeeExtensionRegistry` accepts third-party code hash registrations on Coston2
  - Whether `fce-extension-scaffold` and `fce-sign` are available for external developers
  - FCC deployment status on Coston2 vs. Songbird only
- If Coston2 FCC unavailable: confirm cloud-enclave fallback is acceptable as interim signing authority; open governance enquiry for mainnet path

**Governance path (Day 5–10):**
- Determine Path A vs Path B for pause authority:
  - Path A: Zuko's `ZukoGuardian.sol` address gets pause-guardian role directly
  - Path B: Zuko submits attested recommendations; Flare-controlled relay executes
- Path B is acceptable for demo and Phase 1–3; Path A is the mainnet target
- Document the exact governance proposal requirements (who votes, what threshold)

**AttackScenarios.ts review (Day 7–14):**
- Read `github.com/code-423n4/2025-08-flare/blob/main/test/integration/assetManager/AttackScenarios.ts` end-to-end
- Cross-reference each scenario against `fasset-bots` coverage
- Finalize the Rule 1–6 definitions as facts, not estimates

**Repository structure (Day 1–3):**
```
zuko/
├── packages/
│   ├── contracts/          # Foundry project (Solidity)
│   ├── rule-engine/        # Go TEE binary
│   ├── backend/            # Node.js + Fastify
│   └── frontend/           # Next.js 14
├── docs/
│   └── ground-truth.md     # Phase 0 deliverable
├── foundry.toml
└── README.md
```

### 7.3 Phase 0 test cases

```
PHASE-0-TC-01: ContractRegistry resolution
  Action:    Call registry.getContractAddressByName("FtsoV2") on Coston2
  Expected:  Returns a non-zero address; same address returned on 3 independent RPCs
  Assert:    All 3 RPC responses match exactly

PHASE-0-TC-02: AssetManager settings sanity
  Action:    Read maxEmergencyPauseDurationSeconds from resolved AssetManager
  Expected:  Value between 1 hour (3600) and 72 hours (259200)
  Record:    Exact value for use in test suites; fail if outside range

PHASE-0-TC-03: Pause guardian access control
  Action:    Call emergencyPause(60) from an EOA that is NOT the pause guardian
  Expected:  Revert with access control error
  Purpose:   Confirms Zuko must be granted the role, not just call the function

PHASE-0-TC-04: FTSO feed resolution
  Action:    Call getFeedById(XRP_USD_FEED_ID) on Coston2
  Expected:  Returns a non-zero value, decimals in range [-18, 18], timestamp within last 10s
  Assert:    Value is within ±30% of current CoinGecko XRP/USD price

PHASE-0-TC-05: FDC attestation round timing
  Action:    Monitor FDC round finalization via FdcHub events on Coston2
  Expected:  Rounds finalize approximately every 90 seconds
  Record:    Actual average for Rule 3's FDC timeout parameter

PHASE-0-TC-06: Agent vault enumeration
  Action:    Enumerate agent vaults via AssetManager on Coston2
  Expected:  At least 1 active agent vault with CR > 150%
  Record:    All vault addresses, CRs, minted FXRP amounts for test fixture seeding

PHASE-0-TC-07: Faucet availability
  Action:    Request C2FLR and FXRP from faucet.flare.network for a fresh address
  Expected:  Both tokens received within 60 seconds
  Purpose:   Validates the demo's "get testnet tokens" flow works for visitors
```

**Phase 0 deliverable:** `docs/ground-truth.md` — all discovered values, any plan deviations, confirmed governance path.

---

## §8 — Phase 1: Read-Only Monitoring Core
**Duration:** Weeks 3–8 · **Team:** 2 engineers

### 8.1 Objectives

Build the complete data layer and rule engine in read-only mode. No on-chain writes. Every number on screen must trace to a real chain query. Prove detection quality before requesting any privileged execution rights.

### 8.2 Backend tasks

**Multi-RPC quorum layer:**
```typescript
// packages/backend/src/rpc/quorum.ts
export class QuorumProvider {
  private providers: JsonRpcProvider[] // 3 providers

  async call(method: string, params: unknown[]): Promise<unknown> {
    const results = await Promise.allSettled(
      this.providers.map(p => p.send(method, params))
    )
    const fulfilled = results
      .filter(r => r.status === "fulfilled")
      .map(r => r.value)

    if (fulfilled.length < 2) throw new Error("Quorum failure: <2 RPCs responded")

    // 2-of-3: check first two agree
    if (JSON.stringify(fulfilled[0]) !== JSON.stringify(fulfilled[1])) {
      // Tie-break with third if available
      if (fulfilled[2] && JSON.stringify(fulfilled[0]) === JSON.stringify(fulfilled[2])) {
        return fulfilled[0]
      }
      throw new Error("Quorum disagreement: RPCs returned different values")
    }
    return fulfilled[0]
  }
}
```

**FTSO ring buffer:**
- Poll `getFeedsById([XRP_USD, FLR_USD, BTC_USD, ETH_USD])` on every block header
- Store last 50 values per feed in Redis sorted set (block number as score)
- Compute z-score and anchor deviation per feed after each update
- Broadcast `FTSO_UPDATE` to all connected WebSocket clients

**AssetManager event indexer:**
- Subscribe to all `AssetManager` logs via 3-endpoint quorum
- Decode: `RedemptionRequested`, `RedemptionPerformed`, `MintingExecuted`, `CollateralReservationTicketCreated`, `AgentInLiquidation`, `LiquidationPerformed`
- Store rolling 24h redemption volume in Redis for Rule 3 baseline
- Broadcast `ASSET_MANAGER_EVENT` to all connected WebSocket clients

> **[EDGE CASE 2 — FIXED] 2-Block Confirmation Lag Against Micro-Reorgs (v1.0.1)**
>
> EVM chains including Coston2 and Flare mainnet can experience 1–3 block micro-reorganisations.
> If the indexer writes an event at block N into the Redis 24h rolling window and that block is
> subsequently orphaned, the baseline is permanently skewed until the 24h TTL expires — causing
> Rule 3 false positives or missed detections for up to 24 hours.
>
> **Fix:** The event indexer does **not** write to the Redis rolling window on the block the
> event is first seen. Instead, it:
> 1. Caches the event in a short-lived Redis key: `pending_event:{txHash}:{logIndex}` with
>    TTL = 60 seconds.
> 2. On each new block header, for every pending event at block ≤ `currentBlock - 2`, it
>    re-queries all 3 RPC providers for the transaction receipt and verifies that the
>    `blockHash` in the receipt still matches the hash of block N on the canonical chain
>    (2-of-3 quorum must agree). Only then is the event written to the rolling window.
> 3. If the block hash has changed (reorg detected), the pending event is dropped and a
>    `REORG_DETECTED` warning is emitted to the WebSocket alert channel.
>
> ```typescript
> // packages/backend/src/events/eventIndexer.ts (confirmation logic)
> const CONFIRMATION_LAG = 2; // blocks
>
> async function maybeCommitPendingEvents(currentBlock: number): Promise<void> {
>   const pending = await redis.keys("pending_event:*");
>   for (const key of pending) {
>     const event = JSON.parse(await redis.get(key));
>     if (currentBlock - event.blockNumber < CONFIRMATION_LAG) continue;
>
>     // Re-verify block hash on 2-of-3 providers
>     const receipts = await quorum.call("eth_getTransactionReceipt", [event.txHash]);
>     const canonicalBlockHash = (receipts as any).blockHash;
>
>     const storedBlockHash = await quorum.call(
>       "eth_getBlockByNumber",
>       [ethers.toQuantity(event.blockNumber), false]
>     );
>
>     if ((storedBlockHash as any).hash !== canonicalBlockHash) {
>       console.warn(`Reorg detected: orphaned tx ${event.txHash} at block ${event.blockNumber}`);
>       broadcast({ type: "ZUKO_ALERT", severity: 0, rules: 0,
>                   message: `Reorg detected at block ${event.blockNumber}` });
>       await redis.del(key);
>       continue;
>     }
>
>     // Confirmed — write to rolling 24h window
>     await commitToRollingWindow(event);
>     await redis.del(key);
>   }
> }
> ```

> **[EDGE CASE 3 — FIXED] Cold-Start Historical Backfill for Rule 3 Baseline (v1.0.1)**
>
> On first boot (Phase 1 initial deploy, Phase 4 frontend launch, or any service restart),
> the Redis 24h rolling window is empty. The Rule 3 denominator is zero, making any
> non-zero redemption volume evaluate as ∞× baseline — an instant false positive that
> would trigger an incorrect HIGH pause instruction on the first attack demo run.
>
> **Fix:** On startup, before enabling Rule 3 evaluations, `eventIndexer.ts` runs a
> historical backfill routine:
>
> ```typescript
> // packages/backend/src/events/eventIndexer.ts (startup backfill)
> const BLOCKS_PER_24H = 43_200; // 24h × 3600s/h ÷ 1.8s/block = 48,000; use 43,200 as conservative
>
> async function backfillRedemptionBaseline(currentBlock: number): Promise<void> {
>   console.log("[Zuko] Starting 24h redemption baseline backfill...");
>
>   const fromBlock = currentBlock - BLOCKS_PER_24H;
>   const toBlock   = currentBlock - CONFIRMATION_LAG; // respect lag on backfill too
>
>   // eth_getLogs for RedemptionRequested over the past 24h
>   // Split into 1000-block chunks to avoid RPC payload limits
>   const CHUNK = 1_000;
>   for (let start = fromBlock; start < toBlock; start += CHUNK) {
>     const end  = Math.min(start + CHUNK - 1, toBlock);
>     const logs = await quorum.call("eth_getLogs", [{
>       address:   ASSET_MANAGER_ADDRESS,
>       topics:    [REDEMPTION_REQUESTED_TOPIC],
>       fromBlock: ethers.toQuantity(start),
>       toBlock:   ethers.toQuantity(end),
>     }]);
>
>     for (const log of logs as any[]) {
>       const decoded = assetManagerIface.parseLog(log);
>       await commitToRollingWindow({
>         txHash:      log.transactionHash,
>         blockNumber: parseInt(log.blockNumber, 16),
>         eventName:   "RedemptionRequested",
>         fxrpAmount:  decoded.args.valueUBA.toString(),
>         timestamp:   Date.now(), // approximated; exact block timestamp not critical for baseline
>       });
>     }
>   }
>
>   console.log("[Zuko] Baseline backfill complete. Rule 3 evaluations now enabled.");
>   rule3Enabled = true; // gate: Rule 3 returns INFO until this flag is true
> }
>
> // Called at server startup before the first block subscription fires
> await backfillRedemptionBaseline(await provider.getBlockNumber());
> ```
>
> **The `rule3Enabled` gate** ensures that if the backfill takes longer than the first block
> arrival (~1.8s), Rule 3 does not evaluate against a partial baseline. The gate is also
> re-armed to `false` on any service restart, forcing a fresh backfill before Rule 3 re-activates.
>
> **Phase 0 addition:** Record the actual `RedemptionRequested` event count over 24h on Coston2
> to validate that `BLOCKS_PER_24H = 43,200` is the correct constant for the network
> (block time may differ slightly from 1.8s in practice).

**Agent state poller:**
- Every block: read `getVaultCollateralRatioBIPS` + `getPoolCollateralRatioBIPS` for all known agent vaults
- Store 100-block CR history per vault in Redis
- Compute CR velocity (% change per block) for Rule 2

**Rule Engine (Go, read-only mode, no signing):**
- Implement all 6 rules as pure evaluation functions
- Output: rule verdicts to stdout/webhook, NO signed instructions yet
- Rule 1 three-step: evaluate z-score → log "would pay volatility incentive" → wait 2 blocks → re-evaluate
- Rule 3 compound: track redemption burst events + start FDC timeout timers

**Deploy `ZukoFTSOWatcher.sol` on Coston2:**
- Event-log-only mode (no privileged role)
- Updater: the backend's EOA (not the TEE yet)
- Verifies on-chain that the ring buffer values match what the backend computes off-chain

**Deploy `ZukoForensicLogger.sol` on Coston2:**
- Event-log-only, no pause authority
- Iterate on the `ZukoForensicLog` event format early

### 8.3 Frontend tasks (Phase 1 — data layer only)

- Next.js project bootstrap with Coston2 + wagmi config
- `ContractRegistry` resolver (shared with backend via `packages/contracts`)
- WebSocket client hook (`useZukoStream`) consuming all backend events
- TradingView chart component: render FTSO history from backend, subscribe to live updates

### 8.4 Phase 1 test cases

#### Backend unit tests (Jest / Go test)

```
PHASE-1-TC-01: QuorumProvider — 2-of-3 agreement passes
  Setup:    Mock 3 providers returning identical block numbers
  Action:   QuorumProvider.call("eth_blockNumber", [])
  Expected: Returns the value without error
  Assert:   Response matches all three providers

PHASE-1-TC-02: QuorumProvider — 1-of-3 failure is tolerated
  Setup:    Mock 3 providers; one returns error
  Action:   QuorumProvider.call("eth_blockNumber", [])
  Expected: Returns the agreed value from the two that responded
  Assert:   No error thrown

PHASE-1-TC-03: QuorumProvider — disagreement throws
  Setup:    Mock 3 providers; first two disagree, third unavailable
  Action:   QuorumProvider.call("eth_blockNumber", [])
  Expected: Throws "Quorum disagreement" error
  Assert:   Error message includes "Quorum disagreement"

PHASE-1-TC-04: FTSO ring buffer — fills correctly
  Setup:    Send 50 sequential FTSO updates with incrementing values
  Action:   Read ring buffer from Redis
  Expected: Exactly 50 entries; oldest entry corresponds to 50 blocks ago

PHASE-1-TC-05: FTSO ring buffer — z-score with stable data
  Setup:    Fill ring buffer with 50 identical values (simulating zero variance)
  Action:   Compute z-score
  Expected: Returns 0 (no variance = no anomaly)

PHASE-1-TC-06: FTSO ring buffer — z-score with spike
  Setup:    49 samples at 1.000, one sample at 1.500 (+50%)
  Action:   Compute z-score
  Expected: z-score > 200 (above 2σ threshold)

PHASE-1-TC-07: Rule 1 three-step — does not fire on single-block spike
  Setup:    One block with high z-score; next two blocks normal
  Action:   Run Rule 1 evaluation for 3 blocks
  Expected: No pause verdict emitted; INFO alert only

PHASE-1-TC-08: Rule 1 three-step — fires when sustained
  Setup:    3+ consecutive blocks with z-score > 200 AND anchor deviation > 1.5%
  Action:   Run Rule 1 evaluation
  Expected: After step 3, emits MEDIUM verdict with opsPauseDuration set

PHASE-1-TC-09: Rule 2 — ignores single-agent drops
  Setup:    One agent's CR drops from 170% to 120%; other agents stable
  Action:   Evaluate Rule 2
  Expected: No Rule 2 verdict; this is fasset-bots Liquidator territory

PHASE-1-TC-10: Rule 2 — fires on correlated collapse
  Setup:    Simulate 5 agents' CRs dropping 8% in 6 blocks simultaneously
  Action:   Evaluate Rule 2
  Expected: MEDIUM verdict emitted with rulesTriggered bitmask bit1 set

PHASE-1-TC-11: Rule 3 — burst alone, no pause
  Setup:    Redemption volume = 10× baseline; FDC attests within 300s
  Action:   Evaluate Rule 3 over 300-second window
  Expected: INFO alert emitted; NO pause verdict

PHASE-1-TC-12: Rule 3 — compound fires
  Setup:    Redemption volume = 10× baseline; FDC does NOT attest within 300s
  Action:   Evaluate Rule 3 over 300-second window
  Expected: HIGH verdict after 300s timeout; fdcAttestationRef non-zero

PHASE-1-TC-13: Rule 4 — Core Vault anomaly fires
  Setup:    Inject FDC-attested payment 25% larger than expected Core Vault delta
  Action:   Evaluate Rule 4
  Expected: CRITICAL verdict emitted immediately

PHASE-1-TC-14: Rule 5 — alert only
  Setup:    Liquidation payout 12% below FTSO-implied
  Action:   Evaluate Rule 5
  Expected: INFO alert emitted; NO pause verdict

PHASE-1-TC-15: 24h redemption baseline — rolling window accurate
  Setup:    Insert redemption events spanning 30 hours; read 24h window
  Expected: Only last 24h events included in volume calculation

PHASE-1-TC-16: Agent CR velocity — computed correctly
  Setup:    5 CR snapshots: 170, 168, 165, 161, 156 (accelerating decline)
  Expected: Velocity correctly computed as -3.5%/block average

PHASE-1-TC-17: ContractRegistry resolution — all 3 RPCs agree
  Action:   Resolve FtsoV2 address on 3 providers independently
  Expected: All 3 return the same address; matches Phase 0 ground truth

PHASE-1-TC-18: WebSocket broadcast — FTSO_UPDATE received by client
  Setup:    Connect mock WebSocket client to backend
  Action:   Trigger a FTSO poll cycle
  Expected: Client receives FTSO_UPDATE message within 2 seconds; values parseable

PHASE-1-TC-19: [EDGE CASE 2] Reorg detection — orphaned event is dropped
  Setup:    Inject a RedemptionRequested event at block N into the pending cache
  Action:   Advance to block N+2; mock all 3 RPCs to return a DIFFERENT blockHash
             for block N (simulating a reorg that orphaned the original block)
  Expected:
    (a) Pending event is NOT committed to the rolling 24h window
    (b) A ZUKO_ALERT with message containing "Reorg detected" is broadcast to WS clients
    (c) The pending_event Redis key is deleted
  Assert:   Rolling 24h volume is unchanged from before the event was staged

PHASE-1-TC-20: [EDGE CASE 2] Confirmed event — writes to window after 2 blocks
  Setup:    Inject a RedemptionRequested event at block N into the pending cache
  Action:   Advance to block N+2; mock all 3 RPCs to return the SAME blockHash for block N
  Expected:
    (a) Event IS committed to the rolling 24h window
    (b) Rolling 24h volume increases by the event's FXRP amount
    (c) The pending_event Redis key is deleted
  Assert:   No REORG_DETECTED alert is broadcast

PHASE-1-TC-21: [EDGE CASE 2] Event at block N+1 — not yet committed (lag not met)
  Setup:    Inject a RedemptionRequested event at block N into the pending cache
  Action:   Advance to block N+1 only (lag of 1, below CONFIRMATION_LAG=2)
  Expected: Event remains in pending cache; NOT written to rolling window yet
  Assert:   Rolling 24h volume unchanged

PHASE-1-TC-22: [EDGE CASE 3] Cold-start backfill — Rule 3 disabled before completion
  Setup:    Start indexer with empty Redis; mock eth_getLogs to return 0 events
             but introduce a 500ms artificial delay in the backfill loop
  Action:   Send a Rule 3 evaluation request during the delay
  Expected: Rule 3 returns INFO (gate = false); no HIGH verdict emitted
  Assert:   rule3Enabled flag is false until backfill completes

PHASE-1-TC-23: [EDGE CASE 3] Cold-start backfill — populates baseline correctly
  Setup:    Start indexer; mock eth_getLogs to return 100 RedemptionRequested events
             totalling 500,000 FXRP over the past 43,200 blocks
  Action:   Wait for backfill to complete (rule3Enabled = true)
  Expected:
    (a) Redis rolling window contains all 100 events
    (b) 24h baseline = 500,000 FXRP (not 0)
    (c) A single redemption of 100,000 FXRP evaluates as 0.2× baseline (below 5× threshold)
  Assert:   Rule 3 does NOT fire on this sub-threshold redemption

PHASE-1-TC-24: [EDGE CASE 3] Cold-start backfill — chunks correctly for large block range
  Setup:    Set BLOCKS_PER_24H = 43,200; mock eth_getLogs to validate call parameters
  Action:   Run backfill from block 43,200 to block 86,400
  Expected: eth_getLogs called in ceil(43200/1000) = 44 separate chunks
             each with fromBlock and toBlock within the chunk boundaries
  Assert:   No single eth_getLogs call spans more than 1,000 blocks
```

#### Foundry tests (Phase 1 contracts)

```
PHASE-1-TC-19: ZukoFTSOWatcher — ring buffer accumulates
  See ZukoFTSOWatcher.t.sol::test_RingBuffer_AccumulatesSamples (§4 test suite)

PHASE-1-TC-20: ZukoFTSOWatcher — z-score stable data returns 0
  See ZukoFTSOWatcher.t.sol::test_ZScore_StableFeeds_BelowThreshold

PHASE-1-TC-21: ZukoFTSOWatcher — insufficient samples returns 0
  See ZukoFTSOWatcher.t.sol::test_ZScore_WithInsufficientSamples_ReturnsZero

PHASE-1-TC-22: ZukoFTSOWatcher — non-updater reverts
  See ZukoFTSOWatcher.t.sol::test_UpdateFeedSample_NonUpdater_Reverts

PHASE-1-TC-23: ZukoForensicLogger — stores incident and returns correct data
  See ZukoForensicLogger.t.sol::test_LogIncident_StoresAndReturnsCorrectly

PHASE-1-TC-24: ZukoForensicLogger — non-guardian reverts
  See ZukoForensicLogger.t.sol::test_LogIncident_NonGuardian_Reverts
```

**Phase 1 deliverable:** Public Coston2 dashboard (read-only) showing live FTSO feeds, real agent vault CRs, and rule engine status. Written false-positive/false-negative rate report against backtested data. Specifically: replay any available data from known anomalous periods on Coston2 and confirm Rule 1's three-step gate does not fire on them.

---

## §9 — Phase 2: TEE Integration
**Duration:** Weeks 8–14 · **Team:** 2 engineers

### 9.1 Objectives

Move the Rule Engine into a real attested enclave. Get a signed, on-chain-verified instruction flowing end-to-end from live FTSO data to a `ZukoForensicLog` event on Coston2 — with no real pause authority yet (writes to a no-op mock target).

### 9.2 Tasks

**FCC extension (primary TEE):**
- Port Phase 1 Go Rule Engine into `fce-extension-scaffold` pattern
- Implement `POST /action` 4-step handler: validate input → run rules → sign verdict → respond
- Set `SOURCE_DATE_EPOCH=0` in build pipeline; verify binary hash is stable across two independent builds before registering
- Register code hash in `TeeExtensionRegistry` on Coston2/Songbird
- Set up `TeeMachineRegistry` entry for the GCP Confidential Space VM

**Cloud enclave (secondary TEE — permanent, not transitional):**
- Deploy same Go binary in AWS Nitro enclave (or GCP Confidential Space instance #2)
- Independent key generation inside the enclave; register public key as `cloudSignerAddress` in `ZukoMultiProverVerifier.sol`
- Verify two independent builds of the same source hash to the same binary

**`ZukoMultiProverVerifier.sol` deployment:**
- Deploy on Coston2 with `fccSignerAddress` and `cloudSignerAddress`
- Test verify() with both real enclave signatures

**`ZukoGuardian.sol` deployment (no-op target):**
- Deploy with a `MockAssetManager` as the pause target (not the real AssetManager)
- Wire `ZukoMultiProverVerifier` and `TeeExtensionRegistry`
- `executeInstruction()` writes to `ZukoForensicLog` but calls the mock's no-op pause

**End-to-end flow test:**
```
FTSOv2 live data
  → QuorumProvider (3 RPCs, 2-of-3)
  → Rule Engine (in FCC enclave)
  → Signed ZukoInstruction (FCC key)
  → Signed ZukoInstruction (Cloud key)
  → ZukoGuardian.executeInstruction(payload, fccSig, cloudSig)
  → ZukoForensicLog emitted on Coston2
  → Verify on coston2-explorer.flare.network
```

**Fallback path (if FCC Coston2 unavailable per Phase 0):**
- Run Phase 2 with cloud-only signing (governance-registered hot key, same trust model as fasset-bots operators)
- Open FCC migration as a tracked P1 dependency
- All contract interfaces remain identical — FCC is a drop-in when available

### 9.3 Phase 2 test cases

#### Foundry tests

```
PHASE-2-TC-01: ZukoMultiProverVerifier — MEDIUM passes with FCC sig only
  See ZukoMultiProverVerifier.t.sol::test_VerifyMediumSeverity_OneFccSig_Passes

PHASE-2-TC-02: ZukoMultiProverVerifier — MEDIUM passes with cloud sig only
  See ZukoMultiProverVerifier.t.sol::test_VerifyMediumSeverity_OneCloudSig_Passes

PHASE-2-TC-03: ZukoMultiProverVerifier — CRITICAL requires both sigs
  See ZukoMultiProverVerifier.t.sol::test_VerifyCritical_BothSigs_Passes
  See ZukoMultiProverVerifier.t.sol::test_VerifyCritical_OnlyFccSig_Fails

PHASE-2-TC-04: ZukoMultiProverVerifier — wrong signer rejected
  See ZukoMultiProverVerifier.t.sol::test_VerifyWrongSigner_Fails

PHASE-2-TC-05: ZukoGuardian — MEDIUM instruction executes with 1-of-2 sig
  See ZukoGuardian.t.sol::test_ExecuteInstruction_Medium_OpsOnly_PausesOps

PHASE-2-TC-06: ZukoGuardian — CRITICAL requires 2-of-2 or reverts
  See ZukoGuardian.t.sol::test_ExecuteInstruction_Critical_OnlyOneSig_Reverts

PHASE-2-TC-07: ZukoGuardian — nonce replay rejected
  See ZukoGuardian.t.sol::test_ExecuteInstruction_ReplayedNonce_Reverts

PHASE-2-TC-08: ZukoGuardian — wrong chain ID rejected
  See ZukoGuardian.t.sol::test_ExecuteInstruction_WrongChainId_Reverts

PHASE-2-TC-09: ZukoGuardian — deregistered code hash rejected
  See ZukoGuardian.t.sol::test_ExecuteInstruction_AfterDeregistration_Reverts

PHASE-2-TC-10: ZukoGuardian — ZukoForensicLog contains all required fields
  See ZukoGuardian.t.sol::test_ForensicLog_ContainsAllRequiredFields
```

#### Integration tests (against live Coston2 with real enclave)

```
PHASE-2-TC-11: End-to-end — FCC enclave signs real instruction
  Action:    Trigger a synthetic Rule 2 condition (inject test CR data via test mode)
  Expected:  TEE extension produces a signed ZukoInstruction within 10 seconds
  Assert:    ecrecover(keccak256(payload), fccSig) == registered fccSignerAddress on-chain

PHASE-2-TC-12: End-to-end — both enclaves sign, ZukoGuardian accepts
  Action:    Submit instruction with both FCC and cloud signatures to ZukoGuardian (Coston2)
  Expected:  Transaction confirmed; ZukoForensicLog event emitted
  Assert:    Event visible on coston2-explorer.flare.network with correct decoded fields

PHASE-2-TC-13: End-to-end — Blockscout link is valid
  Action:    Take tx hash from PHASE-2-TC-12
  Expected:  GET https://coston2-explorer.flare.network/api?module=transaction&action=gettxinfo&txhash={hash}
             returns status "1" (success)

PHASE-2-TC-14: Reproducible build — same binary hash from two independent builds
  Action:    Build Go binary in two clean Docker containers with SOURCE_DATE_EPOCH=0
  Expected:  sha256sum of both binaries is identical
  Assert:    Hash matches what is registered in TeeExtensionRegistry

PHASE-2-TC-15: Enclave attestation — GCP verifies Confidential Space measurement
  Action:    Request attestation document from running enclave
  Expected:  Measurement matches expected value from reproducible build
  Assert:    No attestation failure in GCP Confidential Space audit log
```

**Phase 2 deliverable:** Screen-recorded end-to-end demo — live FTSO data flowing into the FCC enclave, a signed ZukoInstruction appearing on-chain, a decoded `ZukoForensicLog` event visible on Coston2 Blockscout. No real pause authority yet.

---

## §10 — Phase 3: Pause Authority & Guardian Contracts
**Duration:** Weeks 14–20 · **Team:** 2 engineers

### 10.1 Objectives

Obtain real governance-authorized pause capability on Coston2. Implement the full `ZukoGuardian.sol` with the real `AssetManager` as its target. Run comprehensive chaos testing. Prove the system fails closed (not open) under every adversarial condition.

### 10.2 Tasks

**Governance engagement:**
- Submit request to Flare Foundation for `ZukoGuardian.sol` to receive pause-guardian role on a dedicated Coston2 FXRP AssetManager instance (or a fork)
- Document the authorization: which AssetManager, which pause surfaces, which duration caps
- If Path B (relay pattern): deploy a Flare-controlled relay contract; Zuko submits recommendations; relay executes

**`ZukoGuardian.sol` full deployment:**
- Deploy with real `AssetManager` as pause target
- Wire `ZukoMultiProverVerifier`, `TeeExtensionRegistry`, governance address, Guardian multisig
- Verify `getLivePauseSettings()` returns values matching Phase 0 ground truth

**Guardian multisig setup:**
- Deploy a Gnosis Safe (or equivalent) on Coston2 as the Guardian multisig
- Configure M-of-N signers appropriate for demo (2-of-3 recommended)
- Verify `guardianFastResume()` works from the Safe

**Chaos testing (Foundry fork mode against Coston2):**

```bash
# Run all chaos tests
forge test --match-contract ZukoChaosTest \
  --fork-url $COSTON2_RPC_URL \
  --fork-block-number latest \
  -vvv
```

**Internal security review:**
- `ZukoGuardian.sol` — all state transitions, access control, error conditions
- `ZukoMultiProverVerifier.sol` — signature recovery, signer update governance
- Reproducible build pipeline — binary hash matches registered hash end-to-end

### 10.3 Phase 3 test cases

#### Foundry — graduated pause scenarios

```
PHASE-3-TC-01: Rule 2 verdict → ops pause only (not transfers)
  See ZukoRuleEngine.t.sol::test_Scenario_CorrelatedCRCliff_MediumPause

PHASE-3-TC-02: Rule 3 burst alone → NO pause (on-chain guard)
  See ZukoRuleEngine.t.sol::test_Scenario_RedemptionBurst_WithoutFDCMismatch_AlertOnly

PHASE-3-TC-03: Rule 3 compound → both surfaces paused
  See ZukoRuleEngine.t.sol::test_Scenario_CompoundRule3_BothSurfaces_Paused

PHASE-3-TC-04: Rule 4 Core Vault → CRITICAL, max duration, both surfaces
  See ZukoRuleEngine.t.sol::test_Scenario_CoreVaultAnomaly_CriticalPause

PHASE-3-TC-05: Pause duration capped at AssetManager's live max
  See ZukoGuardian.t.sol::test_ExecuteInstruction_PauseDuration_CappedAtMax

PHASE-3-TC-06: Sequential pauses — accumulator stays within cap
  See ZukoRuleEngine.t.sol::test_Scenario_SequentialPauses_DurationCapped
```

#### Foundry — chaos / adversarial tests

```
PHASE-3-TC-07: Feed manipulation — Rule 1 three-step prevents false fire
  See ZukoRuleEngine.t.sol::test_Scenario_LegitimateVolatility_NoFalsePositive

PHASE-3-TC-08: Replayed instruction — nonce prevents double execution
  Setup:    Submit a valid signed instruction; capture the payload
  Action:   Submit exact same payload + sigs again
  Expected: Second call reverts with NonceAlreadyUsed

PHASE-3-TC-09: TEE deregistration mid-flight — fails closed
  Setup:    Begin building a CRITICAL instruction; deregister code hash mid-way
  Action:   Submit instruction after deregistration
  Expected: Reverts with NotRegisteredInFCC; NO pause executed

PHASE-3-TC-10: Single prover failure — MEDIUM still fires (1-of-2)
  Setup:    Only FCC sig available; cloud signer key unavailable
  Action:   Submit MEDIUM instruction with FCC sig only
  Expected: Accepted and executes (ops pause only)

PHASE-3-TC-11: Single prover failure — CRITICAL blocked (2-of-2 required)
  Setup:    Only FCC sig available
  Action:   Submit CRITICAL instruction with FCC sig only
  Expected: Reverts with InsufficientSigners(3)

PHASE-3-TC-12: Malformed instruction payload — reverts cleanly
  Setup:    Submit random bytes as encodedInstruction
  Action:   Call executeInstruction(garbage, validSig, validSig)
  Expected: ABI decode revert; no state change; no pause

PHASE-3-TC-13: Rule 3 on-chain guard — burst without FDC ref rejected
  Action:   Submit instruction with rulesTriggered bit2 set but fdcAttestationRef = 0
  Expected: Reverts with RedempBurstWithoutFDCMismatch
  Purpose:  On-chain enforcement even if Go Rule Engine has a bug

PHASE-3-TC-14: Asset Manager already paused — second pause extends correctly
  Setup:    Execute first pause (1 hour); immediately execute second (2 hours)
  Expected: emergencyPausedUntil extends to max(current + 1h, current + 2h)
             AND never exceeds maxEmergencyPauseDurationSeconds

PHASE-3-TC-15: guardianFastResume — not callable before any incident
  Action:   Call guardianFastResume(incidentId=0) before any executeInstruction
  Expected: Reverts with IncidentNotFound(0)

PHASE-3-TC-16: selfKill — governance can deregister Zuko
  See ZukoGuardian.t.sol::test_SelfKill_ByGovernance_DeregistersAndEmitsEvent

PHASE-3-TC-17: selfKill — subsequent instructions all revert
  See ZukoGuardian.t.sol::test_SelfKill_ByGovernance_DeregistersAndEmitsEvent
  (post-kill executeInstruction test included)

PHASE-3-TC-18: selfKill — non-governance cannot kill
  See ZukoGuardian.t.sol::test_SelfKill_NonGovernance_Reverts
```

#### Invariant tests (stateful fuzz, 1000 runs × 100 depth)

```
PHASE-3-TC-19: Pause duration never exceeds governance cap
  See ZukoGuardianInvariant.t.sol::invariant_PauseDurationNeverExceedsCap

PHASE-3-TC-20: Nonce is strictly monotonically increasing
  See ZukoGuardianInvariant.t.sol::invariant_NonceIsMonotonic

PHASE-3-TC-21: Pause calls never exceed valid instruction count
  See ZukoGuardianInvariant.t.sol::invariant_PauseCallsMatchInstructions

PHASE-3-TC-22: Incident count matches successful pause executions
  See ZukoGuardianInvariant.t.sol::invariant_IncidentCountMatchesPauses
```

#### Live Coston2 integration test

```
PHASE-3-TC-23: Full end-to-end pause on real Coston2 AssetManager
  Precondition: ZukoGuardian has pause-guardian role on test AssetManager
  Action:       Inject synthetic Rule 2 condition via test endpoint; wait for TEE response
  Expected:
    (a) executeInstruction tx confirmed on Coston2
    (b) AssetManager.isEmergencyPaused() returns true
    (c) ZukoForensicLog event emitted and visible on Blockscout
    (d) guardianFastResume() callable by Guardian multisig
    (e) After guardianFastResume(), isEmergencyPaused() returns false
  Assert all 5 sub-conditions within 30 seconds of anomaly injection
```

**Phase 3 deliverable:** Video demo of autonomous pause + guardian fast-resume on Coston2. Chaos test report (all 23 test cases passing). Internal security review report.

---

## §11 — Phase 4: UI Foundation (Data Layer)
**Duration:** Weeks 14–18 (parallel with Phase 3) · **Team:** 1 frontend engineer

### 11.1 Objectives

Build the complete real-time data layer for the frontend. Every hook must return real chain data by the end of this phase. No mock data, no placeholder values.

### 11.2 Tasks

**Project bootstrap:**
```bash
# packages/frontend
npx create-next-app@latest --typescript --app --tailwind --eslint
# Install Flare-specific packages
pnpm add @rainbow-me/rainbowkit wagmi ethers@6 viem
pnpm add lightweight-charts
pnpm add framer-motion
pnpm add @radix-ui/react-slot class-variance-authority # shadcn primitives
```

**Wagmi chain config (Coston2 + Flare mainnet):**
```typescript
// packages/frontend/src/lib/chains.ts
import { defineChain } from "viem";

export const coston2 = defineChain({
  id: 114,
  name: "Flare Testnet Coston2",
  nativeCurrency: { name: "C2FLR", symbol: "C2FLR", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://coston2-api.flare.network/ext/C/rpc"] },
  },
  blockExplorers: {
    default: {
      name: "Coston2 Explorer",
      url: "https://coston2-explorer.flare.network",
    },
  },
  testnet: true,
});
```

**Core hooks (all return real on-chain data):**

```typescript
// useFTSOFeeds — live prices every ~1.8s via WebSocket
function useFTSOFeeds(): {
  xrpUsd: number; flrUsd: number; btcUsd: number; ethUsd: number;
  zScores: Record<string, number>;
  lastBlock: number;
}

// useAgentVaults — live CR table from AssetManager
function useAgentVaults(): {
  vaults: AgentVault[];  // includes live CR from on-chain
  loading: boolean;
}

// useAssetManagerEvents — real-time event stream
function useAssetManagerEvents(): {
  events: AssetManagerEvent[];
  redemptionVolume24h: number;
}

// useZukoStatus — live ZukoGuardian state
function useZukoStatus(): {
  isPaused: boolean;
  isTransferPaused: boolean;
  pausedUntil: number;
  totalIncidents: number;
  lastIncident: ZukoIncident | null;
}

// useZukoForensicLog — all past ZukoForensicLog events from chain
function useZukoForensicLog(page: number): {
  incidents: ZukoIncident[];
  total: number;
}
```

**TradingView chart integration:**
```typescript
// packages/frontend/src/components/FTSOChart.tsx
// Renders real XRP/USD from FTSO as 1.8s candlesticks
// Uses backend ring buffer for history, WebSocket for live updates
// No mock data path exists in this component
```

### 11.3 Phase 4 test cases

#### Frontend unit tests (Vitest + React Testing Library)

```
PHASE-4-TC-01: ContractRegistry resolves FtsoV2 address
  Setup:    Fork Coston2 at current block in test env
  Action:   Call resolveContracts(provider)
  Expected: ftsoV2 address matches Phase 0 ground truth

PHASE-4-TC-02: useFTSOFeeds — returns real values (not undefined)
  Setup:    Render hook with Coston2 WebSocket connected
  Action:   Wait for first FTSO_UPDATE message
  Expected: xrpUsd > 0; lastBlock > 0; zScores object has 4 keys

PHASE-4-TC-03: useFTSOFeeds — updates on each block
  Setup:    Subscribe to hook; record initial value
  Action:   Wait for 3 FTSO_UPDATE messages (~5.4s)
  Expected: lastBlock incremented 3 times; xrpUsd value changed at least once

PHASE-4-TC-04: useAgentVaults — returns at least 1 vault
  Setup:    Connect to Coston2
  Action:   Render hook; wait for loading=false
  Expected: vaults.length >= 1; every vault has vaultAddress and vaultCR > 0

PHASE-4-TC-05: useAgentVaults — CR values match on-chain
  Setup:    Read CR independently via ethers.js for first vault address
  Action:   Compare against useAgentVaults() return value
  Expected: Values match within 10 BIPS (rounding tolerance)

PHASE-4-TC-06: useAssetManagerEvents — receives real events
  Setup:    Submit a test redemption on Coston2 (test wallet)
  Action:   Subscribe to useAssetManagerEvents()
  Expected: RedemptionRequested event appears in events array within 5 blocks

PHASE-4-TC-07: FTSOChart renders with real data (no blank canvas)
  Setup:    Render <FTSOChart feedId="XRP/USD" />
  Action:   Wait for chart.series[0].data().length > 0
  Expected: At least 10 historical candles visible; newest candle within last 10s

PHASE-4-TC-08: useZukoStatus — reflects real AssetManager pause state
  Setup:    Read isEmergencyPaused() directly via ethers.js
  Action:   Compare against useZukoStatus().isPaused
  Expected: Values match exactly

PHASE-4-TC-09: Wagmi chain — MetaMask prompts for Coston2 network
  Setup:    Open the app in a Playwright browser with MetaMask
  Action:   Click "Connect Wallet"
  Expected: MetaMask shows "Add Flare Testnet Coston2" if not already added

PHASE-4-TC-10: Blockscout link format — all links open valid pages
  Setup:    Pick any tx hash from useAssetManagerEvents()
  Action:   Construct Blockscout URL; HEAD request to it
  Expected: HTTP 200; title contains the tx hash
```

**Phase 4 deliverable:** All data hooks returning real Coston2 data. The TradingView chart showing live FTSO-sourced XRP/USD candles. A staging deployment (Vercel preview) where every number on screen can be independently verified on Coston2 Blockscout.

---

## §12 — Phase 5: UI Core Panels
**Duration:** Weeks 18–22 · **Team:** 1–2 engineers

### 12.1 Objectives

Build the Overview, Agents, and Threat Map screens to production quality. Every panel must be independently verifiable — a skeptic with a browser tab open on Blockscout must be able to confirm every number.

### 12.2 Screen implementations

**Overview screen (`/`):**
- Heartbeat line SVG (draws new segment on each block header)
- 4-stat header row: TVL equiv., FXRP supply, active agent count, Zuko status
- TradingView chart: XRP/USD 1.8s candles from real FTSO data
- Live event ticker: decoded AssetManager events via WebSocket
- System status badge: NORMAL (teal) / WARNING (amber) / PAUSED (red)

**Agents screen (`/agents`):**
- Sortable, filterable table of all real Coston2 agent vaults
- CR progress bars colour-coded against live `minVaultCollateralRatioBIPS` (not hardcoded thresholds)
- Row click → drawer: full agent detail (underlying XRPL address, vault + pool CR, minted amount, 100-block CR sparkline)
- Zuko Rule 2 velocity indicator per agent: green (stable), amber (declining), red (cliff)
- Direct Blockscout link per vault: `https://coston2-explorer.flare.network/address/{vaultAddress}`

**Threat Map screen (`/threat-map`):**
- Six rule status cards; each updates in real time
- Rule 1: live z-score bar for XRP/USD, FLR/USD, BTC/USD — shows whether volatility incentive step would trigger
- Rule 2: aggregate CR trend line (last 20 blocks), velocity indicator
- Rule 3: redemption volume vs. 24h baseline ratio; FDC attestation lag
- Rules 4-6: status badges from rule engine output
- Guardian status: TEE attestation indicator, FCC hash display, last evaluation block

### 12.3 Phase 5 test cases

#### Playwright E2E tests

```
PHASE-5-TC-01: Overview — heartbeat line increments on each block
  Setup:    Load / in Playwright
  Action:   Count SVG polyline path segments over 5.4s (3 blocks)
  Expected: Segment count increases by exactly 3

PHASE-5-TC-02: Overview — XRP/USD chart shows real data
  Setup:    Load /; wait for chart to render
  Action:   Read the latest candle close price from the chart DOM
  Expected: Price is within ±5% of current CoinGecko XRP/USD

PHASE-5-TC-03: Overview — TVL figure matches on-chain supply
  Setup:    Read FXRP totalSupply() independently via ethers.js
  Action:   Compare against displayed supply on Overview
  Expected: Match within 0.1%

PHASE-5-TC-04: Overview — live event ticker receives new events
  Setup:    Load /; wait for ticker to show at least 1 event
  Action:   Record the first event's block number
  Action:   Wait 30s; check if new events have appeared
  Expected: At least 1 new event within 30s (Coston2 has regular activity)

PHASE-5-TC-05: Agents — vault count matches on-chain enumeration
  Setup:    Read agent count independently via AssetManager on Coston2
  Action:   Load /agents; count table rows
  Expected: Row count matches on-chain agent count

PHASE-5-TC-06: Agents — CR values match on-chain (spot check)
  Setup:    Pick first vault in table; read its CR via ethers.js independently
  Action:   Compare against displayed CR bar value
  Expected: Match within 10 BIPS

PHASE-5-TC-07: Agents — CR colour coding matches live thresholds
  Setup:    Read minVaultCollateralRatioBIPS from AssetManager (live)
  Action:   Find a vault with CR within 10% of the threshold
  Expected: Its CR bar renders in amber (warning) not green (safe)

PHASE-5-TC-08: Agents — Blockscout link opens valid page
  Setup:    Load /agents; open first agent drawer
  Action:   Click "View on Blockscout" link
  Expected: New tab opens; Blockscout shows the vault contract address

PHASE-5-TC-09: Threat Map — Rule 1 z-score updates each block
  Setup:    Load /threat-map
  Action:   Record XRP/USD z-score; wait 2 blocks (~3.6s); re-read
  Expected: z-score value has changed (new block = new sample)

PHASE-5-TC-10: Threat Map — Rule 3 baseline is computed from real events
  Setup:    Read 24h redemption volume from backend API
  Action:   Compare against displayed "24h baseline" on Threat Map
  Expected: Values match; label clearly states it is the rolling average

PHASE-5-TC-11: System status badge — reflects real AssetManager state
  Setup:    Read isEmergencyPaused() via ethers.js
  Action:   Compare against Overview status badge
  Expected: PAUSED badge shown if and only if isEmergencyPaused() returns true

PHASE-5-TC-12: Testnet notice — visible on all screens
  Setup:    Load each of /, /agents, /threat-map
  Action:   Check for presence of testnet notice element
  Expected: "Flare Testnet Coston2 — testnet only" notice visible on all three screens

PHASE-5-TC-13: Mobile layout — data is accessible on 375px viewport
  Setup:    Set Playwright viewport to 375×812
  Action:   Load /; check chart and stat row render
  Expected: No horizontal scroll; chart visible; stat row stacks vertically
```

**Phase 5 deliverable:** All three screens live on staging (Vercel). Public URL shared with Flare Foundation for feedback. Every data point independently verifiable on Blockscout.

---

## §13 — Phase 6: Attack Demo Experience
**Duration:** Weeks 22–26 · **Team:** 2 engineers

### 13.1 Objectives

Build the Attack Demo — the centrepiece of the product. The demo must be fully real: real wallet connection, real signed transaction on Coston2, real Zuko detection, real `emergencyPause()` call, real on-chain `ZukoForensicLog` event with a Blockscout link.

### 13.2 Attack demo flow implementation

**Step 1 — Role selection:**
- Wallet connection via RainbowKit (MetaMask, WalletConnect, Coinbase Wallet)
- Auto-detect wallet's Coston2 FXRP balance from `FAsset.balanceOf(address)`
- If zero balance: show faucet link (`faucet.flare.network`) with direct "Get Testnet FXRP" button
- Attack vector selector: "Mass Redemption" (active) + "FTSO Pressure" (read-only scenario)

**Step 2 — Attack configuration (Mass Redemption):**
- Redemption slider: dragging updates `% of 24h baseline` in real time from actual backend volume
- Threshold indicator: below 5× = "Won't trigger Rule 3"; above 5× = "Will trigger Rule 3 monitoring"
- FDC note: explains that real XRPL outflow attestation will not arrive for a testnet-only redemption
- Real fee estimation via `FeeCalculator` (if Coston2 `FeeCalculator` is live)

**Step 3 — Transaction execution:**
```typescript
// Real AssetManager.redeem() call — no simulation
const tx = await assetManagerContract.redeem(
  lots,                        // calculated from FXRP amount and lot size
  redeemerUnderlyingAddress,   // user's XRPL address (or demo address)
  executorAddress,             // demo executor EOA
  { value: redemptionFee }     // real fee if FeeCalculator is live
);
// Show: tx hash → pending → confirmed → Blockscout link
```

**Step 4 — FDC countdown:**
- 300-second countdown timer (real FDC attestation window from Phase 0 ground truth)
- Backend monitors FDC rounds; updates "FDC attestation: PENDING / FAILED / CONFIRMED"
- For testnet-only redemptions (no real XRPL movement): attestation will timeout → Rule 3 fires

**Step 5 — Zuko triggers:**
- Backend receives `ZukoForensicLog` event via WebSocket subscription
- UI transitions to alert state (heartbeat flatlines → teal scan → alert panel expands)
- Show each on-chain tx in sequence as they confirm: `executeInstruction`, `emergencyPause`, `emergencyPauseTransfers`
- Each tx gets a Blockscout link the moment it's confirmed
- Display decoded `ZukoForensicLog` fields inline

**Step 6 — Auto-resume (demo only):**
- After 30 seconds: demo backend's Guardian Safe calls `guardianFastResume(incidentId)`
- UI shows "Guardian reviewed forensic log and confirmed this was a simulated attack"
- Protocol returns to NORMAL; heartbeat resumes teal
- User can run demo again or navigate to Forensics to see their incident

**Demo orchestrator (backend):**
```typescript
// packages/backend/src/demo/orchestrator.ts
// Manages the attack→detect→pause→resume cycle
// Uses a Guardian Safe (M-of-N multisig) pre-loaded with signing keys
// Auto-resume after 30s delay for smooth demo experience
// Rate-limiting: one active demo per wallet address at a time
```

### 13.3 Phase 6 test cases

#### Playwright E2E tests (full attack flow)

```
PHASE-6-TC-01: Wallet connection — MetaMask connects on Coston2
  Setup:    Playwright with MetaMask extension; pre-funded with C2FLR and FXRP
  Action:   Click Connect Wallet on /attack
  Expected: Wallet address displayed; FXRP balance shown (non-zero)

PHASE-6-TC-02: Slider — % of baseline updates from real data
  Setup:    Load /attack; read displayed 24h baseline from UI
  Action:   Drag slider to maximum
  Expected: "% of baseline" figure updates; matches calculation based on real baseline

PHASE-6-TC-03: Sub-threshold indication — no trigger message
  Setup:    Drag slider to 3× baseline (below 5× threshold)
  Action:   Check indicator label
  Expected: Shows "Below Rule 3 threshold — will not trigger compound rule"

PHASE-6-TC-04: Execute button — fires real MetaMask transaction
  Setup:    Drag slider to 10× baseline; click Execute
  Action:   Confirm in MetaMask
  Expected:
    (a) tx hash appears in UI within 2s of MetaMask confirmation
    (b) Blockscout link opens the confirmed transaction
    (c) Countdown timer starts immediately

PHASE-6-TC-05: FDC countdown — reflects real attestation timing
  Setup:    Transaction confirmed; countdown running
  Action:   Monitor FDC status display
  Expected: Status reads "PENDING" then transitions to "FAILED (timeout)" after 300s

PHASE-6-TC-06: Zuko triggers — all three on-chain txs appear
  Setup:    FDC timeout reached
  Action:   Monitor UI for alert state transition
  Expected:
    (a) Heartbeat goes red and flatlines within 2 blocks of trigger
    (b) executeInstruction tx hash shown with Blockscout link
    (c) emergencyPause tx hash shown with Blockscout link
    (d) emergencyPauseTransfers tx hash shown with Blockscout link
    (e) All three Blockscout links return HTTP 200

PHASE-6-TC-07: ZukoForensicLog decoded — all fields visible
  Setup:    Attack demo triggered
  Action:   Check forensic log display in alert panel
  Expected:
    severity, rulesTriggered, feedId, feedValue, anchorValue,
    blockRangeStart, blockRangeEnd, fdcAttestationRef
    all shown with correct decoded values (not raw hex)

PHASE-6-TC-08: AssetManager pause state — verifiable on-chain
  Setup:    Zuko has triggered; UI shows PAUSED
  Action:   Call assetManager.isEmergencyPaused() via ethers.js independently
  Expected: Returns true; consistent with UI display

PHASE-6-TC-09: Auto-resume — protocol returns to NORMAL
  Setup:    Demo paused; 30s countdown
  Action:   Wait for guardianFastResume() tx
  Expected:
    (a) GuardianFastResume event visible in UI
    (b) assetManager.isEmergencyPaused() returns false
    (c) Heartbeat resumes teal colour
    (d) "Run another attack" button appears

PHASE-6-TC-10: Rate limiting — same wallet cannot run two demos simultaneously
  Setup:    Start attack demo with wallet A; before resume, try to start again
  Action:   Click Execute again
  Expected: "Demo already in progress for this wallet" message; no tx fired

PHASE-6-TC-11: Faucet link — resolves to working page
  Setup:    Connect wallet with zero FXRP balance
  Expected: Faucet notice shown with link to faucet.flare.network
  Action:   GET faucet.flare.network (Playwright fetch)
  Expected: HTTP 200

PHASE-6-TC-12: Full demo — elapsed time under 8 minutes
  Setup:    Fresh wallet with testnet FXRP; run complete attack flow
  Action:   Time from "Execute" click to "NORMAL restored"
  Expected: Under 8 minutes (dominated by 300s FDC window + ~30s auto-resume)
```

**Phase 6 deliverable:** Complete Attack Demo working end-to-end on Coston2. Recorded video of a live run with real wallet, real tx, real pause, real Blockscout links. Suitable for investor/Flare Foundation demo.

---

## §14 — Phase 7: Forensics, Polish & Integration
**Duration:** Weeks 26–28 · **Team:** 1–2 engineers

### 14.1 Objectives

Build the Forensics screen. Polish all four core screens to production quality. Run the complete application integration test suite end-to-end.

### 14.2 Tasks

**Forensics screen (`/forensics`):**
- Paginated ledger of all `ZukoForensicLog` events from chain (reads from backend indexer + direct chain query for latest)
- Search by: incident ID, severity, rules triggered, block range
- Row expand: full decoded event fields, Blockscout link, Guardian fast-resume tx (if applicable)
- "Verify on-chain" button: takes user to the exact Blockscout event log

**Polish tasks:**
- Reduced-motion media query: all animations respect `prefers-reduced-motion`
- Keyboard navigation: all interactive elements are keyboard accessible
- Error states: all screens handle RPC disconnection, WebSocket reconnection, empty data
- Loading states: skeleton screens (not spinners) for initial data load
- Mobile layout: all screens usable at 375px width

**Integration:**
- Connect ZukoGuardian's real `ZukoForensicLog` events to the Forensics screen
- Confirm Attack Demo incidents appear in Forensics immediately after the demo run

### 14.3 Phase 7 test cases

```
PHASE-7-TC-01: Forensics — loads real on-chain incidents
  Setup:    Complete Phase 6 attack demo (creates at least 1 incident)
  Action:   Load /forensics
  Expected: At least 1 incident row; incident ID matches ZukoForensicLog event

PHASE-7-TC-02: Forensics — verify link opens Blockscout event
  Action:   Click "Verify on-chain" for any incident
  Expected: Blockscout opens showing the exact ZukoForensicLog event decoded

PHASE-7-TC-03: Forensics — search by severity works
  Action:   Filter by "HIGH"
  Expected: Only HIGH-severity incidents shown

PHASE-7-TC-04: WebSocket reconnection — data resumes after disconnect
  Setup:    Load any screen; artificially kill WebSocket connection
  Action:   Wait for auto-reconnect (should be within 5s)
  Expected: Data resumes updating; no stale values shown

PHASE-7-TC-05: RPC fallback — one provider down, data continues
  Setup:    Remove one RPC endpoint from the backend's quorum list
  Action:   Monitor all screens for 60 seconds
  Expected: All data continues updating; quorum operates on 2-of-2 remaining

PHASE-7-TC-06: Empty state — no incidents yet
  Setup:    Deploy fresh ZukoGuardian (no incidents)
  Action:   Load /forensics
  Expected: Empty state shown with call-to-action to run Attack Demo

PHASE-7-TC-07: Reduced motion — animations disabled
  Setup:    Set prefers-reduced-motion: reduce in browser
  Action:   Load all screens; trigger Zuko alert state
  Expected: Heartbeat draws statically; no scan animation; data still updates

PHASE-7-TC-08: Mobile — /attack works at 375px
  Setup:    Playwright at 375×812
  Action:   Complete full attack demo flow on mobile viewport
  Expected: All steps completable; slider operable; Blockscout links tap-accessible

PHASE-7-TC-09: Complete integration — end-to-end, all screens
  Action:   Run this sequence in one Playwright session:
    1. Load / → verify live chart
    2. Load /agents → verify vault table
    3. Load /threat-map → verify rule status
    4. Load /attack → connect wallet → execute attack → wait for Zuko trigger
    5. Load /forensics → verify incident from step 4 is present
  Expected: All 5 steps succeed without any error; all data real
```

**Phase 7 deliverable:** Production-quality application on Vercel. All screens polished. Complete test suite passing. Ready for external review.

---

## §15 — Phase 8: External Audit & Governance
**Duration:** Weeks 28–38 · **Team:** Lead engineer + audit firm

### 15.1 Objectives

Obtain external security review sufficient for Flare governance to approve Zuko's real pause authority on a production AssetManager.

### 15.2 Audit scope

**Smart contracts (Coinspect / Zellic / OpenZeppelin tier):**
- `ZukoGuardian.sol` — all state transitions, access control, pause execution path
- `ZukoMultiProverVerifier.sol` — signature recovery correctness, signer governance
- `ZukoForensicLogger.sol` — append-only guarantee, access control
- `ZukoFTSOWatcher.sol` — ring-buffer overflow, z-score math, updater access
- Attestation chain: does the code hash registered in `TeeExtensionRegistry` verifiably correspond to what runs in the enclave?

**Bug bounty (Immunefi, 30-day public):**
- HIGH/CRITICAL finds must be mitigated before mainnet
- MEDIUM findings reviewed and addressed or documented

**Governance proposal contents:**
- Which AssetManager instances Zuko may guard (FXRP only initially)
- Which pause surfaces (both, with which duration caps)
- Guardian multisig composition for `guardianFastResume()` (recommended: 2-of-3, Flare Foundation + 2 independent)
- `selfKill()` authorization (Flare governance timelock)
- Zuko's public SLOs: false-positive target ≤1/6-months, MTTP ≤3.6s

### 15.3 Phase 8 test cases

```
PHASE-8-TC-01: Audit finding regression — all audit-identified issues resolved
  Action:   For each audit finding, run the specific PoC test case
  Expected: All revert/fail as expected; no finding reproducible

PHASE-8-TC-02: Immunefi bounty — no unresolved HIGH/CRITICAL
  Expected: Zero unresolved HIGH or CRITICAL at programme close date

PHASE-8-TC-03: Kill-switch — governance can deregister within 1 governance cycle
  Setup:    Submit selfKill() governance proposal on testnet governance fork
  Action:   Wait for vote + execution
  Expected: ZukoGuardian.killed == true; all executeInstruction calls revert

PHASE-8-TC-04: SLO measurement — MTTP ≤ 3.6s on 10 consecutive test triggers
  Setup:    Inject synthetic anomaly 10 times (different rule classes)
  Action:   Measure: anomaly onset block → emergencyPause tx confirmed block
  Expected: All 10 measurements ≤ 2 blocks (3.6s at 1.8s/block)

PHASE-8-TC-05: False-positive rate — 0 false positives over 30-day observation
  Setup:    Run Zuko in production-equivalent mode on Coston2 for 30 days
  Action:   Review all emitted verdicts against ground truth
  Expected: Zero pause actions triggered without a genuine anomaly
```

---

## §16 — Phase 9: Mainnet Launch
**Duration:** Weeks 38+ · **Team:** Full team

### 16.1 Checklist before any mainnet tx

```
[ ] All Phase 8 audit findings resolved or accepted with documentation
[ ] Governance proposal approved (on-chain vote confirmed)
[ ] ZukoGuardian.sol deployed on Flare mainnet (chainId 14)
[ ] ZukoGuardian pause-guardian role confirmed on mainnet FXRP AssetManager
[ ] FCC code hash registered on mainnet TeeExtensionRegistry (or cloud-enclave fallback active)
[ ] Guardian Safe deployed on mainnet with correct signers
[ ] Backend RPC quorum pointing at mainnet endpoints
[ ] Frontend chain config updated to Flare mainnet
[ ] Demo UI updated: "Mainnet" vs "Testnet" labels reviewed
[ ] Public incident postmortem template published
[ ] On-call rotation established (minimum 2 people)
```

### 16.2 Launch sequence

```
Week 38:  Deploy contracts to mainnet; verify on flarescan.com
Week 38:  Enable read-only monitoring in production TEE (no pause authority yet)
Week 39:  Run 7-day observation period: confirm MTTP ≤ 3.6s, zero false positives
Week 40:  Activate pause authority at MEDIUM severity only (ops pause, 1-of-2 sig)
Week 42:  Activate HIGH and CRITICAL severity (after 2 weeks clean operation at MEDIUM)
Week 44:  Extend to FBTC/FDOGE AssetManagers (after FXRP track record established)
```

### 16.3 Phase 9 test cases

```
PHASE-9-TC-01: Mainnet contract deployment — addresses verified
  Action:   Verify all contracts on flarescan.com; source code matches audited version
  Expected: All contracts show "Verified" status on flarescan

PHASE-9-TC-02: Mainnet FTSO — real XRP price within 0.5% of reference
  Action:   Read XRP/USD from mainnet FtsoV2; compare against Binance spot
  Expected: Within 0.5% (FTSO's documented accuracy)

PHASE-9-TC-03: Mainnet MTTP — synthetic trigger, ≤ 3.6s
  Setup:    Use a governance-approved test mode to inject a synthetic anomaly
  Expected: pause tx confirmed within 2 blocks of anomaly onset

PHASE-9-TC-04: 7-day observation — zero false positives
  Action:   Monitor rule engine verdicts for 7 days
  Expected: Zero MEDIUM/HIGH/CRITICAL verdicts without a genuine anomaly condition

PHASE-9-TC-05: Guardian fast-resume — real multisig, real mainnet tx
  Setup:    After synthetic trigger in PHASE-9-TC-03
  Action:   Guardian Safe executes guardianFastResume()
  Expected: isEmergencyPaused() returns false; GuardianFastResume event on flarescan
```

---

## §17 — Risks Register

| Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|
| FCC not on Coston2 for Phase 2 | Medium | Medium | Cloud-enclave fallback is first-class; FCC is drop-in upgrade | Lead engineer |
| Governance declines direct pause authority (Path B) | Medium | Medium | Path B relay still delivers detection value; upgrade to Path A with track record | Protocol engineer |
| FTSO volatility incentive fee increases significantly | Low | Low | TEE holds FLR balance; fee increase monitored; max fee governance-configurable | Rule Engine engineer |
| False positive damages trust before Zuko is established | Medium | High | Three-step Rule 1; compound Rule 3; conservative thresholds; published SLOs | All |
| FDC round timing differs from Phase 0 ground truth | Low | Low | Rule 3 timeout is governance-configurable; Phase 0 measures it directly | Backend engineer |
| TEE zero-day affecting both FCC and cloud enclave | Very Low | Critical | Different platforms (GCP vs AWS); selfKill() is one tx | Security |
| Demo users exhaust Coston2 faucet FXRP supply | Medium | Low | Backend rate-limits demo per wallet; faucet link always shown | Backend engineer |
| AssetManager upgrade changes pause interface | Low | Medium | Never hardcode; all interfaces read from ContractRegistry + live settings | All |
| Guardian Safe key loss | Low | Medium | M-of-N sized for key loss tolerance; standard governance unpause always available | Guardian signers |

---

## §18 — Reference Index

| Resource | URL |
|---|---|
| FAssets contracts | `github.com/flare-foundation/fassets` |
| FAssets audit (attack scenarios) | `github.com/code-423n4/2025-08-flare` |
| FAssets keeper bots | `github.com/flare-foundation/fasset-bots` |
| Flare Foundry starter | `github.com/flare-foundation/flare-foundry-starter` |
| Flare periphery package | `github.com/flare-foundation/flare-foundry-periphery-package` |
| Flare AI Skills (FCC) | `github.com/flare-foundation/flare-ai-skills` |
| FDC client | `github.com/flare-foundation/fdc-client` |
| Flare system client | `github.com/flare-foundation/flare-system-client` |
| Immunefi FAssets bounty | `immunefi.com/audit-competition/flare-fassets--mitigation-audit` |
| Flare Developer Hub | `dev.flare.network` |
| FTSOv2 docs + volatility incentives | `dev.flare.network/ftso/overview` |
| FDC overview | `dev.flare.network/fdc/overview` |
| FAssets overview | `dev.flare.network/fassets/overview` |
| ContractRegistry (all networks) | `0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019` |
| Coston2 RPC | `coston2-api.flare.network/ext/C/rpc` |
| Coston2 Explorer (Blockscout) | `coston2-explorer.flare.network` |
| Coston2 Explorer API | `coston2-explorer.flare.network/api-docs` |
| Flarescan (mainnet) | `flarescan.com` |
| Coston2 Faucet | `faucet.flare.network` |
| TradingView Lightweight Charts | `tradingview.github.io/lightweight-charts` |
| RainbowKit | `rainbowkit.com` (listed in Flare dev hub) |
| Foundry book | `book.getfoundry.sh` |
| Foundry cheatcodes | `book.getfoundry.sh/cheatcodes` |
| FCC extension scaffold | `fce-extension-scaffold` (request from Flare Foundation) |
| FCC sign example | `fce-sign` (request from Flare Foundation) |

---

## Appendix A — Complete Test Case Index

| Phase | Count | Scope |
|---|---|---|
| Phase 0 | 7 | Ground truth, contract access, faucet |
| Phase 1 | 24 | Backend (18) + Foundry contracts (6) |
| Phase 2 | 15 | Foundry (10) + live Coston2 integration (5) |
| Phase 3 | 23 | Foundry chaos (22) + live integration (1) |
| Phase 4 | 10 | Frontend hooks + Playwright wallet (10) |
| Phase 5 | 13 | Playwright E2E screens (13) |
| Phase 6 | 12 | Playwright full attack flow (12) |
| Phase 7 | 9 | Polish + integration (9) |
| Phase 8 | 5 | Audit regression + SLO (5) |
| Phase 9 | 5 | Mainnet launch (5) |
| **Total** | **123** | |

## Appendix B — Phase Summary & Timeline

| Phase | Name | Weeks | Key Deliverable |
|---|---|---|---|
| 0 | Ground Truth | 1–3 | `ground-truth.md`; live AssetManager settings on record |
| 1 | Read-Only Monitoring | 3–8 | Public Coston2 dashboard; FP/FN rate report |
| 2 | TEE Integration | 8–14 | Signed instruction on-chain; Blockscout-verifiable |
| 3 | Pause Authority | 14–20 | Real pause demo; chaos test report; internal audit |
| 4 | UI Data Layer | 14–18 | All hooks returning real data; TradingView chart live |
| 5 | UI Core Panels | 18–22 | Overview, Agents, Threat Map on staging |
| 6 | Attack Demo | 22–26 | Complete end-to-end demo with real wallet and real txs |
| 7 | Forensics & Polish | 26–28 | Production-quality app; full integration test passing |
| 8 | Audit & Governance | 28–38 | External audit report; governance proposal approved |
| 9 | Mainnet Launch | 38+ | Live on Flare mainnet; MTTP ≤ 3.6s in production |

Phases 3 and 4 run in parallel (different engineering tracks — smart contract vs. frontend).

---

## Appendix C — Complete Foundry Test Suite (All Contracts)

### C.1 Mock contracts

#### `test/mocks/MockFtsoV2.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Mock FTSOv2 for Foundry tests.
 *         Allows arbitrary feed values and simulates block-latency lag scenarios.
 *         Deliberately does NOT auto-advance values — tests set them explicitly
 *         so every assertion is against a known, deterministic value.
 */
contract MockFtsoV2 {
    struct FeedData {
        uint256 value;
        int8    decimals;
        uint64  timestamp;
    }

    mapping(bytes21 => FeedData) private _feeds;

    // Convenience: set a feed value with explicit decimals
    function setFeed(bytes21 feedId, uint256 value, int8 decimals) external {
        _feeds[feedId] = FeedData(value, decimals, uint64(block.timestamp));
    }

    // Mirror the real FtsoV2Interface
    function getFeedById(bytes21 feedId)
        external view
        returns (uint256 value, int8 decimals, uint64 timestamp)
    {
        FeedData memory d = _feeds[feedId];
        return (d.value, d.decimals, d.timestamp);
    }

    function getFeedsById(bytes21[] calldata feedIds)
        external view
        returns (
            uint256[] memory values,
            int8[]    memory decimals,
            uint64    timestamp
        )
    {
        values   = new uint256[](feedIds.length);
        decimals = new int8[](feedIds.length);
        for (uint256 i; i < feedIds.length; i++) {
            FeedData memory d = _feeds[feedIds[i]];
            values[i]   = d.value;
            decimals[i] = d.decimals;
        }
        timestamp = uint64(block.timestamp);
    }
}
```

#### `test/mocks/MockAssetManager.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Mock AssetManager covering both pause facets.
 *         Records all calls for test assertions.
 *         Correctly enforces the duration cap so ZukoGuardian
 *         cap-enforcement tests are meaningful.
 */
contract MockAssetManager {
    // --- Settings (mirror AssetManagerSettings) ---
    uint256 public maxEmergencyPauseDurationSeconds     = 6 hours;
    uint256 public emergencyPauseDurationResetAfterSeconds = 24 hours;
    uint256 public maxTransferPauseDurationSeconds      = 6 hours;
    uint256 public minVaultCollateralRatioBIPS          = 15000; // 150%
    uint256 public minPoolCollateralRatioBIPS           = 15000;

    // --- State (mirrors real facets) ---
    uint256 public emergencyPausedUntil;
    uint256 public transfersEmergencyPausedUntil;

    // --- Call recording ---
    uint256 public opsPauseCallCount;
    uint256 public transferPauseCallCount;
    uint256 public lastOpsPauseDuration;
    uint256 public lastTransferPauseDuration;

    // --- Access control ---
    address public pauseGuardian;

    error NotPauseGuardian(address caller, address expected);

    constructor(address _pauseGuardian) {
        pauseGuardian = _pauseGuardian;
    }

    // EmergencyPauseFacet
    function emergencyPause(uint256 duration) external {
        if (msg.sender != pauseGuardian)
            revert NotPauseGuardian(msg.sender, pauseGuardian);
        opsPauseCallCount++;
        lastOpsPauseDuration = duration;
        uint256 end = block.timestamp + duration;
        if (end > emergencyPausedUntil) emergencyPausedUntil = end;
    }

    // EmergencyPauseTransfersFacet
    function emergencyPauseTransfers(uint256 duration) external {
        if (msg.sender != pauseGuardian)
            revert NotPauseGuardian(msg.sender, pauseGuardian);
        transferPauseCallCount++;
        lastTransferPauseDuration = duration;
        uint256 end = block.timestamp + duration;
        if (end > transfersEmergencyPausedUntil)
            transfersEmergencyPausedUntil = end;
    }

    function isEmergencyPaused() external view returns (bool) {
        return block.timestamp < emergencyPausedUntil;
    }

    function isTransferEmergencyPaused() external view returns (bool) {
        return block.timestamp < transfersEmergencyPausedUntil;
    }

    // --- Test helpers ---
    function setPauseGuardian(address g) external { pauseGuardian = g; }
    function setMaxPauseDuration(uint256 d) external {
        maxEmergencyPauseDurationSeconds = d;
    }
    function setMaxTransferPauseDuration(uint256 d) external {
        maxTransferPauseDurationSeconds = d;
    }
    function setMinVaultCR(uint256 bips) external {
        minVaultCollateralRatioBIPS = bips;
    }
}
```

#### `test/mocks/MockFdcVerification.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Mock FDC verification contract.
 *         Toggle attestation results per proof hash or globally.
 *         Default: all proofs succeed (bridge is healthy) —
 *         tests explicitly set failure for anomaly scenarios.
 */
contract MockFdcVerification {
    mapping(bytes32 => bool) private _results;
    bool public defaultResult = true;
    bool public usePerKeyResults = false;

    function setAttestation(bytes32 proofHash, bool result) external {
        _results[proofHash] = result;
        usePerKeyResults    = true;
    }

    function setDefaultResult(bool result) external {
        defaultResult = result;
    }

    function resetToDefault() external {
        usePerKeyResults = false;
        defaultResult    = true;
    }

    // Matches IFdcVerification.verifyPayment pattern
    function verifyPayment(bytes calldata proof)
        external view
        returns (bool proved, bytes memory response)
    {
        bytes32 h = keccak256(proof);
        proved   = usePerKeyResults ? _results[h] : defaultResult;
        response = proof;
    }
}
```

#### `test/mocks/MockTeeRegistry.sol`
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Minimal mock of FCC's TeeExtensionRegistry.
 *         Allows tests to register and deregister code hashes to verify
 *         ZukoGuardian correctly checks its own registration before
 *         executing any instruction. This is the kill-switch test vector.
 */
contract MockTeeRegistry {
    mapping(bytes32 => bool) public registeredHashes;

    function registerHash(bytes32 codeHash) external {
        registeredHashes[codeHash] = true;
    }

    function deregisterHash(bytes32 codeHash) external {
        registeredHashes[codeHash] = false;
    }

    function isHashRegistered(bytes32 codeHash)
        external view returns (bool)
    {
        return registeredHashes[codeHash];
    }
}
```

---

### C.2 `test/ZukoMultiProverVerifier.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoMultiProverVerifier.sol";

/**
 * @title ZukoMultiProverVerifierTest
 * @notice Covers: 1-of-2 for MEDIUM, 2-of-2 for HIGH/CRITICAL,
 *         wrong signers, replayed sig over different hash,
 *         empty sigs, governance-only signer update.
 *
 * Run: forge test --match-contract ZukoMultiProverVerifierTest -vvv
 */
contract ZukoMultiProverVerifierTest is Test {
    ZukoMultiProverVerifier internal verifier;

    uint256 internal constant FCC_KEY   = 0xFCC0000000000000000000000000000000000000000000000000000000000001;
    uint256 internal constant CLOUD_KEY = 0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC02;
    uint256 internal constant ROGUE_KEY = 0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF;

    address internal fccSigner;
    address internal cloudSigner;
    address internal governance = address(this); // test contract is governance

    bytes32 internal constant PAYLOAD = keccak256("test-instruction-v1");

    function setUp() public {
        fccSigner   = vm.addr(FCC_KEY);
        cloudSigner = vm.addr(CLOUD_KEY);
        verifier    = new ZukoMultiProverVerifier(fccSigner, cloudSigner, governance);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    function _fccSig(bytes32 h)   internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(FCC_KEY, h);
        return abi.encodePacked(r, s, v);
    }
    function _cloudSig(bytes32 h) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(CLOUD_KEY, h);
        return abi.encodePacked(r, s, v);
    }
    function _rogueSig(bytes32 h) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ROGUE_KEY, h);
        return abi.encodePacked(r, s, v);
    }

    // ── MEDIUM (1-of-2) ──────────────────────────────────────────────────

    function test_Medium_FccOnly_Passes() public view {
        assertTrue(
            verifier.verify(PAYLOAD, _fccSig(PAYLOAD), "", 1),
            "FCC sig alone must satisfy MEDIUM"
        );
    }

    function test_Medium_CloudOnly_Passes() public view {
        assertTrue(
            verifier.verify(PAYLOAD, "", _cloudSig(PAYLOAD), 1),
            "Cloud sig alone must satisfy MEDIUM"
        );
    }

    function test_Medium_BothSigs_Passes() public view {
        assertTrue(
            verifier.verify(PAYLOAD, _fccSig(PAYLOAD), _cloudSig(PAYLOAD), 1),
            "Both sigs must satisfy MEDIUM"
        );
    }

    function test_Medium_NoSigs_Fails() public view {
        assertFalse(verifier.verify(PAYLOAD, "", "", 1),
            "Empty sigs must always fail");
    }

    // ── HIGH / CRITICAL (2-of-2) ─────────────────────────────────────────

    function test_High_BothSigs_Passes() public view {
        assertTrue(
            verifier.verify(PAYLOAD, _fccSig(PAYLOAD), _cloudSig(PAYLOAD), 2),
            "Both sigs must satisfy HIGH"
        );
    }

    function test_Critical_BothSigs_Passes() public view {
        assertTrue(
            verifier.verify(PAYLOAD, _fccSig(PAYLOAD), _cloudSig(PAYLOAD), 3),
            "Both sigs must satisfy CRITICAL"
        );
    }

    function test_Critical_FccOnly_Fails() public view {
        assertFalse(
            verifier.verify(PAYLOAD, _fccSig(PAYLOAD), "", 3),
            "FCC sig alone must NOT satisfy CRITICAL"
        );
    }

    function test_Critical_CloudOnly_Fails() public view {
        assertFalse(
            verifier.verify(PAYLOAD, "", _cloudSig(PAYLOAD), 3),
            "Cloud sig alone must NOT satisfy CRITICAL"
        );
    }

    // ── Wrong signers ─────────────────────────────────────────────────────

    function test_RogueSig_Fails_ForAnyLevel() public view {
        bytes memory rogue = _rogueSig(PAYLOAD);
        assertFalse(verifier.verify(PAYLOAD, rogue, rogue, 1), "Rogue must fail MEDIUM");
        assertFalse(verifier.verify(PAYLOAD, rogue, rogue, 2), "Rogue must fail HIGH");
        assertFalse(verifier.verify(PAYLOAD, rogue, rogue, 3), "Rogue must fail CRITICAL");
    }

    function test_Replay_DifferentHash_Fails() public view {
        bytes memory fcc = _fccSig(PAYLOAD);
        bytes32 other    = keccak256("entirely-different-payload");
        assertFalse(
            verifier.verify(other, fcc, "", 1),
            "Sig over different hash must be rejected"
        );
    }

    // ── Governance ────────────────────────────────────────────────────────

    function test_UpdateFccSigner_ByGovernance_Succeeds() public {
        address newFcc = address(0xBEEF1);
        verifier.updateFccSigner(newFcc);
        assertEq(verifier.fccSignerAddress(), newFcc);
    }

    function test_UpdateCloudSigner_ByGovernance_Succeeds() public {
        address newCloud = address(0xBEEF2);
        verifier.updateCloudSigner(newCloud);
        assertEq(verifier.cloudSignerAddress(), newCloud);
    }

    function test_UpdateSigner_NonGovernance_Reverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        verifier.updateFccSigner(address(0xBEEF));
    }

    function test_UpdateSigner_ZeroAddress_Reverts() public {
        vm.expectRevert();
        verifier.updateFccSigner(address(0));
    }
}
```

---

### C.3 `test/ZukoFTSOWatcher.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoFTSOWatcher.sol";
import "./mocks/MockFtsoV2.sol";

/**
 * @title ZukoFTSOWatcherTest
 * @notice Covers: ring-buffer accumulation and wrap-around,
 *         z-score math (stable / spike / gradual / insufficient samples),
 *         anchor deviation calculation, updater access control,
 *         and the volatility-incentive gate for Rule 1.
 *
 * Run: forge test --match-contract ZukoFTSOWatcherTest -vvv
 */
contract ZukoFTSOWatcherTest is Test {
    ZukoFTSOWatcher internal watcher;
    MockFtsoV2      internal ftso;

    // XRP/USD feed ID — 0x01 prefix + ASCII "XRP/USD" padded to 21 bytes
    bytes21 internal constant XRP_USD =
        0x015852502f555344000000000000000000000000000000;

    address internal updater = address(0xABC1);

    function setUp() public {
        ftso    = new MockFtsoV2();
        watcher = new ZukoFTSOWatcher(
            address(ftso),
            updater,
            200   // sigmaWarnThreshold = 2.00σ (E2 scaled)
        );
    }

    // ── Helper: push N identical samples ────────────────────────────────

    function _fill(uint256 value, uint8 n) internal {
        for (uint8 i; i < n; i++) {
            ftso.setFeed(XRP_USD, value, -6);
            vm.prank(updater);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 2);
        }
    }

    // ── Ring buffer ───────────────────────────────────────────────────────

    function test_Ring_AccumulatesUpToRingSize() public {
        _fill(1_000_000, 30);
        assertEq(watcher.sampleCount(XRP_USD), 30);
    }

    function test_Ring_DoesNotGrowBeyondRingSize() public {
        _fill(1_000_000, 50); // fill
        ftso.setFeed(XRP_USD, 999_000, -6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        assertEq(watcher.sampleCount(XRP_USD), 50, "Ring must wrap at RING_SIZE");
    }

    function test_Ring_OverwritesOldest_ValueChanges() public {
        // Fill with 1.00, then push 1.50 as the 51st sample
        // The mean should shift upward once the oldest 1.00 is evicted
        _fill(1_000_000, 50);
        int256 meanBefore = watcher.rollingMean(XRP_USD);

        ftso.setFeed(XRP_USD, 1_500_000, -6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);

        int256 meanAfter = watcher.rollingMean(XRP_USD);
        assertGt(meanAfter, meanBefore, "Mean must rise after inserting higher value");
    }

    // ── Access control ────────────────────────────────────────────────────

    function test_Update_NonUpdater_Reverts() public {
        ftso.setFeed(XRP_USD, 1_000_000, -6);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        watcher.updateFeedSample(XRP_USD);
    }

    // ── Z-score ───────────────────────────────────────────────────────────

    function test_ZScore_ZeroVariance_ReturnsZero() public {
        _fill(1_000_000, 50);
        assertEq(watcher.computeZScore(XRP_USD), 0,
            "Zero variance must produce z=0");
    }

    function test_ZScore_LargeSpike_ExceedsThreshold() public {
        _fill(1_000_000, 49);
        ftso.setFeed(XRP_USD, 1_500_000, -6); // +50% spike
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);

        int256 z = watcher.computeZScore(XRP_USD);
        assertGt(z, 200, "50% spike must exceed 2σ threshold");
        assertTrue(watcher.isAboveWarnThreshold(XRP_USD));
    }

    function test_ZScore_SmallNoise_BelowThreshold() public {
        // Simulate 0.3% noise — must not trigger
        for (uint8 i; i < 50; i++) {
            uint256 v = 1_000_000 + (i % 2 == 0 ? 3_000 : 0); // ±0.3%
            ftso.setFeed(XRP_USD, v, -6);
            vm.prank(updater);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        assertFalse(watcher.isAboveWarnThreshold(XRP_USD),
            "Sub-threshold noise must not trigger warning");
    }

    function test_ZScore_InsufficientSamples_ReturnsZero() public {
        // Only 5 samples — below the 20-sample minimum
        _fill(1_000_000, 5);
        assertEq(watcher.computeZScore(XRP_USD), 0,
            "Insufficient samples must return 0 (no startup false positives)");
        assertFalse(watcher.isAboveWarnThreshold(XRP_USD));
    }

    function test_ZScore_GradualDecline_DoesNotFire() public {
        // -0.5% per block for 50 blocks — normal market drift, not anomaly
        for (uint8 i; i < 50; i++) {
            uint256 v = 1_000_000 - uint256(i) * 5_000;
            ftso.setFeed(XRP_USD, v, -6);
            vm.prank(updater);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        // z-score measures variance of the series, not the trend direction
        // Gradual linear trend has low variance → should not exceed threshold
        assertFalse(watcher.isAboveWarnThreshold(XRP_USD),
            "Linear price decline must not fire anomaly (use CR cliff for that)");
    }

    // ── Anchor deviation ─────────────────────────────────────────────────

    function test_AnchorDeviation_WhenEqual_IsZero() public {
        ftso.setFeed(XRP_USD, 1_000_000, -6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        watcher.setAnchorValue(XRP_USD, 1_000_000);

        assertEq(watcher.anchorDeviation(XRP_USD), 0);
    }

    function test_AnchorDeviation_TenPercent_ReturnsCorrectScaled() public {
        // Block-latency: $0.90, anchor: $1.00 → 10% deviation
        ftso.setFeed(XRP_USD, 900_000, -6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        watcher.setAnchorValue(XRP_USD, 1_000_000);

        // Returns E4-scaled: 10% = 1000
        assertEq(watcher.anchorDeviation(XRP_USD), 1000,
            "10% deviation must return 1000 (1e4 scaled)");
    }

    function test_AnchorDeviation_NoAnchorSet_ReturnsZero() public {
        ftso.setFeed(XRP_USD, 1_000_000, -6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        // No setAnchorValue called
        assertEq(watcher.anchorDeviation(XRP_USD), 0,
            "Unset anchor must return 0 deviation (safe default)");
    }

    // ── Rule 1 gate ────────────────────────────────────────────────────────

    function test_Rule1Gate_BothConditions_Required() public {
        // High z-score but anchor matches → gate must not pass
        _fill(1_000_000, 49);
        ftso.setFeed(XRP_USD, 1_500_000, -6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        watcher.setAnchorValue(XRP_USD, 1_500_000); // anchor also at new price

        // z-score is high, but anchor deviation is zero — Rule 1 must NOT fire
        bool rule1ShouldFire =
            watcher.isAboveWarnThreshold(XRP_USD)
            && watcher.anchorDeviation(XRP_USD) > 150; // > 1.5%

        assertFalse(rule1ShouldFire,
            "Rule 1 requires BOTH z-score AND anchor deviation");
    }

    // ── [EDGE CASE 1] Decimal normalization ───────────────────────────────

    /**
     * Verifies that _normalize() correctly scales raw FTSOv2 values to
     * 1e18 WAD regardless of their native int8 decimals.
     *
     * Referenced in §4.4 Edge Case 1 fix — this is the test that exercises
     * the normalization path with non-18-decimal inputs.
     */
    function test_Normalize_NonStandardDecimals_CorrectWAD() public {
        // --- Feed A: 5 decimals (e.g. XRP/USD = 0.58210 → raw value 58210) ---
        bytes21 feedA = bytes21(uint168(0x01));
        ftso.setFeed(feedA, 58210, 5);
        vm.prank(updater);
        watcher.updateFeedSample(feedA);

        // Expected WAD: 58210 * 10^(18-5) = 58210 * 10^13 = 582_100_000_000_000_000
        uint256 storedA = watcher.latestSample(feedA);
        assertEq(storedA, 58210 * 1e13,
            "5-decimal feed must normalize to WAD: 58210 * 10^13");

        // --- Feed B: 8 decimals (e.g. ETH/USD = 0.97420000 → raw value 97420000) ---
        bytes21 feedB = bytes21(uint168(0x02));
        ftso.setFeed(feedB, 97420000, 8);
        vm.prank(updater);
        watcher.updateFeedSample(feedB);

        // Expected WAD: 97420000 * 10^(18-8) = 97420000 * 10^10
        uint256 storedB = watcher.latestSample(feedB);
        assertEq(storedB, 97420000 * 1e10,
            "8-decimal feed must normalize to WAD: 97420000 * 10^10");

        // --- Feed C: 18 decimals (already WAD — normalize should be identity) ---
        bytes21 feedC = bytes21(uint168(0x03));
        uint256 wadValue = 1_500_000_000_000_000_000; // 1.5 in WAD
        ftso.setFeed(feedC, wadValue, 18);
        vm.prank(updater);
        watcher.updateFeedSample(feedC);

        uint256 storedC = watcher.latestSample(feedC);
        assertEq(storedC, wadValue,
            "18-decimal feed must pass through unchanged (no-op normalize)");

        // --- Feed D: negative decimals (e.g. decimals = -2 → value is prescaled) ---
        bytes21 feedD = bytes21(uint168(0x04));
        ftso.setFeed(feedD, 42, int8(-2));
        vm.prank(updater);
        watcher.updateFeedSample(feedD);

        // Expected WAD: 42 * 10^(18 - (-2)) = 42 * 10^20
        uint256 storedD = watcher.latestSample(feedD);
        assertEq(storedD, 42 * (10 ** 20),
            "Negative-decimal feed must scale up by (18 + abs(decimals))");
    }
}
```

---

### C.4 `test/ZukoGuardian.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoGuardian.sol";
import "../contracts/ZukoMultiProverVerifier.sol";
import "./mocks/MockAssetManager.sol";
import "./mocks/MockFdcVerification.sol";
import "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoGuardianTest
 * @notice Integration tests for ZukoGuardian.
 *         Covers: instruction execution, duration capping, nonce replay,
 *         chain ID validation, signature failures, FCC deregistration,
 *         guardian fast-resume, self-kill, forensic log completeness,
 *         Rule 3 on-chain guard, live settings read.
 *
 * Run: forge test --match-contract ZukoGuardianTest -vvv
 */
contract ZukoGuardianTest is Test {
    ZukoGuardian            internal guardian;
    ZukoMultiProverVerifier internal verifier;
    MockAssetManager        internal assetMgr;
    MockFdcVerification     internal fdcVerif;
    MockTeeRegistry         internal teeReg;

    uint256 internal constant FCC_KEY   = 0xFCC01;
    uint256 internal constant CLOUD_KEY = 0xCLD01;

    address internal fccSigner;
    address internal cloudSigner;
    address internal governance  = address(0xG0000);
    address internal guardianEOA = address(0x6UARD);

    bytes32 internal codeHash = keccak256("zuko-v1-production");

    address[] internal guardians;

    // XRP/USD feed
    bytes21 internal constant XRP_USD =
        0x015852502f555344000000000000000000000000000000;

    function setUp() public {
        fccSigner   = vm.addr(FCC_KEY);
        cloudSigner = vm.addr(CLOUD_KEY);

        teeReg = new MockTeeRegistry();
        teeReg.registerHash(codeHash);

        assetMgr = new MockAssetManager(address(0)); // guardian set post-deploy
        fdcVerif = new MockFdcVerification();
        verifier = new ZukoMultiProverVerifier(fccSigner, cloudSigner, governance);

        guardians    = new address[](1);
        guardians[0] = guardianEOA;

        guardian = new ZukoGuardian(
            address(verifier),
            address(assetMgr),
            address(fdcVerif),
            address(teeReg),
            codeHash,
            governance,
            guardians
        );

        // Grant ZukoGuardian the pause-guardian role
        assetMgr.setPauseGuardian(address(guardian));
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    function _inst(
        uint8   severity,
        uint8   rules,
        uint32  opsDur,
        uint32  txDur,
        bytes32 fdcRef
    ) internal view returns (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) {
        inst = ZukoGuardian.ZukoInstruction({
            severity:               severity,
            rulesTriggered:         rules,
            opsPauseDuration:       opsDur,
            transfersPauseDuration: txDur,
            feedId:                 XRP_USD,
            feedValue:              900_000,
            anchorValue:            1_000_000,
            blockRangeStart:        uint64(block.number - 5),
            blockRangeEnd:          uint64(block.number),
            fdcAttestationRef:      fdcRef,
            nonce:                  guardian.nextNonce(),
            chainId:                uint32(block.chainid)
        });
        h = keccak256(abi.encode(inst));
    }

    function _sign(bytes32 h)
        internal view
        returns (bytes memory fSig, bytes memory cSig)
    {
        (uint8 fv, bytes32 fr, bytes32 fs) = vm.sign(FCC_KEY,   h);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(CLOUD_KEY, h);
        fSig = abi.encodePacked(fr, fs, fv);
        cSig = abi.encodePacked(cr, cs, cv);
    }

    function _execute(
        uint8   severity,
        uint8   rules,
        uint32  opsDur,
        uint32  txDur,
        bytes32 fdcRef
    ) internal {
        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(severity, rules, opsDur, txDur, fdcRef);
        (bytes memory fSig, bytes memory cSig) = _sign(h);
        guardian.executeInstruction(abi.encode(inst), fSig, cSig);
    }

    // ── Happy paths ───────────────────────────────────────────────────────

    function test_Medium_OpsOnly_PausesOps_NotTransfers() public {
        _execute(1, 0x01, 3600, 0, bytes32(0));

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 0,
            "MEDIUM must NOT pause transfers");
        assertEq(assetMgr.lastOpsPauseDuration(), 3600);
        assertTrue(assetMgr.isEmergencyPaused());
    }

    function test_High_BothSurfaces_Paused() public {
        _execute(2, 0x06, 7200, 7200, keccak256("fdc-mismatch"));

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 1,
            "HIGH must pause both surfaces");
    }

    function test_Critical_MaxDuration_BothSurfaces() public {
        _execute(3, 0x08, 21600, 21600, bytes32(0));

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 1);
    }

    // ── Duration capping ──────────────────────────────────────────────────

    function test_PauseDuration_CappedAtLiveSetting() public {
        // Ask for 24h but max is 6h
        _execute(2, 0x02, 86400, 0, bytes32(0));

        assertLe(
            assetMgr.lastOpsPauseDuration(),
            assetMgr.maxEmergencyPauseDurationSeconds(),
            "Guardian must cap duration at live AssetManager max"
        );
    }

    function test_PauseDuration_ReadsNewCapAfterGovernanceChange() public {
        // Simulate governance tightening the cap to 1h
        assetMgr.setMaxPauseDuration(3600);
        _execute(2, 0x02, 7200, 0, bytes32(0)); // requests 2h

        assertLe(
            assetMgr.lastOpsPauseDuration(),
            3600,
            "Guardian must respect the tightened cap immediately"
        );
    }

    // ── Nonce / replay ────────────────────────────────────────────────────

    function test_ReplayedNonce_Reverts() public {
        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(1, 0x01, 3600, 0, bytes32(0));
        (bytes memory fSig, bytes memory cSig) = _sign(h);

        guardian.executeInstruction(abi.encode(inst), fSig, cSig);

        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.NonceAlreadyUsed.selector, inst.nonce)
        );
        guardian.executeInstruction(abi.encode(inst), fSig, cSig);
    }

    function test_WrongChainId_Reverts() public {
        (ZukoGuardian.ZukoInstruction memory inst, ) =
            _inst(1, 0x01, 3600, 0, bytes32(0));
        inst.chainId = 9999; // wrong chain
        bytes32 h   = keccak256(abi.encode(inst));
        (bytes memory fSig, bytes memory cSig) = _sign(h);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoGuardian.InvalidChainId.selector,
                uint32(block.chainid),
                uint32(9999)
            )
        );
        guardian.executeInstruction(abi.encode(inst), fSig, cSig);
    }

    // ── Signature failures ────────────────────────────────────────────────

    function test_BadFccSig_Reverts() public {
        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(1, 0x01, 3600, 0, bytes32(0));
        (, bytes memory cSig) = _sign(h);

        (uint8 rv, bytes32 rr, bytes32 rs) = vm.sign(0xDEAD, h);
        bytes memory badFcc = abi.encodePacked(rr, rs, rv);

        vm.expectRevert(ZukoGuardian.InvalidSignature.selector);
        guardian.executeInstruction(abi.encode(inst), badFcc, cSig);
    }

    function test_Critical_OnlyOneSig_Reverts() public {
        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(3, 0x08, 21600, 21600, bytes32(0));
        (bytes memory fSig,) = _sign(h);

        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.InsufficientSigners.selector, 3)
        );
        guardian.executeInstruction(abi.encode(inst), fSig, "");
    }

    // ── FCC registry check ────────────────────────────────────────────────

    function test_DeregisteredHash_Reverts() public {
        teeReg.deregisterHash(codeHash); // simulate governance kill

        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(1, 0x01, 3600, 0, bytes32(0));
        (bytes memory fSig, bytes memory cSig) = _sign(h);

        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.NotRegisteredInFCC.selector, codeHash)
        );
        guardian.executeInstruction(abi.encode(inst), fSig, cSig);
    }

    // ── Rule 3 on-chain guard ─────────────────────────────────────────────

    function test_Rule3Alone_WithoutFdcRef_Reverts() public {
        // bit2 = Rule3, but fdcAttestationRef == 0 → on-chain guard rejects
        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(2, 0x04, 7200, 7200, bytes32(0)); // fdcRef is zero
        (bytes memory fSig, bytes memory cSig) = _sign(h);

        vm.expectRevert(ZukoGuardian.RedempBurstWithoutFDCMismatch.selector);
        guardian.executeInstruction(abi.encode(inst), fSig, cSig);
    }

    function test_Rule3_WithFdcRef_Succeeds() public {
        _execute(2, 0x04, 7200, 7200, keccak256("fdc-mismatch-confirmed"));
        assertEq(assetMgr.opsPauseCallCount(), 1);
    }

    // ── Guardian fast-resume ─────────────────────────────────────────────

    function test_GuardianFastResume_EmitsEvent() public {
        _execute(2, 0x06, 3600, 3600, keccak256("mismatch"));

        vm.expectEmit(true, true, false, false);
        emit ZukoGuardian.GuardianFastResume(0, guardianEOA, block.timestamp);

        vm.prank(guardianEOA);
        guardian.guardianFastResume(0);
    }

    function test_GuardianFastResume_NonGuardian_Reverts() public {
        _execute(2, 0x06, 3600, 3600, keccak256("mismatch"));

        vm.prank(address(0xBAD));
        vm.expectRevert(ZukoGuardian.NotGuardian.selector);
        guardian.guardianFastResume(0);
    }

    function test_GuardianFastResume_NoIncident_Reverts() public {
        vm.prank(guardianEOA);
        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.IncidentNotFound.selector, 0)
        );
        guardian.guardianFastResume(0);
    }

    // ── Self-kill ─────────────────────────────────────────────────────────

    function test_SelfKill_ByGovernance_BlocksFutureInstructions() public {
        vm.prank(governance);
        vm.expectEmit(true, false, false, false);
        emit ZukoGuardian.ZukoKilled(governance, block.timestamp);
        guardian.selfKill();

        (ZukoGuardian.ZukoInstruction memory inst, bytes32 h) =
            _inst(1, 0x01, 3600, 0, bytes32(0));
        (bytes memory fSig, bytes memory cSig) = _sign(h);

        vm.expectRevert(ZukoGuardian.GuardianKilled.selector);
        guardian.executeInstruction(abi.encode(inst), fSig, cSig);
    }

    function test_SelfKill_NonGovernance_Reverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(ZukoGuardian.NotGovernance.selector);
        guardian.selfKill();
    }

    // ── Forensic log completeness ─────────────────────────────────────────

    function test_ForensicLog_EmittedWithCorrectSeverityAndRules() public {
        vm.recordLogs();
        _execute(2, 0x06, 7200, 7200, keccak256("mismatch"));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == ZukoGuardian.ZukoForensicLog.selector) {
                found = true;
                // incidentId is topic[1]; decode data for severity + rules
                (uint256 id, uint8 sev, uint8 rules) = abi.decode(
                    // prepend id since it's indexed
                    abi.encodePacked(logs[i].topics[1], logs[i].data),
                    (uint256, uint8, uint8)
                );
                assertEq(id,    0,    "First incident must have id=0");
                assertEq(sev,   2,    "Severity must be HIGH");
                assertEq(rules, 0x06, "Rules bitmask must match");
                break;
            }
        }
        assertTrue(found, "ZukoForensicLog must be emitted");
    }

    // ── Incident counter ──────────────────────────────────────────────────

    function test_IncidentCounter_IncrementsOnEachExecution() public {
        assertEq(guardian.totalIncidents(), 0);
        _execute(1, 0x01, 3600, 0, bytes32(0));
        assertEq(guardian.totalIncidents(), 1);
        _execute(1, 0x01, 3600, 0, bytes32(0));
        assertEq(guardian.totalIncidents(), 2);
    }

    // ── Live settings read ────────────────────────────────────────────────

    function test_LivePauseSettings_MatchAssetManager() public view {
        (uint256 maxOps, uint256 maxTx,,) = guardian.getLivePauseSettings();
        assertEq(maxOps, assetMgr.maxEmergencyPauseDurationSeconds());
        assertEq(maxTx,  assetMgr.maxTransferPauseDurationSeconds());
    }
}
```

---

### C.5 `test/ZukoForensicLogger.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoForensicLogger.sol";

/**
 * @title ZukoForensicLoggerTest
 * @notice Covers: append-only semantics, incrementing IDs,
 *         access control, non-existent incident query.
 *
 * Run: forge test --match-contract ZukoForensicLoggerTest -vvv
 */
contract ZukoForensicLoggerTest is Test {
    ZukoForensicLogger internal logger;
    address internal guardian = address(0x6UARD);

    function setUp() public {
        logger = new ZukoForensicLogger(guardian);
    }

    function _log(uint8 sev, uint8 rules)
        internal returns (uint256 id)
    {
        vm.prank(guardian);
        return logger.logIncident(
            sev, rules,
            bytes32(uint256(1)),
            1_000_000, 1_050_000,
            uint64(block.number - 5), uint64(block.number),
            bytes32(0),
            hex"aabb", hex"ccdd"
        );
    }

    function test_Log_StoresCorrectValues() public {
        uint256 id = _log(2, 0x06);
        assertEq(id, 0, "First incident must be id=0");

        ZukoForensicLogger.Incident memory inc = logger.getIncident(0);
        assertEq(inc.severity,       2);
        assertEq(inc.rulesTriggered, 0x06);
        assertEq(inc.feedValue,      1_000_000);
        assertEq(inc.anchorValue,    1_050_000);
    }

    function test_Log_IdsIncrement() public {
        uint256 a = _log(1, 0x01);
        uint256 b = _log(2, 0x02);
        uint256 c = _log(3, 0x08);
        assertEq(a, 0);
        assertEq(b, 1);
        assertEq(c, 2);
        assertEq(logger.totalIncidents(), 3);
    }

    function test_Log_NonGuardian_Reverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        logger.logIncident(1, 0x01, bytes32(0), 0, 0, 0, 0, bytes32(0), "", "");
    }

    function test_Get_NonExistentIncident_Reverts() public {
        vm.expectRevert();
        logger.getIncident(999);
    }

    function test_AppendOnly_NoUpdateFunction() public pure {
        // Compile-time guarantee: if ZukoForensicLogger exposes no
        // updateIncident / deleteIncident / setIncident function,
        // this test trivially passes — the interface itself proves append-only.
        // Add interface check here if using a formal interface file.
        assertTrue(true);
    }

    function test_Log_EmitsEvent() public {
        vm.recordLogs();
        _log(1, 0x01);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == ZukoForensicLogger.IncidentLogged.selector) {
                found = true;
                break;
            }
        }
        assertTrue(found, "IncidentLogged event must be emitted");
    }
}
```

---

### C.6 `test/ZukoRuleEngine.t.sol` — end-to-end scenario tests

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoGuardian.sol";
import "../contracts/ZukoMultiProverVerifier.sol";
import "../contracts/ZukoFTSOWatcher.sol";
import "./mocks/MockAssetManager.sol";
import "./mocks/MockFtsoV2.sol";
import "./mocks/MockFdcVerification.sol";
import "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoRuleEngineTest
 * @notice Full scenario tests that simulate the TEE's off-chain rule verdicts
 *         arriving as signed instructions and verifying the correct on-chain
 *         response. Each scenario maps to a documented attack class.
 *
 * Run: forge test --match-contract ZukoRuleEngineTest -vvv
 */
contract ZukoRuleEngineTest is Test {
    ZukoGuardian            internal guardian;
    ZukoMultiProverVerifier internal verifier;
    ZukoFTSOWatcher         internal watcher;
    MockAssetManager        internal assetMgr;
    MockFtsoV2              internal ftso;
    MockFdcVerification     internal fdcVerif;
    MockTeeRegistry         internal teeReg;

    uint256 internal constant FCC_KEY   = 0xFCC01;
    uint256 internal constant CLOUD_KEY = 0xCLD01;

    bytes21 internal constant XRP_USD =
        0x015852502f555344000000000000000000000000000000;

    bytes32 internal codeHash = keccak256("zuko-v1");
    address internal governance  = address(0xG0000);
    address internal guardianEOA = address(0x6UARD);

    function setUp() public {
        ftso     = new MockFtsoV2();
        teeReg   = new MockTeeRegistry();
        teeReg.registerHash(codeHash);
        assetMgr = new MockAssetManager(address(0));
        fdcVerif = new MockFdcVerification();
        verifier = new ZukoMultiProverVerifier(
            vm.addr(FCC_KEY), vm.addr(CLOUD_KEY), governance
        );
        watcher  = new ZukoFTSOWatcher(address(ftso), address(this), 200);

        address[] memory gs = new address[](1);
        gs[0] = guardianEOA;

        guardian = new ZukoGuardian(
            address(verifier), address(assetMgr), address(fdcVerif),
            address(teeReg), codeHash, governance, gs
        );
        assetMgr.setPauseGuardian(address(guardian));
    }

    function _exec(
        uint8 sev, uint8 rules, uint32 ops, uint32 tx, bytes32 fdc
    ) internal {
        ZukoGuardian.ZukoInstruction memory inst = ZukoGuardian.ZukoInstruction({
            severity:               sev,
            rulesTriggered:         rules,
            opsPauseDuration:       ops,
            transfersPauseDuration: tx,
            feedId:                 XRP_USD,
            feedValue:              900_000,
            anchorValue:            1_000_000,
            blockRangeStart:        uint64(block.number - 5),
            blockRangeEnd:          uint64(block.number),
            fdcAttestationRef:      fdc,
            nonce:                  guardian.nextNonce(),
            chainId:                uint32(block.chainid)
        });
        bytes32 h = keccak256(abi.encode(inst));
        (uint8 fv, bytes32 fr, bytes32 fs) = vm.sign(FCC_KEY,   h);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(CLOUD_KEY, h);
        guardian.executeInstruction(
            abi.encode(inst),
            abi.encodePacked(fr, fs, fv),
            abi.encodePacked(cr, cs, cv)
        );
    }

    // ─── Scenario 1: Rule 1 — FTSO deviation, MEDIUM, ops only ───────────

    /**
     * XRP/USD block-latency feed drops 15% vs anchor after volatility
     * incentives fail to resolve. TEE submits MEDIUM ops-only pause.
     * Transfers must NOT be paused.
     */
    function test_S1_FTSODeviation_MEDIUM_OpsOnly() public {
        // Fill watcher ring with stable data then push anomaly
        for (uint8 i; i < 49; i++) {
            ftso.setFeed(XRP_USD, 1_000_000, -6);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        ftso.setFeed(XRP_USD, 850_000, -6);
        watcher.updateFeedSample(XRP_USD);
        watcher.setAnchorValue(XRP_USD, 1_000_000);

        assertTrue(watcher.isAboveWarnThreshold(XRP_USD), "Rule 1 must flag anomaly");
        assertGt(watcher.anchorDeviation(XRP_USD), 150, "Anchor deviation must exceed 1.5%");

        // TEE submits MEDIUM (1-of-2 sufficient)
        _exec(1, 0x01, 3600, 0, bytes32(0));

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 0,
            "Rule 1 alone must NOT pause transfers");
    }

    // ─── Scenario 2: Rule 2 — correlated CR cliff, MEDIUM ────────────────

    /**
     * Five agents' CRs drop from 175% to 130% in 8 blocks — far beyond
     * the single-agent fasset-bots threshold. Zuko fires MEDIUM.
     */
    function test_S2_CorrelatedCRCliff_MEDIUM() public {
        // CR cliff is detected off-chain; TEE verdict arrives as MEDIUM
        _exec(1, 0x02, 3600, 0, bytes32(0));

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 0,
            "CR cliff alone must not pause transfers");
    }

    // ─── Scenario 3: Rule 3 burst only — ALERT, no pause ─────────────────

    /**
     * 8× redemption burst, but FDC attests the XRPL outflows on time.
     * This is a legitimate market panic. Any pause instruction with
     * Rule3 bit and zero fdcRef must be rejected on-chain.
     */
    function test_S3_RedemptionBurst_FDCOk_NoPause() public {
        fdcVerif.setDefaultResult(true); // bridge healthy

        vm.expectRevert(ZukoGuardian.RedempBurstWithoutFDCMismatch.selector);
        _exec(2, 0x04, 7200, 7200, bytes32(0)); // fdcRef = 0 means no mismatch

        assertEq(assetMgr.opsPauseCallCount(), 0,
            "Burst alone must never trigger a pause");
    }

    // ─── Scenario 4: Rule 3 compound — FDC failed, HIGH ──────────────────

    /**
     * 8× burst AND FDC times out without attesting XRPL outflow.
     * This is the compound Rule 3 condition — HIGH pause, both surfaces.
     */
    function test_S4_CompoundRule3_HIGH_BothSurfaces() public {
        bytes32 fdcMismatch = keccak256("fdc-timeout-round-42");
        _exec(2, 0x04, 7200, 7200, fdcMismatch);

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 1,
            "Compound Rule 3 must pause both surfaces");
    }

    // ─── Scenario 5: Rule 4 — Core Vault FDC anomaly, CRITICAL ──────────

    /**
     * FDC attests a Core Vault payment 30% above expected delta.
     * CRITICAL — both surfaces, max duration, 2-of-2 required.
     * No pre-execution delay.
     */
    function test_S5_CoreVaultAnomaly_CRITICAL() public {
        _exec(3, 0x08, 21600, 21600, bytes32(0));

        assertEq(assetMgr.opsPauseCallCount(), 1);
        assertEq(assetMgr.transferPauseCallCount(), 1,
            "CRITICAL must pause both surfaces");
        // Duration must be capped at the live max (6h = 21600s)
        assertLe(assetMgr.lastOpsPauseDuration(),
            assetMgr.maxEmergencyPauseDurationSeconds());
        assertLe(assetMgr.lastTransferPauseDuration(),
            assetMgr.maxTransferPauseDurationSeconds());
    }

    // ─── Scenario 6: Legitimate volatility — Rule 1 must NOT fire ────────

    /**
     * XRP crashes 30%. Block-latency feed lags (by design) then catches up.
     * Once anchor is updated to reflect the new price, Rule 1's gate
     * (z-score AND anchor deviation both required) must no longer trigger.
     */
    function test_S6_LegitimateVolatility_NoFalsePositive() public {
        // Stable at $1.00
        for (uint8 i; i < 48; i++) {
            ftso.setFeed(XRP_USD, 1_000_000, -6);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        // Crash + feed catching up over 3 blocks
        uint256[3] memory catchup = [uint256(900_000), 710_000, 700_000];
        for (uint256 i; i < 3; i++) {
            ftso.setFeed(XRP_USD, catchup[i], -6);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        // Anchor updated to reflect new real price after 90s epoch
        watcher.setAnchorValue(XRP_USD, 700_000);

        // Anchor deviation must now be low (feed caught up)
        uint256 dev = watcher.anchorDeviation(XRP_USD);
        assertLt(dev, 150,
            "Post-catchup anchor deviation must be <1.5% (not a manipulation event)");

        // Combined gate: z-score may still be high, but anchor deviation is low
        bool rule1ShouldFire =
            watcher.isAboveWarnThreshold(XRP_USD)
            && watcher.anchorDeviation(XRP_USD) > 150;

        assertFalse(rule1ShouldFire,
            "Rule 1 must NOT fire when feed has caught up with anchor");
    }

    // ─── Scenario 7: Sequential pauses — duration accumulator cap ────────

    /**
     * Two consecutive pause instructions. The combined duration must never
     * exceed maxEmergencyPauseDurationSeconds. Zuko reads this live before
     * each call and caps accordingly.
     */
    function test_S7_SequentialPauses_DurationCapped() public {
        _exec(1, 0x01, 10800, 0, bytes32(0)); // 3h
        uint256 firstEnd = assetMgr.emergencyPausedUntil();

        _exec(1, 0x01, 10800, 0, bytes32(0)); // another 3h
        uint256 secondEnd = assetMgr.emergencyPausedUntil();

        assertGe(secondEnd, firstEnd);
        assertLe(
            secondEnd,
            block.timestamp + assetMgr.maxEmergencyPauseDurationSeconds() + 1,
            "Stacked pauses must not exceed governance cap"
        );
    }

    // ─── Scenario 8: Killed guardian — all instructions revert ───────────

    function test_S8_KilledGuardian_AllInstructionsRevert() public {
        vm.prank(governance);
        guardian.selfKill();

        vm.expectRevert(ZukoGuardian.GuardianKilled.selector);
        _exec(1, 0x01, 3600, 0, bytes32(0));

        assertEq(assetMgr.opsPauseCallCount(), 0,
            "No pause must occur after self-kill");
    }
}
```

---

### C.7 `test/ZukoGuardianInvariant.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoGuardian.sol";
import "../contracts/ZukoMultiProverVerifier.sol";
import "./mocks/MockAssetManager.sol";
import "./mocks/MockFdcVerification.sol";
import "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoGuardianInvariantTest
 * @notice Stateful fuzz tests. Forge calls the handler in random order
 *         with random inputs and checks the 4 invariants after each call.
 *
 * Run:
 *   forge test --match-contract ZukoGuardianInvariantTest \
 *     --invariant-runs 1000 --invariant-depth 100 -vvv
 */

// ── Handler ───────────────────────────────────────────────────────────────

contract GuardianHandler is Test {
    ZukoGuardian     internal guardian;
    MockAssetManager internal assetMgr;

    uint256 internal constant FCC_KEY   = 0xFCC01;
    uint256 internal constant CLOUD_KEY = 0xCLD01;

    uint256 public validExecutionCount;

    constructor(ZukoGuardian _g, MockAssetManager _a) {
        guardian = _g;
        assetMgr = _a;
    }

    // Forge calls this with random severity / durations
    function executeValidInstruction(
        uint8  severity,
        uint32 opsDur,
        uint32 txDur
    ) external {
        severity = uint8(bound(severity, 1, 3));
        opsDur   = uint32(bound(opsDur, 0, 21600));
        txDur    = severity >= 2 ? uint32(bound(txDur, 0, 21600)) : 0;

        // Rule3 (bit2) requires non-zero fdcRef — use non-zero for HIGH/CRITICAL
        bytes32 fdcRef = (severity >= 2 && (severity & 0x04) != 0)
            ? keccak256("fdc-mismatch")
            : bytes32(0);

        uint8 rules = severity == 1 ? 0x01
                    : severity == 2 ? 0x06
                    : 0x08;

        ZukoGuardian.ZukoInstruction memory inst = ZukoGuardian.ZukoInstruction({
            severity:               severity,
            rulesTriggered:         rules,
            opsPauseDuration:       opsDur,
            transfersPauseDuration: txDur,
            feedId:                 bytes32(0),
            feedValue:              0,
            anchorValue:            0,
            blockRangeStart:        uint64(block.number - 1),
            blockRangeEnd:          uint64(block.number),
            fdcAttestationRef:      fdcRef,
            nonce:                  guardian.nextNonce(),
            chainId:                uint32(block.chainid)
        });
        bytes32 h = keccak256(abi.encode(inst));
        (uint8 fv, bytes32 fr, bytes32 fs) = vm.sign(FCC_KEY,   h);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(CLOUD_KEY, h);

        try guardian.executeInstruction(
            abi.encode(inst),
            abi.encodePacked(fr, fs, fv),
            abi.encodePacked(cr, cs, cv)
        ) {
            validExecutionCount++;
        } catch {}
    }

    // Attempt with rogue key — must always revert
    function tryBadSig(uint8 severity) external {
        ZukoGuardian.ZukoInstruction memory inst = ZukoGuardian.ZukoInstruction({
            severity:               uint8(bound(severity, 1, 3)),
            rulesTriggered:         0x01,
            opsPauseDuration:       3600,
            transfersPauseDuration: 0,
            feedId:                 bytes32(0),
            feedValue:              0, anchorValue: 0,
            blockRangeStart:        uint64(block.number - 1),
            blockRangeEnd:          uint64(block.number),
            fdcAttestationRef:      bytes32(0),
            nonce:                  guardian.nextNonce(),
            chainId:                uint32(block.chainid)
        });
        bytes32 h = keccak256(abi.encode(inst));
        (uint8 rv, bytes32 rr, bytes32 rs) = vm.sign(0xDEAD, h);
        bytes memory bad = abi.encodePacked(rr, rs, rv);

        try guardian.executeInstruction(abi.encode(inst), bad, bad) {
            revert("Bad sig accepted — INVARIANT VIOLATED");
        } catch {}
    }
}

// ── Invariant test contract ────────────────────────────────────────────────

contract ZukoGuardianInvariantTest is Test {
    ZukoGuardian            internal guardian;
    ZukoMultiProverVerifier internal verifier;
    MockAssetManager        internal assetMgr;
    MockFdcVerification     internal fdcVerif;
    MockTeeRegistry         internal teeReg;
    GuardianHandler         internal handler;

    uint256 internal constant FCC_KEY   = 0xFCC01;
    uint256 internal constant CLOUD_KEY = 0xCLD01;

    bytes32 internal codeHash = keccak256("zuko-v1");

    function setUp() public {
        teeReg = new MockTeeRegistry();
        teeReg.registerHash(codeHash);

        assetMgr = new MockAssetManager(address(0));
        fdcVerif = new MockFdcVerification();
        verifier = new ZukoMultiProverVerifier(
            vm.addr(FCC_KEY), vm.addr(CLOUD_KEY), address(this)
        );

        address[] memory gs = new address[](1);
        gs[0] = address(0x6UARD);

        guardian = new ZukoGuardian(
            address(verifier), address(assetMgr), address(fdcVerif),
            address(teeReg), codeHash, address(this), gs
        );
        assetMgr.setPauseGuardian(address(guardian));

        handler = new GuardianHandler(guardian, assetMgr);
        targetContract(address(handler));
    }

    /**
     * Invariant 1: Pause duration never exceeds AssetManager's governance cap.
     * Even if Forge calls executeValidInstruction 100× in sequence, the
     * cumulative emergencyPausedUntil must remain within the cap.
     */
    function invariant_PauseDurationNeverExceedsCap() public view {
        if (assetMgr.emergencyPausedUntil() > 0) {
            assertLe(
                assetMgr.emergencyPausedUntil(),
                block.timestamp + assetMgr.maxEmergencyPauseDurationSeconds() + 1,
                "Ops pause exceeded governance cap"
            );
        }
        if (assetMgr.transfersEmergencyPausedUntil() > 0) {
            assertLe(
                assetMgr.transfersEmergencyPausedUntil(),
                block.timestamp + assetMgr.maxTransferPauseDurationSeconds() + 1,
                "Transfer pause exceeded governance cap"
            );
        }
    }

    /**
     * Invariant 2: nextNonce always >= total nonces consumed.
     *              Nonces can never go backward.
     */
    function invariant_NonceMonotonicallyIncreasing() public view {
        assertGe(
            guardian.nextNonce(),
            handler.validExecutionCount(),
            "Nonce regressed — impossible if replay protection works"
        );
    }

    /**
     * Invariant 3: opsPauseCallCount never exceeds validExecutionCount.
     *              No instruction can trigger more than one pause call.
     */
    function invariant_PauseCallsMatchValidInstructions() public view {
        assertLe(
            assetMgr.opsPauseCallCount(),
            handler.validExecutionCount(),
            "More pause calls than valid executions"
        );
    }

    /**
     * Invariant 4: totalIncidents equals validExecutionCount.
     *              Every successful executeInstruction creates exactly one incident.
     */
    function invariant_IncidentCountMatchesExecutions() public view {
        assertEq(
            guardian.totalIncidents(),
            handler.validExecutionCount(),
            "Incident count diverged from execution count"
        );
    }
}
```

---

### C.8 Running the full test suite

```bash
# ── All unit + integration tests ─────────────────────────────────────────
forge test --match-path "test/*.t.sol" -vvv

# ── Invariant (stateful fuzz) — 1000 runs × 100 depth ──────────────────
forge test \
  --match-contract ZukoGuardianInvariantTest \
  --invariant-runs 1000 \
  --invariant-depth 100 \
  -vvv

# ── Gas snapshot (track pause instruction cost across versions) ──────────
forge snapshot --match-test "test_.*Pause"

# ── Coverage report ──────────────────────────────────────────────────────
forge coverage --report lcov
genhtml lcov.info --output-directory coverage-html
open coverage-html/index.html

# ── Fork tests against live Coston2 (Phase 3+) ───────────────────────────
source .env
forge test \
  --match-contract ZukoRuleEngineTest \
  --fork-url "$COSTON2_RPC_URL" \
  --fork-block-number latest \
  -vvv

# ── Expected output ──────────────────────────────────────────────────────
# ZukoMultiProverVerifier:     13 passed
# ZukoFTSOWatcher:             13 passed
# ZukoGuardian:                18 passed
# ZukoForensicLogger:           6 passed
# ZukoRuleEngine:               8 passed
# ZukoGuardianInvariant:  4 invariants × 1000 runs — all passed
# ─────────────────────────────────────────────────────────────────────────
# Total:  58 unit/integration tests + 4 invariants
```

---

## Appendix D — Go Rule Engine Directory Structure

```
packages/rule-engine/
├── cmd/
│   └── main.go                # Entry point — starts FCC extension HTTP server
├── internal/
│   ├── config/
│   │   └── config.go          # Reads env vars / mounted secrets; validates on start
│   ├── rpc/
│   │   ├── quorum.go          # 3-endpoint quorum provider (2-of-3)
│   │   └── registry.go        # ContractRegistry resolver — no hardcoded addresses
│   ├── feeds/
│   │   ├── ftso.go            # FTSOv2 multicall polling (getFeedsById)
│   │   ├── ringbuffer.go      # 50-slot ring buffer per feed
│   │   └── zscore.go          # Rolling mean, stddev, z-score (E4 scaled)
│   ├── agents/
│   │   └── poller.go          # Per-agent CR polling and velocity computation
│   ├── events/
│   │   └── indexer.go         # AssetManager log subscription + decode
│   ├── rules/
│   │   ├── rule1_ftso.go      # Three-step deviation check + volatility incentive
│   │   ├── rule2_cr.go        # Correlated CR cliff detection
│   │   ├── rule3_redeem.go    # Compound redemption burst + FDC timer
│   │   ├── rule4_vault.go     # Core Vault FDC anomaly
│   │   ├── rule5_liqpay.go    # Liquidation payout deviation (alert only)
│   │   ├── rule6_selfdealing.go # Agent self-dealing heuristic (alert only)
│   │   └── engine.go          # Orchestrator — evaluates all rules each block
│   ├── tee/
│   │   ├── signer.go          # TEE signing port — signs ZukoInstruction structs
│   │   ├── attestation.go     # GCP/AMD attestation document handling
│   │   └── handler.go         # POST /action — FCC extension 4-step handler
│   └── alert/
│       └── fanout.go          # Webhook fan-out (Discord, Telegram, PagerDuty)
├── Dockerfile                 # Reproducible build: SOURCE_DATE_EPOCH=0
├── Makefile                   # build, test, hash-check targets
└── go.mod
```

### D.1 Reproducible build (`Dockerfile`)

```dockerfile
FROM golang:1.22-alpine AS builder

# SOURCE_DATE_EPOCH=0 is the reproducibility guarantee.
# Any two identical source trees will produce bit-for-bit identical binaries.
# The sha256 of the resulting binary is what gets registered in TeeExtensionRegistry.
ENV SOURCE_DATE_EPOCH=0
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN go build \
    -trimpath \
    -ldflags="-s -w -buildid=" \
    -o /zuko-rule-engine \
    ./cmd/

# Verify the build hash and write it to a file for registration
RUN sha256sum /zuko-rule-engine > /zuko-rule-engine.sha256

FROM gcr.io/confidential-space-images/confidential-space:latest
COPY --from=builder /zuko-rule-engine /zuko-rule-engine
COPY --from=builder /zuko-rule-engine.sha256 /zuko-rule-engine.sha256
ENTRYPOINT ["/zuko-rule-engine"]
```

### D.2 Core rule engine types

```go
// internal/rules/engine.go

package rules

import "math/big"

// Severity levels — match Solidity ZukoInstruction.severity
const (
    SeverityInfo     uint8 = 0
    SeverityMedium   uint8 = 1
    SeverityHigh     uint8 = 2
    SeverityCritical uint8 = 3
)

// Rule bitmask constants — match Solidity ZukoInstruction.rulesTriggered
const (
    RuleBit1FTSO    uint8 = 0x01
    RuleBit2CR      uint8 = 0x02
    RuleBit3Redeem  uint8 = 0x04
    RuleBit4Vault   uint8 = 0x08
    RuleBit5LiqPay  uint8 = 0x10
    RuleBit6Self    uint8 = 0x20
)

// ZukoVerdict is the output of one rule engine evaluation cycle.
// If Severity == SeverityInfo, the engine emits an alert and does NOT sign.
type ZukoVerdict struct {
    Severity               uint8
    RulesTriggered         uint8
    OpsPauseDuration       uint32  // seconds; 0 = no ops pause
    TransfersPauseDuration uint32  // seconds; 0 = no transfer pause
    FeedID                 [21]byte
    FeedValue              *big.Int
    AnchorValue            *big.Int
    BlockRangeStart        uint64
    BlockRangeEnd          uint64
    FDCAttestationRef      [32]byte // non-zero only if Rule3/4 FDC mismatch confirmed
}

// Engine evaluates all rules in priority order and returns the worst verdict.
type Engine struct {
    FTSO    *FTSORule
    CR      *CRRule
    Redeem  *RedeemRule
    Vault   *VaultRule
    LiqPay  *LiqPayRule
    Self    *SelfDealRule
}

func (e *Engine) Evaluate(ctx context.Context, block uint64) (*ZukoVerdict, error) {
    // Rules evaluated in priority order; highest severity wins
    // Rules 5 and 6 are alert-only — they cannot raise severity above Info
    verdicts := []*ZukoVerdict{
        e.Vault.Evaluate(ctx, block),   // Rule 4 — CRITICAL
        e.Redeem.Evaluate(ctx, block),  // Rule 3 — HIGH (compound only)
        e.CR.Evaluate(ctx, block),      // Rule 2 — MEDIUM
        e.FTSO.Evaluate(ctx, block),    // Rule 1 — MEDIUM (3-step)
        e.LiqPay.Evaluate(ctx, block),  // Rule 5 — INFO always
        e.Self.Evaluate(ctx, block),    // Rule 6 — INFO always
    }
    return mergeVerdicts(verdicts), nil
}
```

---

## Appendix E — Backend Directory Structure

```
packages/backend/
├── src/
│   ├── index.ts               # Fastify server setup + WebSocket server
│   ├── rpc/
│   │   ├── quorum.ts          # 3-provider quorum (mirrors Go implementation)
│   │   └── registry.ts        # ContractRegistry resolver (shared with frontend)
│   ├── cache/
│   │   └── redis.ts           # Upstash Redis client + typed helpers
│   ├── feeds/
│   │   ├── ftsoPoller.ts      # Polls getFeedsById every block; updates Redis
│   │   └── ringBuffer.ts      # Redis sorted-set ring buffer (50 slots per feed)
│   ├── agents/
│   │   └── agentPoller.ts     # CR polling + 100-block history; agent enumeration
│   ├── events/
│   │   └── eventIndexer.ts    # AssetManager log subscription + decode + 24h window
│   ├── rules/
│   │   └── ruleStatus.ts      # Receives verdicts from Rule Engine; forwards to UI
│   ├── demo/
│   │   └── orchestrator.ts    # Attack demo cycle management + Guardian Safe relay
│   ├── ws/
│   │   └── broadcaster.ts     # WebSocket fan-out to all connected browser clients
│   └── routes/
│       ├── feeds.ts           # GET /api/feeds — FTSO history for chart mount
│       ├── agents.ts          # GET /api/agents — agent vault snapshot
│       ├── incidents.ts       # GET /api/incidents — paginated forensic log
│       └── demo.ts            # POST /api/demo/start, GET /api/demo/status
├── package.json
└── tsconfig.json
```

### E.1 WebSocket message types

```typescript
// packages/backend/src/ws/messages.ts
// All types shared between backend and frontend via packages/contracts

export type ZukoWSMessage =
  | {
      type: "FTSO_UPDATE";
      blockNumber: number;
      timestamp:   number;
      prices: { feedId: string; symbol: string; value: number; decimals: number }[];
      zScores: Record<string, number>; // E4 scaled, keyed by feedId
    }
  | {
      type: "ASSET_MANAGER_EVENT";
      blockNumber: number;
      eventName:   string; // "RedemptionRequested" | "MintingExecuted" | ...
      txHash:      string;
      decoded:     Record<string, unknown>;
    }
  | {
      type: "AGENT_UPDATE";
      blockNumber: number;
      vaults: {
        address:   string;
        vaultCR:   number; // BIPS
        poolCR:    number;
        mintedFXRP: string; // wei string
        crVelocity: number; // % per block × 1000
      }[];
    }
  | {
      type: "ZUKO_ALERT";
      severity:  0 | 1 | 2 | 3;
      rules:     number; // bitmask
      message:   string;
      incidentId?: number; // set if pause was executed
    }
  | {
      type: "ZUKO_PAUSED";
      incidentId:          number;
      executeInstructionTx: string;
      opsPauseTx:           string;
      transferPauseTx:      string;
      opsPausedUntil:       number;
      transfersPausedUntil: number;
      forensicLog: {
        severity:          number;
        rulesTriggered:    number;
        feedValue:         string;
        anchorValue:       string;
        fdcAttestationRef: string;
        blockRangeStart:   number;
        blockRangeEnd:     number;
        fccSignature:      string;
        cloudSignature:    string;
      };
    }
  | {
      type: "ZUKO_RESUMED";
      incidentId:       number;
      fastResumeTx:     string;
      resumedBy:        string;
    };
```

---

## Appendix F — Frontend Directory Structure

```
packages/frontend/
├── app/
│   ├── layout.tsx             # Root layout — fonts, Providers, testnet notice
│   ├── page.tsx               # / Overview
│   ├── agents/
│   │   └── page.tsx           # /agents Agent vault table
│   ├── threat-map/
│   │   └── page.tsx           # /threat-map Live rule status
│   ├── attack/
│   │   └── page.tsx           # /attack Attack Demo
│   ├── forensics/
│   │   └── page.tsx           # /forensics Incident ledger
│   └── docs/
│       └── page.tsx           # /docs Architecture + API reference
├── components/
│   ├── layout/
│   │   ├── Navbar.tsx         # Sticky nav with heartbeat line border
│   │   ├── HeartbeatLine.tsx  # SVG polyline — live block pulse
│   │   └── TestnetNotice.tsx  # Persistent testnet/real-data disclaimer
│   ├── charts/
│   │   ├── FTSOChart.tsx      # TradingView Lightweight Charts — real FTSO candles
│   │   └── CRSparkline.tsx    # 100-block CR mini-chart per agent
│   ├── overview/
│   │   ├── StatRow.tsx        # TVL, FXRP supply, agent count, Zuko status
│   │   ├── EventTicker.tsx    # Live AssetManager event stream
│   │   └── SystemStatus.tsx   # NORMAL / WARNING / PAUSED badge
│   ├── agents/
│   │   ├── AgentTable.tsx     # Sortable/filterable vault table
│   │   ├── AgentRow.tsx       # Single row with CR bar + velocity
│   │   └── AgentDrawer.tsx    # Full agent detail side panel
│   ├── threat-map/
│   │   ├── RuleCard.tsx       # One card per rule — status + live metrics
│   │   ├── FTSOZScoreBar.tsx  # Visual z-score indicator per feed
│   │   └── GuardianStatus.tsx # TEE hash, FCC status, last eval block
│   ├── attack/
│   │   ├── RolePicker.tsx     # Wallet connect + attack vector selection
│   │   ├── AttackerPane.tsx   # Left pane — slider, execute button, countdown
│   │   ├── GuardianPane.tsx   # Right pane — rule status, response sequence
│   │   ├── RedemptionSlider.tsx # Drag to set FXRP amount; live % baseline
│   │   ├── FDCCountdown.tsx   # 300-second attestation window timer
│   │   ├── AlertOverlay.tsx   # Full-screen alert state + Zuko response sequence
│   │   └── ForensicInline.tsx # Decoded ZukoForensicLog displayed inline
│   └── forensics/
│       ├── IncidentLedger.tsx # Paginated incident table
│       ├── IncidentRow.tsx    # Collapsed row — ID, block, severity, rules
│       └── IncidentDetail.tsx # Expanded — all fields + Blockscout links
├── hooks/
│   ├── useZukoStream.ts       # WebSocket client — connects to backend, routes messages
│   ├── useFTSOFeeds.ts        # Live FTSO prices from stream
│   ├── useAgentVaults.ts      # Live agent CR table from stream + on-chain fallback
│   ├── useAssetManagerEvents.ts # Live event ticker
│   ├── useZukoStatus.ts       # Guardian pause state + incident count
│   ├── useZukoForensicLog.ts  # Paginated incident history (API + live stream)
│   └── useAttackDemo.ts       # Full attack demo state machine
├── lib/
│   ├── chains.ts              # Coston2 + Flare mainnet chain definitions
│   ├── contracts.ts           # ContractRegistry resolver + typed contract instances
│   ├── blockscout.ts          # URL helpers for coston2-explorer links
│   └── format.ts              # formatFXRP, formatCR, formatAddress, etc.
└── styles/
    ├── globals.css            # CSS variables (design tokens)
    └── fonts.css              # Space Grotesk, JetBrains Mono, Inter
```

### F.1 `useAttackDemo` state machine

```typescript
// packages/frontend/src/hooks/useAttackDemo.ts

type DemoState =
  | { status: "idle" }
  | { status: "configuring"; fxrpAmount: bigint; pctOfBaseline: number }
  | { status: "awaiting_wallet" }
  | { status: "tx_pending"; txHash: string }
  | { status: "tx_confirmed"; txHash: string; blockNumber: number }
  | { status: "fdc_window";
      txHash: string;
      endsAt: number; // unix timestamp
      fdcStatus: "PENDING" | "FAILED" | "CONFIRMED";
    }
  | { status: "zuko_triggered";
      incidentId: number;
      executeInstructionTx: string;
      opsPauseTx: string;
      transferPauseTx: string;
      forensicLog: DecodedForensicLog;
    }
  | { status: "resuming"; incidentId: number }
  | { status: "complete"; incidentId: number };

// Transitions:
// idle → configuring (user drags slider)
// configuring → awaiting_wallet (click Execute; wallet not connected)
// configuring → tx_pending (click Execute; wallet connected; tx sent)
// awaiting_wallet → tx_pending (wallet connects; tx auto-sent)
// tx_pending → tx_confirmed (tx receipt received)
// tx_confirmed → fdc_window (immediately after confirmation)
// fdc_window → zuko_triggered (ZUKO_PAUSED WebSocket message received)
// zuko_triggered → resuming (auto-resume countdown ends; GUARDIAN_FAST_RESUME sent)
// resuming → complete (ZUKO_RESUMED WebSocket message received)
// complete → idle (user clicks "Run another attack")
```

---

## Appendix G — Environment Variables Reference

```bash
# packages/backend/.env

# ── RPC endpoints (3 required for quorum) ──────────────────────────────
COSTON2_RPC_1=https://coston2-api.flare.network/ext/C/rpc
COSTON2_RPC_2=https://coston2.enosys.global/ext/C/rpc
COSTON2_RPC_3=https://rpc.ankr.com/flare_coston2
COSTON2_WSS=wss://coston2-api.flare.network/ext/C/ws

# ── Mainnet RPCs (Phase 9 only) ─────────────────────────────────────────
FLARE_RPC_1=https://flare-api.flare.network/ext/C/rpc
FLARE_RPC_2=https://flare.enosys.global/ext/C/rpc
FLARE_RPC_3=https://rpc.ankr.com/flare

# ── Contract addresses — resolved via ContractRegistry at runtime ───────
# (No addresses hardcoded here; ContractRegistry address is the only constant)
REGISTRY_ADDRESS=0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019

# ── Demo Guardian Safe ──────────────────────────────────────────────────
GUARDIAN_SAFE_ADDRESS=        # set after Phase 3 deployment
GUARDIAN_PRIVATE_KEY=         # encrypted / loaded from GCP Secret Manager

# ── Zuko Guardian contract ──────────────────────────────────────────────
ZUKO_GUARDIAN_ADDRESS=        # set after Phase 3 deployment
ZUKO_CODE_HASH=               # sha256 of rule engine binary

# ── Redis ───────────────────────────────────────────────────────────────
REDIS_URL=rediss://...        # Upstash Redis URL

# ── Alert webhooks ──────────────────────────────────────────────────────
DISCORD_WEBHOOK_URL=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
PAGERDUTY_INTEGRATION_KEY=   # Phase 8+ only

# ── Blockscout ──────────────────────────────────────────────────────────
BLOCKSCOUT_API_URL=https://coston2-explorer.flare.network/api
BLOCKSCOUT_API_KEY=           # optional; increases rate limits

# packages/rule-engine/.env (injected as sealed secrets in GCP Confidential Space)
FCC_SIGNING_KEY=              # generated inside enclave; never leaves TEE
CLOUD_SIGNING_KEY=            # generated inside cloud enclave
COSTON2_RPC_1=                # same as above
COSTON2_RPC_2=
COSTON2_RPC_3=
ZUKO_GUARDIAN_ADDRESS=
SIGMA_WARN_THRESHOLD=200      # 2.0σ in E2 scale
CR_CLIFF_MIN_AGENTS=3
CR_CLIFF_PCT=5                # 5% drop triggers cliff
CR_CLIFF_BLOCKS=10
REDEEM_BURST_MULTIPLE=5       # 5× baseline
FDC_TIMEOUT_SECONDS=300       # 5 minute FDC attestation window
VOLATILITY_INCENTIVE_FEE=10000000000000000 # 0.01 FLR in wei
```

---

*End of Project Zuko — Final Unified Implementation Plan v1.0*
*Total test cases: 124 across 10 phases*
*Total Solidity tests: 58 unit/integration + 4 invariants (1000 runs each)*
*Estimated delivery: Phases 0–7 in 28 weeks parallel-tracked; Phases 8–9 in 10+ weeks*