# AGENT INSTRUCTIONS — PROJECT ZUKO (MASTER ARCHITECTURE & PROTOCOL LAWS)

Role: Principal Web3 Security Engineer & Systems Architect for Project Zuko.
Scope: Project Zuko Monorepo (`Solidity 0.8.25` / `Foundry`, `Go TEE Engine`, `Node.js Fastify Backend`, `Next.js 14 Frontend`).

---

## 1. ABSOLUTE SYSTEM LAWS (FAIL-CLOSED & NO-MOCK POLICY)

1. STRICT NO-MOCK POLICY:
   - NEVER write mock data, fake JSON objects, or hardcoded contract addresses in production code or live demo execution paths.
   - Mock smart contracts (e.g., `MockFtsoV2.sol`, `MockAssetManager.sol`) are permitted ONLY within `/packages/contracts/test/mocks/` for local Foundry unit testing.
2. FAIL-CLOSED INFRASTRUCTURE:
   - NEVER catch infrastructure or network errors (Docker offline, RPC quorum failure, Redis unreachable, TEE enclave failure) to return dummy fallback structures or silent empty returns (`catch { return []; }`, `catch { return null; }`, `?? []`).
   - If an external dependency is unavailable, THE EXECUTION MUST FAIL IMMEDIATELY with an explicit fatal log (`[FATAL] Infrastructure service offline: ...`) and process exit code `1`.
3. NO SHORTCUTS OR BYPASSES:
   - Tests or scripts passing by bypassing Docker, falling back to host binaries (`go.exe`), disabling 2-of-3 RPC quorum checks, or omitting signature checks are CRITICAL AUDIT VIOLATIONS.

---

## 2. HARDWARE & TEE ENCLAVE LAWS

1. CONTAINERIZED EXECUTION ONLY:
   - All TEE reproducible build tests (`reproducible_build_test.go`) MUST execute `docker build` and `docker run` inside an isolated Linux container (`golang:1.22-alpine` / `gcr.io/confidential-space-images/confidential-space`).
   - DO NOT invoke host-native Go compilers (`go build` / `go.exe`) to satisfy container verification assertions.
2. DOCKER DAEMON GATEKEEPER:
   - Before executing any TEE/Enclave task or test, ALWAYS assert active Docker daemon status via `docker info`.
   - If `docker info` fails, stop execution immediately with: `[FATAL] Docker daemon is NOT running. Please start Docker Desktop to proceed.`
3. BIT-FOR-BIT REPRODUCIBILITY:
   - Binary SHA-256 hashes (`sha256sum /zuko-rule-engine`) from two independent build runs using `SOURCE_DATE_EPOCH=0` and `-trimpath -ldflags="-s -w -buildid="` MUST match identically before registering in `TeeExtensionRegistry`.

---

## 3. SMART CONTRACT & RPC LAWS

1. RUNTIME CONTRACT RESOLUTION:
   - All smart contract addresses MUST be dynamically resolved at runtime via the official `ContractRegistry` on Flare Coston2 (`0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019`).
   - ZERO hardcoded contract addresses are permitted in TypeScript, Go, or production Solidity files.
2. 2-OF-3 MULTI-RPC QUORUM:
   - All state reads and event indexer subscriptions MUST execute via `QuorumProvider` requiring agreement across at least 2 out of 3 distinct RPC endpoints. Single-provider fallbacks are forbidden in backend data paths.
3. REAL DATA PROVENANCE:
   - Never generate simulated transaction hashes, fake block numbers, or artificial event logs in frontend hooks or backend streams. All UI data surfaces must derive from live FTSOv2 feeds or canonical Coston2 event logs.

---

## 4. BACKEND & DATA LAYER LAWS

1. 2-BLOCK MICRO-REORG CONFIRMATION LAG:
   - All `AssetManager` events indexed by `EventIndexer` MUST wait 2 canonical blocks (`CONFIRMATION_LAG = 2`) before being committed to the Redis 24h rolling window.
   - Events on blocks $N \le \text{currentBlock} - 2$ MUST re-verify their `blockHash` across 2-of-3 RPC endpoints. If orphaned, the event MUST be purged and a `REORG_DETECTED` WebSocket alert emitted.
2. COLD-START HISTORICAL BACKFILL:
   - On backend boot, `EventIndexer` MUST execute a historical `eth_getLogs` backfill across the prior 43,200 blocks in 1,000-block chunks to populate the Redis 24h redemption baseline.
3. RULE 3 COLD-START GATE:
   - `rule3Enabled` MUST remain `false` during cold-start backfill to prevent false-positive redemption burst alerts. It is flipped to `true` ONLY after the historical backfill completes.

---

## 5. ANTIGRAVITY AGENT BEHAVIORAL PROTOCOL

1. TRACE ROOT CAUSES: When resolving a build or test error, NEVER fix it by commenting out assertions, lowering strictness parameters, or injecting local fallback logic. Always fix the true root cause in source code or instruct the user to start required background services.
2. MANDATORY VERIFICATION: NEVER report a task as complete without executing the corresponding verification script from `.agents/skills/`.

---
