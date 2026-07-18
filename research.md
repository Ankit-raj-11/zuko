# Project Zuko: Flare Ecosystem Security & FAssets Safeguard Research

This document synthesizes and verifies the research material regarding security monitoring on the Flare Network, specifically detailing Hypernative's capabilities and mapping them directly to the design and scope of **Project Zuko**.

---

## 1. Hypernative Capabilities for the Flare Ecosystem
Based on Flare's official partnership announcements, press releases, and security documentation, here are the 25 capabilities Hypernative offers to Flare and the broader Web3 ecosystem:

1. **Always-On Ecosystem Monitoring**: Provides continuous, real-time security monitoring across the entire Flare L1 ecosystem at both the base-protocol and dApp/smart contract level.
2. **Pre-Execution Threat Detection**: Detects zero-day exploits, flash loan attacks, and anomalous transactions before execution (mempool level) to provide critical lead-time windows.
3. **Cross-Chain Bridge Monitoring**: Monitors bridge contracts and associated cross-chain message flows as a distinct, high-risk attack surface.
4. **Internal Infrastructure Monitoring**: Tracks Flare core smart contracts (such as price feedback systems and data connectors) for operational and security integrity.
5. **Multisig & Governance Wallet Auditing**: Monitors transaction initiation, threshold changes, and unexpected activities on multi-signature admin/guardian wallets.
6. **Treasury & Token Allocation Tracking**: Observes movement of treasury funds, foundation allocations, and ecosystem incentives to flag anomalous withdrawals.
7. **Smart Contract Security Risk Monitoring**: Identifies code-level vulnerabilities, reentrancy vectors, and malicious contracts deployed on the network.
8. **Compliance & Sanctions Screenings**: Flags interactions, funding flows, and addresses tied to sanctioned entities (e.g., OFAC) or high-risk mixers.
9. **Threat Intelligence Database**: Integrates active feeds of known exploits, bad actors, attack infrastructure, and emerging attack vectors across multiple chains.
10. **Financial & Market Risk Analysis**: Monitors abnormal asset price deviations, liquidity pools, oracle manipulation patterns, and de-pegging risks.
11. **Operational Parameter Anomaly Detection**: Warns of incorrect configuration adjustments, parameter updates, or unexpected state transitions within core protocols.
12. **Governance Attack Prevention**: Monitors proposals, vote accumulation, and flash loan governance voting manipulation vectors in DAOs and protocol governance.
13. **User-Facing Fraud & Phishing Detection**: Tracks front-end spoofing, phishing sites, and address poisoning schemes targeting end-users.
14. **Machine Learning Anomaly Models**: Leverages ML models trained on historical Web3 attack vectors to classify and score transaction anomalies.
15. **Heuristics & Rule-Based Detection Engine**: Combines rule-based pattern matching with ML to detect known attack signatures immediately.
16. **Pre-State Transaction Simulation**: Simulates transaction executions off-chain against current blockchain states to verify outcomes and state changes.
17. **Graph-Based Address Clustering**: Uses graph-database analysis to map relations between exploiter funding addresses, mixers, and malicious smart contracts.
18. **Automated Defensive Pausing**: Capable of triggering automated protocol pauses or emergency lockdowns when a high-confidence threat is identified.
19. **dApp-Level Monitoring Support**: Assists Flare-native developers in configuring custom alerts and automated mitigation scripts for their own projects.
20. **Post-Incident Response & Forensics**: Provides expert root-cause analysis, tracing of stolen assets, and technical forensic support post-exploit.
21. **Fund Recovery & Exchange Coordination**: Utilizes industry networks (exchanges, stablecoin issuers, law enforcement) to freeze and recover stolen assets.
22. **FAssets Emergency Alert Integration**: Serves as an external alert layer feeding signals into FAssets' Alert Mode and the system-wide emergency pause.
23. **Core Security Stack Alliance**: Named as one of the three foundational security partners of Flare (alongside Immunefi for bug bounties and Elliptic for compliance).
24. **Human-in-the-Loop Governance Alerting**: Provides detailed dashboard alerts that Flare's Foundation or Governance Guardians manually review to make protocol execution decisions.
25. **Broad dApp Coverage Extension**: Extends monitoring to individual consumer dApps, wallets, and protocols built on Flare, protecting the network from contagion risks.

---

## 2. Project Zuko Capabilities Matrix
To design Zuko effectively, we map the 25 Hypernative capabilities to what we can feasibly build as an on-chain, permissionless or decentralized guardian system, highlighting what is **in-scope** vs. **out-of-scope**.

| # | Hypernative Capability | Zuko Implementation Scope | Feasibility & Technical Approach |
|---|-----------------------|---------------------------|----------------------------------|
| **1** | Always-On Ecosystem Monitoring | **Partially (Scoped)** | Polling FAssets-relevant on-chain state (AssetManager, Collateral Pool) every block/epoch, rather than full L1 monitoring. |
| **2** | Pre-Execution Threat Detection | **Partially** | Restricted to on-chain state transitions (e.g., Collateral Ratio crashes, massive redemptions). No mempool-level pre-execution analysis. |
| **3** | Cross-Chain Bridge Monitoring | **Partially (Scoped)** | Monitoring FAssets' XRPL/BTC bridge state using FDC-attested data (Flare Data Connector) specifically, rather than general bridges. |
| **4** | Internal Infrastructure Monitoring | **Yes (FAssets)** | Direct on-chain read access to `AssetManager` settings and FTSO price feeds. |
| **5** | Multisig Wallet Monitoring | **No** | Out of scope for v1. Can potentially watch specific guardian transactions in later iterations. |
| **6** | Treasury & Token Allocations | **No** | Out of scope. Zuko focuses on collateral and redemption health. |
| **7** | Security Risk Monitoring | **Partially** | Detects state anomalies resulting from exploits (e.g. abrupt price or collateral drop), not bytecode-level contract verification. |
| **8** | Compliance & Sanctions | **No** | Out of scope. Requires off-chain compliance APIs (e.g., Elliptic/Chainalysis) which Zuko does not ingest. |
| **9** | Threat Intelligence Database | **No** | Out of scope. Zuko operates on real-time state rules without historical off-chain intelligence lists. |
| **10** | Financial & Market Risk | **Yes (Core)** | Real-time monitoring of FTSO price deviations, collateral pool sizes, and redemption success rates. |
| **11** | Operational Parameter Anomalies | **Partially** | Compares current `AssetManager` parameter changes against expected ranges. |
| **12** | Governance Attack Prevention | **No** | Out of scope. Zuko does not monitor proposal queues or vote accumulation. |
| **13** | Phishing & Fraud Detection | **No** | Out of scope. Phishing is a Web2/frontend threat; Zuko is strictly smart contract-centric. |
| **14** | Machine Learning Models | **Partially (Minimal)** | Lightweight, on-chain mathematical anomaly scoring models (e.g., Z-scores or rolling standard deviations of prices) can run, but without historical training sets. |
| **15** | Heuristics & Rule-Based Engine | **Yes (Core)** | Implemented via Solidity threshold layers evaluating state constraints (e.g., $CR < CR_{critical}$). |
| **16** | Pre-State Transaction Simulation | **No** | Cannot simulate arbitrary transactions on-chain before execution without off-chain infrastructure. |
| **17** | Graph-Based Address Clustering | **No** | Out of scope. Requires specialized graph database indexing (like Erigon or Graph protocol) and massive off-chain indexing. |
| **18** | Automated Defensive Pausing | **Yes (Core)** | Zuko's primary objective: executing permissionless or automated calls to trigger `AssetManager`'s emergency pause when thresholds are breached. |
| **19** | dApp-Level Monitoring Support | **No** | Zuko is a single-purpose, highly-optimized security layer for FAssets, not a general SaaS toolkit. |
| **20** | Post-Incident Response | **Partially** | Emits rich on-chain event logs to assist developers in forensic reconstruction, but offers no human services. |
| **21** | Fund Recovery & Coordination | **No** | Out of scope. Zuko has no off-chain legal, regulatory, or exchange contacts. |
| **22** | FAssets Alert Mode Integration | **Yes (Core)** | Designed to directly interface with FAssets' existing pause hooks or act as a decentralized backup guardian. |
| **23** | Core Security Stack Alliance | **No** | A reputation and alliance position, not a technical feature. |
| **24** | Governance Alerting (Manual) | **Partially (Inverted)** | Zuko automates the intervention of on-chain provable failures, bypassing the delay of manual human-in-the-loop decisions. |
| **25** | Broad dApp Coverage | **No** | Out of scope. Narrowly focused on FAssets safety. |

---

## 3. What Zuko CANNOT Do (The "Cannot Do" List)
To manage project expectations and focus on our core value proposition, the following features are explicitly out of scope for Zuko:

* **Ecosystem-Wide Infrastructure Audit**: We do not monitor arbitrary L1 infrastructure, token treasuries, foundation addresses, or third-party dApps.
* **Mempool / Pre-Execution Analysis**: We cannot inspect the mempool or run pre-execution simulation on Flare (this is typically reserved for specialized node operators or off-chain systems).
* **Compliance & Sanctions Screening**: We do not parse OFAC or Elliptic compliance databases.
* **Off-Chain / Social Engineering Defenses**: We cannot protect against DNS hijackings, frontend phishing attacks, or social media scams.
* **Graph Databases & Threat Intelligence**: We do not maintain or query large-scale historical threat data, nor do we run graph-based address clustering.
* **Human Incident Response & Fund Recovery**: We are a technical protocol, not a security consultancy with relations to law enforcement or exchanges.

---

## 4. The Technical Focus of Zuko
Rather than trying to replicate Hypernative's massive off-chain SaaS platform, **Zuko is a decentralized, on-chain "circuit breaker" specifically tailored for Flare's FAssets.** 

### FAssets Emergency Pause System Reference
The FAssets protocol contains a structured, multi-level emergency pause system managed via the `AssetManager` contract (`IIAssetManager.sol`). The pause levels are:
1. **Start Operations**: Pauses new action initiation (like minting) while letting active processes complete (useful for planned upgrades).
2. **Halted Operations**: Halts key operations including minting, redemptions, liquidations, and collateral pool deposits/withdrawals.
3. **Full**: Stops all activities except for core contract settings updates, upgrades, and FAsset token transfers.
4. **Full and Transfer**: The most restrictive level. Freezes all functions, including the transfer of FAssets.

**Zuko's Core Objective:** Create an on-chain verification contract (the *Zuko Guardian*) that reads real-time price feeds from the **Flare Time Series Oracle (FTSO)** and verifies collateral health. If an anomaly or sudden crash is detected (e.g., massive collateral pool imbalance, oracle price deviation exceeding limits, or bridge state anomalies verified by the **Flare Data Connector**), the *Zuko Guardian* uses its permissioned or keeper-triggered role to call `AssetManager.emergencyPause(level)` to lock the system before exploitation cascades.
