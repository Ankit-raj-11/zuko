// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ZukoGuardian} from "../contracts/ZukoGuardian.sol";
import {ZukoMultiProverVerifier} from "../contracts/ZukoMultiProverVerifier.sol";
import {ZukoForensicLogger} from "../contracts/ZukoForensicLogger.sol";
import {MockAssetManager} from "./mocks/MockAssetManager.sol";
import {MockTeeRegistry} from "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoGuardianTest
 * @notice Phase 2 test cases TC-05..10 for ZukoGuardian.
 *         Uses real ECDSA signatures from Foundry vm.sign().
 *         MockAssetManager records calls — not a no-op; it tracks state.
 *         MockTeeRegistry is the minimal FCC registry interface.
 */
contract ZukoGuardianTest is Test {
    ZukoGuardian public guardian;
    ZukoMultiProverVerifier public verifier;
    ZukoForensicLogger public forensicLogger;
    MockAssetManager public mockAM;
    MockTeeRegistry public teeRegistry;

    uint256 constant FCC_PRIVATE_KEY   = 0x1;
    uint256 constant CLOUD_PRIVATE_KEY = 0x2;
    uint256 constant ROGUE_PRIVATE_KEY = 0x3;

    address fccAddr;
    address cloudAddr;
    address rogueAddr;

    address governance;
    address guardianMultisig;

    bytes32 constant CODE_HASH = keccak256("zuko-tee-v1.0");

    function setUp() public {
        fccAddr   = vm.addr(FCC_PRIVATE_KEY);
        cloudAddr = vm.addr(CLOUD_PRIVATE_KEY);
        rogueAddr = vm.addr(ROGUE_PRIVATE_KEY);
        governance = address(this);
        guardianMultisig = address(0xABCD);

        // Deploy verifier
        verifier = new ZukoMultiProverVerifier(fccAddr, cloudAddr, governance);

        // Deploy TEE registry and register our code hash
        teeRegistry = new MockTeeRegistry();
        teeRegistry.registerHash(CODE_HASH);

        // Deploy MockAssetManager — guardian address TBD, set after guardian deploy
        mockAM = new MockAssetManager(address(0)); // temp guardian

        // Deploy forensic logger — guardian address TBD
        // We need to predict guardian address or deploy in two steps
        // Use a placeholder, then set guardian on AM after Guardian deploy

        // Deploy Guardian first to get address, then wire everything
        // Actually: ForensicLogger needs guardian address at construction (immutable)
        // So we deploy guardian address with CREATE2 or use a two-step approach.
        // Simpler: compute the guardian address via nonce.

        // Current nonce: this contract has deployed verifier(nonce0), teeRegistry(nonce1),
        // mockAM(nonce2). ForensicLogger will be nonce3, Guardian will be nonce4.
        address predictedGuardian = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        forensicLogger = new ZukoForensicLogger(predictedGuardian);

        guardian = new ZukoGuardian(
            address(mockAM),
            address(verifier),
            address(teeRegistry),
            address(forensicLogger),
            governance,
            guardianMultisig,
            CODE_HASH
        );

        // Verify prediction was correct
        assertEq(address(guardian), predictedGuardian, "Guardian address prediction mismatch");

        // Set guardian as pause guardian on MockAssetManager
        mockAM.setPauseGuardian(address(guardian));
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    function _buildInstruction(
        uint8 severity,
        uint8 rulesTriggered,
        uint32 opsPause,
        uint32 transferPause,
        bytes32 fdcRef,
        uint64 nonce
    ) internal view returns (bytes memory) {
        return abi.encode(
            ZukoGuardian.ZukoInstruction({
                severity: severity,
                rulesTriggered: rulesTriggered,
                opsPauseDuration: opsPause,
                transfersPauseDuration: transferPause,
                feedId: bytes32(uint256(0x01)),
                feedValue: 1e18,
                anchorValue: 1e18,
                blockRangeStart: uint64(block.number >= 10 ? block.number - 10 : 0),
                blockRangeEnd: uint64(block.number),
                fdcAttestationRef: fdcRef,
                nonce: nonce,
                chainId: uint32(block.chainid)
            })
        );
    }

    function _signInstruction(bytes memory encodedInst, uint256 privKey)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(encodedInst)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ── PHASE-2-TC-05: MEDIUM instruction executes with 1-of-2 sig ──────

    function test_ExecuteInstruction_Medium_OpsOnly_PausesOps() public {
        bytes memory inst = _buildInstruction(
            1,       // MEDIUM
            0x02,    // Rule 2 (correlated CR cliff)
            3600,    // 1 hour ops pause
            0,       // no transfer pause
            bytes32(0),
            1        // nonce
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        guardian.executeInstruction(inst, fccSig, "");

        // Verify ops pause was called
        assertEq(mockAM.opsPauseCallCount(), 1, "Ops pause should be called once");
        assertEq(mockAM.lastOpsPauseDuration(), 3600, "Ops pause duration should be 3600");
        assertEq(mockAM.transferPauseCallCount(), 0, "Transfer pause should NOT be called");

        // Verify incident recorded
        assertEq(guardian.totalIncidents(), 1, "Should have 1 incident");

        // Verify nonce used
        assertTrue(guardian.usedNonces(1), "Nonce 1 should be marked used");

        // Verify forensic logger
        assertEq(forensicLogger.totalIncidents(), 1, "ForensicLogger should have 1 incident");
    }

    // ── PHASE-2-TC-05b: MEDIUM with cloud sig only also works ────────────

    function test_ExecuteInstruction_Medium_CloudSigOnly_PausesOps() public {
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory cloudSig = _signInstruction(inst, CLOUD_PRIVATE_KEY);

        guardian.executeInstruction(inst, "", cloudSig);

        assertEq(mockAM.opsPauseCallCount(), 1);
        assertEq(guardian.totalIncidents(), 1);
    }

    // ── PHASE-2-TC-06: CRITICAL requires 2-of-2 or reverts ──────────────

    function test_ExecuteInstruction_Critical_OnlyOneSig_Reverts() public {
        bytes memory inst = _buildInstruction(
            3,       // CRITICAL
            0x08,    // Rule 4 (Core Vault anomaly)
            21600,   // 6 hours
            21600,   // 6 hours
            keccak256("fdc-mismatch"), // fdcRef
            1
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        // Only FCC sig → should revert with InsufficientSigners(3)
        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(3)
            )
        );
        guardian.executeInstruction(inst, fccSig, "");
    }

    function test_ExecuteInstruction_Critical_BothSigs_Succeeds() public {
        bytes memory inst = _buildInstruction(
            3,       // CRITICAL
            0x08,    // Rule 4
            21600,
            21600,
            keccak256("fdc-mismatch"),
            1
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _signInstruction(inst, CLOUD_PRIVATE_KEY);

        guardian.executeInstruction(inst, fccSig, cloudSig);

        // Both pause surfaces should be called
        assertEq(mockAM.opsPauseCallCount(), 1, "Ops pause called");
        assertEq(mockAM.transferPauseCallCount(), 1, "Transfer pause called");
        assertEq(guardian.totalIncidents(), 1);
    }

    // ── PHASE-2-TC-07: Nonce replay rejected ─────────────────────────────

    function test_ExecuteInstruction_ReplayedNonce_Reverts() public {
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 42);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        // First execution succeeds
        guardian.executeInstruction(inst, fccSig, "");
        assertEq(guardian.totalIncidents(), 1);

        // Replay with same nonce should revert
        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.NonceAlreadyUsed.selector, uint64(42))
        );
        guardian.executeInstruction(inst, fccSig, "");
    }

    // ── PHASE-2-TC-08: Wrong chain ID rejected ───────────────────────────

    function test_ExecuteInstruction_WrongChainId_Reverts() public {
        // Build instruction with wrong chain ID
        bytes memory inst = abi.encode(
            ZukoGuardian.ZukoInstruction({
                severity: 1,
                rulesTriggered: 0x02,
                opsPauseDuration: 3600,
                transfersPauseDuration: 0,
                feedId: bytes32(uint256(0x01)),
                feedValue: 1e18,
                anchorValue: 1e18,
                blockRangeStart: uint64(block.number >= 10 ? block.number - 10 : 0),
                blockRangeEnd: uint64(block.number),
                fdcAttestationRef: bytes32(0),
                nonce: 1,
                chainId: 999 // WRONG chain ID
            })
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoGuardian.InvalidChainId.selector,
                uint32(block.chainid),
                uint32(999)
            )
        );
        guardian.executeInstruction(inst, fccSig, "");
    }

    // ── PHASE-2-TC-09: Deregistered code hash rejected ───────────────────

    function test_ExecuteInstruction_AfterDeregistration_Reverts() public {
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        // Deregister the code hash (FCC kill switch)
        teeRegistry.deregisterHash(CODE_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.NotRegisteredInFCC.selector, CODE_HASH)
        );
        guardian.executeInstruction(inst, fccSig, "");
    }

    function test_ExecuteInstruction_ReregisteredCodeHash_Succeeds() public {
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        // Deregister then re-register
        teeRegistry.deregisterHash(CODE_HASH);
        teeRegistry.registerHash(CODE_HASH);

        // Should succeed after re-registration
        guardian.executeInstruction(inst, fccSig, "");
        assertEq(guardian.totalIncidents(), 1);
    }

    // ── PHASE-2-TC-10: ZukoForensicLog contains all required fields ──────

    function test_ForensicLog_ContainsAllRequiredFields() public {
        bytes32 testFeedId = bytes32(uint256(0xAA));
        uint256 testFeedValue = 58210 * 1e13; // WAD-normalized XRP price
        uint256 testAnchorValue = 58000 * 1e13;
        bytes32 testFdcRef = keccak256("fdc-test");

        bytes memory inst = abi.encode(
            ZukoGuardian.ZukoInstruction({
                severity: 2,         // HIGH
                rulesTriggered: 0x06, // R2 + R3
                opsPauseDuration: 7200,
                transfersPauseDuration: 3600,
                feedId: testFeedId,
                feedValue: testFeedValue,
                anchorValue: testAnchorValue,
                blockRangeStart: 1000,
                blockRangeEnd: 1010,
                fdcAttestationRef: testFdcRef,
                nonce: 77,
                chainId: uint32(block.chainid)
            })
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _signInstruction(inst, CLOUD_PRIVATE_KEY);

        // Expect the ZukoForensicLog event with all fields
        vm.expectEmit(true, false, false, true);
        emit ZukoGuardian.ZukoForensicLog(
            0,                  // incidentId
            2,                  // severity
            0x06,               // rulesTriggered
            testFeedId,
            testFeedValue,
            testAnchorValue,
            1000,               // blockRangeStart
            1010,               // blockRangeEnd
            testFdcRef,
            fccSig,
            cloudSig,
            block.timestamp + 7200,   // opsPausedUntil (approx)
            block.timestamp + 3600    // transfersPausedUntil (approx)
        );

        guardian.executeInstruction(inst, fccSig, cloudSig);

        // Also verify forensic logger has the incident
        ZukoForensicLogger.Incident memory incident = forensicLogger.getIncident(0);
        assertEq(incident.severity, 2, "Severity should be HIGH");
        assertEq(incident.rulesTriggered, 0x06, "Rules should be R2+R3");
        assertEq(incident.feedId, testFeedId, "Feed ID should match");
        assertEq(incident.feedValue, testFeedValue, "Feed value should match");
        assertEq(incident.anchorValue, testAnchorValue, "Anchor value should match");
        assertEq(incident.blockRangeStart, 1000, "Block range start");
        assertEq(incident.blockRangeEnd, 1010, "Block range end");
        assertEq(incident.fdcAttestationRef, testFdcRef, "FDC ref should match");
    }

    // ── Rule 3 on-chain guard ────────────────────────────────────────────

    function test_Rule3_BurstWithoutFDCRef_Reverts() public {
        // Rule 3 (bit2 = 0x04) with fdcAttestationRef = 0 → rejected
        bytes memory inst = _buildInstruction(
            2,       // HIGH
            0x04,    // Rule 3 only
            7200,
            3600,
            bytes32(0), // NO fdc ref → should revert
            1
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _signInstruction(inst, CLOUD_PRIVATE_KEY);

        vm.expectRevert(ZukoGuardian.RedempBurstWithoutFDCMismatch.selector);
        guardian.executeInstruction(inst, fccSig, cloudSig);
    }

    function test_Rule3_BurstWithFDCRef_Succeeds() public {
        // Rule 3 with valid fdcAttestationRef → should succeed
        bytes memory inst = _buildInstruction(
            2,       // HIGH
            0x04,    // Rule 3
            7200,
            3600,
            keccak256("fdc-mismatch"), // valid FDC ref
            1
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _signInstruction(inst, CLOUD_PRIVATE_KEY);

        guardian.executeInstruction(inst, fccSig, cloudSig);
        assertEq(guardian.totalIncidents(), 1);
    }

    // ── guardianFastResume ───────────────────────────────────────────────

    function test_GuardianFastResume_ValidIncident() public {
        // First create an incident
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        guardian.executeInstruction(inst, fccSig, "");

        // Guardian multisig calls fast resume
        vm.prank(guardianMultisig);
        vm.expectEmit(true, true, false, true);
        emit ZukoGuardian.GuardianFastResume(0, guardianMultisig, block.timestamp);
        guardian.guardianFastResume(0);
    }

    function test_GuardianFastResume_InvalidIncident_Reverts() public {
        vm.prank(guardianMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.IncidentNotFound.selector, uint256(0))
        );
        guardian.guardianFastResume(0);
    }

    function test_GuardianFastResume_NonGuardian_Reverts() public {
        // Create incident first
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        guardian.executeInstruction(inst, fccSig, "");

        // Random caller tries fast resume
        vm.prank(address(0xDEAD));
        vm.expectRevert(ZukoGuardian.NotGuardian.selector);
        guardian.guardianFastResume(0);
    }

    // ── selfKill ────────────────────────────────────────────────────────

    function test_SelfKill_ByGovernance_KillsAndEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ZukoGuardian.ZukoKilled(governance, block.timestamp);
        guardian.selfKill();

        assertTrue(guardian.killed(), "Guardian should be killed");
    }

    function test_SelfKill_SubsequentInstruction_Reverts() public {
        guardian.selfKill();

        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);

        vm.expectRevert(ZukoGuardian.GuardianKilled.selector);
        guardian.executeInstruction(inst, fccSig, "");
    }

    function test_SelfKill_NonGovernance_Reverts() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(ZukoGuardian.NotGovernance.selector);
        guardian.selfKill();
    }

    // ── Pause duration capping ───────────────────────────────────────────

    function test_PauseDuration_CappedAtAssetManagerMax() public {
        // MockAM default max is 6 hours = 21600s
        // Request 10 hours = 36000s → should be capped to 21600s
        bytes memory inst = _buildInstruction(
            1,       // MEDIUM
            0x02,
            36000,   // 10 hours → should be capped to 6 hours
            0,
            bytes32(0),
            1
        );

        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        guardian.executeInstruction(inst, fccSig, "");

        // MockAM records the actual duration passed to it
        assertEq(
            mockAM.lastOpsPauseDuration(),
            21600, // 6 hours (capped)
            "Ops pause duration should be capped at AM max"
        );
    }

    // ── getLivePauseSettings ─────────────────────────────────────────────

    function test_GetLivePauseSettings() public view {
        (
            uint256 maxOps,
            uint256 maxTransfer,
            uint256 opsReset,
            /*uint256 transferReset*/
        ) = guardian.getLivePauseSettings();

        assertEq(maxOps, 21600, "Max ops pause = 6 hours");
        assertEq(maxTransfer, 21600, "Max transfer pause = 6 hours");
        assertEq(opsReset, 86400, "Ops reset = 24 hours");
    }

    // ── Multiple sequential instructions ─────────────────────────────────

    function test_MultipleInstructions_SequentialNonces() public {
        for (uint64 i = 1; i <= 5; i++) {
            bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), i);
            bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
            guardian.executeInstruction(inst, fccSig, "");
        }

        assertEq(guardian.totalIncidents(), 5, "Should have 5 incidents");
        assertEq(forensicLogger.totalIncidents(), 5, "Logger should have 5 incidents");
        assertEq(mockAM.opsPauseCallCount(), 5, "5 ops pause calls");
    }

    // ── nextNonce view ───────────────────────────────────────────────────

    function test_NextNonce_ReturnsFirstUnused() public {
        assertEq(guardian.nextNonce(), 0, "First unused nonce should be 0");

        // Use nonce 0
        bytes memory inst = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 0);
        bytes memory fccSig = _signInstruction(inst, FCC_PRIVATE_KEY);
        guardian.executeInstruction(inst, fccSig, "");

        assertEq(guardian.nextNonce(), 1, "Next unused nonce should be 1");
    }

    // ── Governance setters ───────────────────────────────────────────────

    function test_SetGuardianMultisig() public {
        address newGuardian = address(0xBEEF);
        guardian.setGuardianMultisig(newGuardian);
        assertEq(guardian.guardianMultisig(), newGuardian);
    }

    function test_SetRegisteredCodeHash() public {
        bytes32 newHash = keccak256("zuko-tee-v2.0");
        guardian.setRegisteredCodeHash(newHash);
        assertEq(guardian.registeredCodeHash(), newHash);
    }
}
