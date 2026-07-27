// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ZukoMultiProverVerifier} from "../contracts/ZukoMultiProverVerifier.sol";
import {ZukoForensicLogger} from "../contracts/ZukoForensicLogger.sol";
import {ZukoGuardian} from "../contracts/ZukoGuardian.sol";

/**
 * @title DeployZukoPhase2
 * @notice Deploys Phase 2 TEE Integration contracts to Coston2.
 *
 * Usage:
 *   forge script script/DeployZukoPhase2.s.sol:DeployZukoPhase2 \
 *     --rpc-url $COSTON2_RPC \
 *     --broadcast \
 *     --verify
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY  — deployer / governance wallet
 *   FCC_SIGNER_ADDRESS    — FCC enclave signer public address
 *   CLOUD_SIGNER_ADDRESS  — Cloud enclave signer public address
 *   ASSET_MANAGER_ADDRESS — MockAssetManager or real AM address (no-op target for Phase 2)
 *   TEE_REGISTRY_ADDRESS  — TeeExtensionRegistry address on Coston2
 *   GUARDIAN_MULTISIG     — Guardian multisig address for fast-resume
 *   REGISTERED_CODE_HASH  — SHA-256 hash of reproducible Go binary
 */
contract DeployZukoPhase2 is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address fccSigner = vm.envAddress("FCC_SIGNER_ADDRESS");
        address cloudSigner = vm.envAddress("CLOUD_SIGNER_ADDRESS");
        address assetManager = vm.envAddress("ASSET_MANAGER_ADDRESS");
        address teeRegistry = vm.envAddress("TEE_REGISTRY_ADDRESS");
        address guardianMultisig = vm.envAddress("GUARDIAN_MULTISIG");
        bytes32 registeredCodeHash = vm.envBytes32("REGISTERED_CODE_HASH");

        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy ZukoMultiProverVerifier
        ZukoMultiProverVerifier verifier = new ZukoMultiProverVerifier(
            fccSigner,
            cloudSigner,
            deployer // governance
        );
        console.log("ZukoMultiProverVerifier deployed at:", address(verifier));

        // 2. Predict ZukoGuardian address (needed by ForensicLogger constructor)
        address predictedGuardian = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        // 3. Deploy ZukoForensicLogger
        ZukoForensicLogger forensicLogger = new ZukoForensicLogger(predictedGuardian);
        console.log("ZukoForensicLogger deployed at:", address(forensicLogger));

        // 4. Deploy ZukoGuardian
        ZukoGuardian guardian = new ZukoGuardian(
            assetManager,
            address(verifier),
            teeRegistry,
            address(forensicLogger),
            deployer, // governance
            guardianMultisig,
            registeredCodeHash
        );
        console.log("ZukoGuardian deployed at:", address(guardian));

        // Verify address prediction was correct
        require(address(guardian) == predictedGuardian, "Guardian address prediction mismatch");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Phase 2 Deployment Summary ===");
        console.log("Verifier:       ", address(verifier));
        console.log("ForensicLogger: ", address(forensicLogger));
        console.log("Guardian:       ", address(guardian));
        console.log("FCC Signer:     ", fccSigner);
        console.log("Cloud Signer:   ", cloudSigner);
        console.log("Asset Manager:  ", assetManager);
        console.log("TEE Registry:   ", teeRegistry);
        console.log("Code Hash:      ");
    }
}
