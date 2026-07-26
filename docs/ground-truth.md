# Zuko — Ground Truth Document

> **Phase 0 Deliverable** — All on-chain discovered values, protocol parameters, and confirmed governance paths.
> Verified via live Coston2 fork tests on July 26, 2026.

---

## 1. ContractRegistry Resolution

| Contract | Registry Name | Resolved Address | Verified On |
|---|---|---|---|
| FtsoV2 | `FtsoV2` | `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d` | Coston2 (ChainID 114) |
| FdcVerification | `FdcVerification` | `0x906507E0B64bcD494Db73bd0459d1C667e14B933` | Coston2 (ChainID 114) |
| AssetManagerController | `AssetManagerController` | `0x1C772F700308aF4c13897cc7b9c41EFfB82c50C0` | Coston2 (ChainID 114) |
| AssetManager (FXRP) | _(via controller)_ | `0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA` | Coston2 (ChainID 114) |

**3-RPC consistency check:** All 3 endpoints returned identical addresses: ✅ Yes

---

## 2. AssetManager Live Settings

- `getSettings()` payload verified live on-chain at `0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA`
- `maxEmergencyPauseDurationSeconds`: 21,600s (6 hours)
- `emergencyPauseDurationResetAfterSeconds`: 86,400s (24 hours)

---

## 3. Pause Guardian Access Control

- `emergencyPause()` from unauthorized accounts reverts cleanly (verified in `test_TC03_PauseGuardian_NonGuardianReverts`)
- `ZukoGuardian.sol` must be granted the pause-guardian role by governance before executing pauses on Coston2

---

## 4. FTSO Feed Verification

| Feed | Feed ID | Decimals | Sample Live Price | CoinGecko Match |
|---|---|---|---|---|
| XRP/USD | `0x015852502f55534400000000000000000000000000` | 6 | $1.100098 | ✅ Verified |

---

## 5. Agent Vault Enumeration

- Active FXRP AssetManager instances on Coston2: 1 (`0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA`)

---

## 6. Faucet & Network Configuration

- Network: Flare Testnet Coston2 (Chain ID 114)
- Faucet URL: `https://faucet.flare.network`
