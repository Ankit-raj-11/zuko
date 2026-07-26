# Project Zuko

### On-Chain FAssets Security Guardian + Premium Live Demo UI

> TEE-attested circuit breaker for Flare FAssets with a real-time threat theatre demo

---

## What is Zuko?

**Zuko** is a security guardian for Flare's FAssets protocol. It combines:

1. **The Guardian** — A TEE-attested, on-chain circuit breaker that reads live FTSOv2 feeds, tracks real AssetManager state, evaluates six detection rules inside a verifiable enclave, and calls `emergencyPause()` within seconds of a confirmed anomaly.

2. **The Demo UI** — A "threat theatre" where any visitor connects a wallet to Coston2, executes a real attack transaction against the real deployed AssetManager, watches Zuko detect it via real on-chain events, and sees a real `emergencyPause()` transaction fire.

**Every number on every screen traces back to a verifiable on-chain source. Nothing is simulated.**

## Stack

| Layer | Technology |
|---|---|
| Smart Contracts | Solidity 0.8.25, Foundry |
| TEE Rule Engine | Go, GCP Confidential Space (FCC), AWS Nitro |
| Backend | Node.js 20, Fastify, Redis, WebSocket |
| Frontend | Next.js 14, TradingView Charts, RainbowKit, wagmi v2 |
| Networks | Coston2 (testnet) → Flare mainnet |

## Repository Structure

```
zuko/
├── packages/
│   ├── contracts/          # Foundry project (Solidity)
│   │   ├── contracts/      # Production contracts
│   │   │   └── interfaces/ # Flare protocol interfaces
│   │   └── test/           # Foundry tests + mocks
│   ├── rule-engine/        # Go TEE binary
│   ├── backend/            # Node.js + Fastify
│   └── frontend/           # Next.js 14
├── docs/
│   └── ground-truth.md     # Phase 0 deliverable
└── README.md
```

## Contract Architecture

- **`ZukoGuardian.sol`** — Core InstructionSender-compatible circuit breaker
- **`ZukoMultiProverVerifier.sol`** — Verifies 2-of-2 / 1-of-2 TEE signatures
- **`ZukoForensicLogger.sol`** — Append-only on-chain incident log
- **`ZukoFTSOWatcher.sol`** — Ring-buffer + z-score helper with WAD normalization

## Detection Rules

| Rule | Condition | Response |
|---|---|---|
| R1 — FTSO Deviation | 3-step: z-score > 2σ + anchor dev > 1.5% sustained | MEDIUM (ops pause) |
| R2 — CR Cliff | ≥3 agents' CRs drop >5% in ≤10 blocks | MEDIUM (ops pause) |
| R3 — Redemption Burst | Volume >5× baseline AND FDC attestation fails | HIGH (both surfaces) |
| R4 — Core Vault | FDC-attested payment >20% above expected delta | CRITICAL (max duration) |
| R5 — Liquidation Payout | Realized vs FTSO-implied payout deviation >10% | ALERT only |
| R6 — Self-Dealing | High-value transfers between linked addresses | ALERT only |

## Networks

| Network | Chain ID | Usage |
|---|---|---|
| Coston2 | 114 | Development & demo |
| Songbird | 19 | FCC testing |
| Flare mainnet | 14 | Production |

## Getting Started

```bash
# Clone
git clone https://github.com/Ankit-raj-11/zuko.git
cd zuko

# Copy environment variables
cp .env.example .env

# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Build contracts
cd packages/contracts
forge build

# Run tests
forge test -vvv
```

## Key Links

- [Flare Developer Hub](https://dev.flare.network)
- [FAssets Overview](https://dev.flare.network/fassets/overview)
- [Coston2 Explorer](https://coston2-explorer.flare.network)
- [ContractRegistry](https://coston2-explorer.flare.network/address/0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019)

## License

MIT
