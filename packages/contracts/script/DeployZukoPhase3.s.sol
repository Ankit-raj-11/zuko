// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ZukoMultiProverVerifier} from "../contracts/ZukoMultiProverVerifier.sol";
import {ZukoForensicLogger} from "../contracts/ZukoForensicLogger.sol";
import {ZukoGuardian} from "../contracts/ZukoGuardian.sol";

/**
 * @title DeployZukoPhase3
 * @notice Phase 3 deployment — ZukoGuardian wired to the REAL Coston2 AssetManager.
 *
 * This script re-deploys a fresh ZukoGuardian pointing to the official Flare
 * AssetManager on Coston2 (or a Flare-provided dedicated instance). The Phase 2
 * contracts (verifier, forensicLogger) are reused if already deployed;
 * if not, this script deploys them fresh.
 *
 * Prerequisites:
 *   - Docker TEE enclave is running and has signed at least one test instruction.
 *   - Flare Foundation (or hackathon judges) have agreed to grant ZukoGuardian
 *     the pause-guardian role on ASSET_MANAGER_ADDRESS.
 *   - For hackathon demo: use fork mode to simulate governance authorization.
 *
 * Usage (Phase 3 live deployment):
 *   forge script script/DeployZukoPhase3.s.sol:DeployZukoPhase3 \
 *     --rpc-url https://rpc.ankr.com/flare_coston2 \
 *     --broadcast \
 *     --legacy \
 *     -vvv
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY      — deployer wallet private key
 *   FCC_SIGNER_ADDRESS        — FCC enclave public key (same as Phase 2)
 *   CLOUD_SIGNER_ADDRESS      — Cloud enclave public key (same as Phase 2)
 *   ASSET_MANAGER_ADDRESS     — REAL Flare AssetManager on Coston2
 *   TEE_REGISTRY_ADDRESS      — TeeExtensionRegistry on Coston2 (unchanged from Phase 2)
 *   GUARDIAN_MULTISIG         — Guardian multisig wallet address
 *   REGISTERED_CODE_HASH      — SHA-256 hash of reproducible Go TEE binary
 *
 * Optional (skip re-deployment if already live from Phase 2):
 *   EXISTING_VERIFIER_ADDRESS     — reuse Phase 2 ZukoMultiProverVerifier
 *   EXISTING_FORENSIC_LOGGER_ADDRESS — reuse Phase 2 ZukoForensicLogger
 */
contract DeployZukoPhase3 is Script {

    // ── Known Coston2 AssetManager address (official Flare FAssets v2) ──────
    // Source: https://dev.flare.network/fassets/reference/coston2
    // This can be overridden via ASSET_MANAGER_ADDRESS env var.
    address constant COSTON2_FASSETS_ASSET_MANAGER =
        0x8a6b58b4E2f9a507133dD6DB67BC0A9037d15d20;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        address fccSigner    = vm.envAddress("FCC_SIGNER_ADDRESS");
        address cloudSigner  = vm.envAddress("CLOUD_SIGNER_ADDRESS");
        address teeRegistry  = vm.envAddress("TEE_REGISTRY_ADDRESS");
        address guardianMultisig = vm.envAddress("GUARDIAN_MULTISIG");
        bytes32 registeredCodeHash = vm.envBytes32("REGISTERED_CODE_HASH");

        // Real AssetManager: from env or fallback to well-known Coston2 address
        address assetManager;
        try vm.envAddress("ASSET_MANAGER_ADDRESS") returns (address addr) {
            assetManager = addr;
        } catch {
            assetManager = COSTON2_FASSETS_ASSET_MANAGER;
        }

        console.log("=== Zuko Phase 3 Deployment ===");
        console.log("Deployer:         ", deployer);
        console.log("AssetManager:     ", assetManager);
        console.log("TeeRegistry:      ", teeRegistry);
        console.log("FCC Signer:       ", fccSigner);
        console.log("Cloud Signer:     ", cloudSigner);
        console.log("Guardian Multisig:", guardianMultisig);

        vm.startBroadcast(deployerKey);

        // ── 1. Deploy or reuse ZukoMultiProverVerifier ───────────────────────
        address verifierAddr;
        try vm.envAddress("EXISTING_VERIFIER_ADDRESS") returns (address existing) {
            verifierAddr = existing;
            console.log("Reusing Phase 2 Verifier:  ", verifierAddr);
        } catch {
            ZukoMultiProverVerifier verifier = new ZukoMultiProverVerifier(
                fccSigner,
                cloudSigner,
                deployer
            );
            verifierAddr = address(verifier);
            console.log("New Verifier deployed:     ", verifierAddr);
        }

        // ── 2. Predict ZukoGuardian address for ForensicLogger wiring ────────
        address predictedGuardian = vm.computeCreateAddress(
            deployer,
            vm.getNonce(deployer) + 1
        );

        // ── 3. Deploy or reuse ZukoForensicLogger ────────────────────────────
        address forensicLoggerAddr;
        try vm.envAddress("EXISTING_FORENSIC_LOGGER_ADDRESS") returns (address existing) {
            forensicLoggerAddr = existing;
            console.log("Reusing Phase 2 ForensicLogger: ", forensicLoggerAddr);
        } catch {
            ZukoForensicLogger forensicLogger = new ZukoForensicLogger(predictedGuardian);
            forensicLoggerAddr = address(forensicLogger);
            console.log("New ForensicLogger deployed:    ", forensicLoggerAddr);
        }

        // ── 4. Deploy Phase 3 ZukoGuardian (real AssetManager target) ────────
        ZukoGuardian guardian = new ZukoGuardian(
            assetManager,       // ← REAL AssetManager (not mock)
            verifierAddr,
            teeRegistry,
            forensicLoggerAddr,
            deployer,           // governance
            guardianMultisig,
            registeredCodeHash
        );

        // ── 5. Verify address prediction ─────────────────────────────────────
        require(
            address(guardian) == predictedGuardian,
            "DeployZukoPhase3: guardian address prediction mismatch"
        );

        vm.stopBroadcast();

        // ── 6. Verify getLivePauseSettings() returns values ──────────────────
        // (matches Phase 0 ground truth assertions)
        (
            uint256 maxOpsDuration,
            uint256 maxTransferDuration,
            uint256 opsResetAfter,
            /* transferResetAfter */
        ) = guardian.getLivePauseSettings();

        console.log("");
        console.log("=== Phase 3 Live Pause Settings (from real AssetManager) ===");
        console.log("maxOpsDuration:     ", maxOpsDuration);
        console.log("maxTransferDuration:", maxTransferDuration);
        console.log("opsResetAfter:      ", opsResetAfter);

        // Safety gate: ensure live pause settings are non-zero (AM is responding)
        require(maxOpsDuration > 0, "DeployZukoPhase3: AssetManager not responding to pause settings query");

        console.log("");
        console.log("=== Phase 3 Deployment Summary ===");
        console.log("Guardian (Phase 3): ", address(guardian));
        console.log("Verifier:           ", verifierAddr);
        console.log("ForensicLogger:     ", forensicLoggerAddr);
        console.log("AssetManager:       ", assetManager);
        console.log("TeeRegistry:        ", teeRegistry);
        console.log("Code Hash:          ");
        console.log(uint256(registeredCodeHash));
        console.log("");
        console.log(">>> NEXT STEP: Grant ZukoGuardian the pauseGuardian role on AssetManager.");
        console.log(">>> Address to whitelist:", address(guardian));
    }
}
