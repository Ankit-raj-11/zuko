// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ZukoGuardian} from "../contracts/ZukoGuardian.sol";
import {ZukoMultiProverVerifier} from "../contracts/ZukoMultiProverVerifier.sol";
import {ZukoForensicLogger} from "../contracts/ZukoForensicLogger.sol";
import {MockAssetManager} from "./mocks/MockAssetManager.sol";
import {MockTeeRegistry} from "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoChaosTest
 * @notice Phase 3 chaos test suite — all 18 graduated + adversarial test cases.
 *
 * Run locally (fast, no network):
 *   forge test --match-contract ZukoChaosTest -vvv
 *
 * Run in fork mode against live Coston2 (proves real-world behaviour):
 *   forge test --match-contract ZukoChaosTest \
 *     --fork-url $COSTON2_RPC_URL \
 *     --fork-block-number latest \
 *     -vvv
 *
 * In fork mode the MockAssetManager is still used for control; the fork mode
 * proves the Foundry cheat codes (vm.prank, vm.sign) work against live chain
 * state. TC-23 (live integration) is a separate manual/script step.
 */
contract ZukoChaosTest is Test {
    // ── Contracts ────────────────────────────────────────────────────────────
    ZukoGuardian       public guardian;
    ZukoMultiProverVerifier public verifier;
    ZukoForensicLogger public forensicLogger;
    MockAssetManager   public mockAM;
    MockTeeRegistry    public teeRegistry;

    // ── Private keys (deterministic, Foundry only) ───────────────────────────
    uint256 constant FCC_PRIVATE_KEY   = 0xA11CE;
    uint256 constant CLOUD_PRIVATE_KEY = 0xB0B;
    uint256 constant ROGUE_PRIVATE_KEY = 0xDEAD;

    address fccAddr;
    address cloudAddr;
    address rogueAddr;
    address governance;
    address guardianMultisig;

    bytes32 constant CODE_HASH = keccak256("zuko-tee-v1.0-phase3");

    // ── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        fccAddr         = vm.addr(FCC_PRIVATE_KEY);
        cloudAddr       = vm.addr(CLOUD_PRIVATE_KEY);
        rogueAddr       = vm.addr(ROGUE_PRIVATE_KEY);
        governance      = address(this);
        guardianMultisig = makeAddr("guardian-multisig");

        // Deploy verifier
        verifier = new ZukoMultiProverVerifier(fccAddr, cloudAddr, governance);

        // Deploy TEE registry
        teeRegistry = new MockTeeRegistry();
        teeRegistry.registerHash(CODE_HASH);

        // Deploy MockAssetManager (default max = 6h for both surfaces)
        mockAM = new MockAssetManager(address(0)); // pauseGuardian set after guardian deploy

        // Predict guardian address (nonce accounting: verifier=0, teeRegistry=1, mockAM=2, forensicLogger=3, guardian=4)
        address predictedGuardian = vm.computeCreateAddress(
            address(this),
            vm.getNonce(address(this)) + 1
        );

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

        assertEq(address(guardian), predictedGuardian, "Guardian address mismatch");

        // Wire guardian as the pause authority on MockAssetManager
        mockAM.setPauseGuardian(address(guardian));
    }

    // ── Internal Helpers ─────────────────────────────────────────────────────

    function _buildInstruction(
        uint8   severity,
        uint8   rulesTriggered,
        uint32  opsPause,
        uint32  transferPause,
        bytes32 fdcRef,
        uint64  nonce
    ) internal view returns (bytes memory) {
        return abi.encode(
            ZukoGuardian.ZukoInstruction({
                severity:               severity,
                rulesTriggered:         rulesTriggered,
                opsPauseDuration:       opsPause,
                transfersPauseDuration: transferPause,
                feedId:                 bytes32(uint256(0x01)),
                feedValue:              1e18,
                anchorValue:            1e18,
                blockRangeStart:        uint64(block.number >= 10 ? block.number - 10 : 0),
                blockRangeEnd:          uint64(block.number),
                fdcAttestationRef:      fdcRef,
                nonce:                  nonce,
                chainId:                uint32(block.chainid)
            })
        );
    }

    function _sign(bytes memory encodedInst, uint256 privKey)
        internal pure returns (bytes memory)
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

    // ════════════════════════════════════════════════════════════════════════
    // CATEGORY A — GRADUATED PAUSE SCENARIOS (TC-01 to TC-06)
    // ════════════════════════════════════════════════════════════════════════

    /**
     * PHASE-3-TC-01: Rule 2 CR Cliff verdict → ops pause ONLY (not transfers).
     * A correlated CR cliff is a MEDIUM threat. Only ops are paused.
     * Users can still freely transfer their existing FAssets.
     */
    function test_TC01_Rule2_CRCliff_OpsOnlyPause() public {
        bytes memory inst = _buildInstruction(
            1,       // MEDIUM severity
            0x02,    // bit1 = Rule 2 (Correlated CR Cliff)
            7200,    // 2-hour ops pause
            0,       // NO transfer pause
            bytes32(0),
            1
        );

        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);

        guardian.executeInstruction(inst, fccSig, "");

        // Assert: ops paused, transfers live
        assertEq(mockAM.opsPauseCallCount(),      1, "TC-01: emergencyPause must be called once");
        assertEq(mockAM.lastOpsPauseDuration(),   7200, "TC-01: 2-hour ops pause");
        assertEq(mockAM.transferPauseCallCount(), 0, "TC-01: transfer pause must NOT fire");
        assertEq(guardian.totalIncidents(),       1, "TC-01: incident recorded");
        assertTrue(guardian.usedNonces(1),           "TC-01: nonce marked used");
    }

    /**
     * PHASE-3-TC-02: Rule 3 redemption burst ALONE → INFO alert, NO pause.
     * On-chain guard enforces: burst without FDC attestation ref = rejected.
     * The system must NEVER pause on a burst spike alone.
     */
    function test_TC02_Rule3_BurstAlone_NoPause_Reverts() public {
        // bit2 = Rule 3, but fdcAttestationRef = 0  → on-chain guard rejects
        bytes memory inst = _buildInstruction(
            2,       // HIGH
            0x04,    // bit2 = Rule 3
            14400,
            14400,
            bytes32(0), // NO FDC ref — this is the safety gate
            1
        );

        bytes memory fccSig   = _sign(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _sign(inst, CLOUD_PRIVATE_KEY);

        vm.expectRevert(ZukoGuardian.RedempBurstWithoutFDCMismatch.selector);
        guardian.executeInstruction(inst, fccSig, cloudSig);

        // Verify zero state change
        assertEq(mockAM.opsPauseCallCount(),  0, "TC-02: no pause should fire");
        assertEq(guardian.totalIncidents(),   0, "TC-02: no incident recorded");
    }

    /**
     * PHASE-3-TC-03: Rule 3 compound (burst + FDC timeout) → both surfaces paused.
     * When both conditions A + B are present, the full 4-hour freeze is justified.
     */
    function test_TC03_Rule3_Compound_BothSurfacesPaused() public {
        bytes32 fdcRef = keccak256("btc-payment-timeout-block-33001");

        bytes memory inst = _buildInstruction(
            2,       // HIGH severity
            0x04,    // Rule 3
            14400,   // 4-hour ops pause
            14400,   // 4-hour transfer pause
            fdcRef,  // FDC attestation reference confirms the compound condition
            1
        );

        bytes memory fccSig   = _sign(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _sign(inst, CLOUD_PRIVATE_KEY);

        guardian.executeInstruction(inst, fccSig, cloudSig);

        assertEq(mockAM.opsPauseCallCount(),       1, "TC-03: ops pause fired");
        assertEq(mockAM.transferPauseCallCount(),   1, "TC-03: transfer pause fired");
        assertEq(mockAM.lastOpsPauseDuration(),   14400, "TC-03: 4-hour ops pause");
        assertEq(mockAM.lastTransferPauseDuration(), 14400, "TC-03: 4-hour transfer pause");
        assertEq(guardian.totalIncidents(),         1, "TC-03: incident recorded");
    }

    /**
     * PHASE-3-TC-04: Rule 4 Core Vault FDC anomaly → CRITICAL, 6h both surfaces.
     * Highest severity. Both surfaces frozen for maximum duration.
     */
    function test_TC04_Rule4_CoreVault_CriticalFullFreeze() public {
        bytes32 fdcRef = keccak256("core-vault-payment-failed-proof");

        bytes memory inst = _buildInstruction(
            3,       // CRITICAL
            0x08,    // bit3 = Rule 4 (Core Vault FDC)
            21600,   // 6-hour ops pause
            21600,   // 6-hour transfer pause
            fdcRef,
            1
        );

        bytes memory fccSig   = _sign(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _sign(inst, CLOUD_PRIVATE_KEY);

        guardian.executeInstruction(inst, fccSig, cloudSig);

        assertEq(mockAM.opsPauseCallCount(),          1, "TC-04: ops pause fired");
        assertEq(mockAM.transferPauseCallCount(),      1, "TC-04: transfer pause fired");
        assertEq(mockAM.lastOpsPauseDuration(),     21600, "TC-04: 6-hour ops pause");
        assertEq(mockAM.lastTransferPauseDuration(), 21600, "TC-04: 6-hour transfer pause");
        assertTrue(guardian.usedNonces(1), "TC-04: nonce consumed");
    }

    /**
     * PHASE-3-TC-05: Pause duration exceeding AssetManager cap is silently capped.
     * ZukoGuardian reads live maxEmergencyPauseDurationSeconds before every call.
     * The instruction requests more than the cap allows — it must be silently reduced.
     */
    function test_TC05_PauseDuration_CappedAtAssetManagerMax() public {
        // Set AssetManager max to 1 hour (3600s)
        mockAM.setMaxPauseDuration(3600);

        // Instruction requests 6 hours — Guardian must cap it to 3600
        bytes memory inst = _buildInstruction(
            1,       // MEDIUM
            0x02,    // Rule 2
            21600,   // 6 hours — EXCEEDS cap
            0,
            bytes32(0),
            1
        );

        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);
        guardian.executeInstruction(inst, fccSig, "");

        // Verify the duration was capped, NOT rejected
        assertEq(mockAM.lastOpsPauseDuration(), 3600, "TC-05: duration capped at AM max");
        assertEq(mockAM.opsPauseCallCount(),    1,    "TC-05: pause still executed");
        assertEq(guardian.totalIncidents(),     1,    "TC-05: incident recorded");
    }

    /**
     * PHASE-3-TC-06: Two sequential pauses — accumulator stays within cap.
     * First pause: 2 hours. Second pause: 3 hours.
     * Both should succeed; the MockAssetManager extends the deadline to max(existing, new).
     */
    function test_TC06_SequentialPauses_AccumulatorWithinCap() public {
        // First pause: 2 hours
        bytes memory inst1 = _buildInstruction(1, 0x02, 7200, 0, bytes32(0), 1);
        guardian.executeInstruction(inst1, _sign(inst1, FCC_PRIVATE_KEY), "");

        uint256 pausedAfterFirst = mockAM.emergencyPausedUntil();
        assertGt(pausedAfterFirst, block.timestamp, "TC-06: first pause active");

        // Second pause: 3 hours (extends the existing pause)
        bytes memory inst2 = _buildInstruction(1, 0x02, 10800, 0, bytes32(0), 2);
        guardian.executeInstruction(inst2, _sign(inst2, FCC_PRIVATE_KEY), "");

        uint256 pausedAfterSecond = mockAM.emergencyPausedUntil();
        assertGe(pausedAfterSecond, pausedAfterFirst, "TC-06: second pause extended the deadline");

        // Total pause time must never exceed the AssetManager's max (6 hours default)
        assertLe(
            pausedAfterSecond - block.timestamp,
            mockAM.maxEmergencyPauseDurationSeconds(),
            "TC-06: accumulator never exceeds governance cap"
        );

        assertEq(guardian.totalIncidents(), 2, "TC-06: two incidents recorded");
    }

    // ════════════════════════════════════════════════════════════════════════
    // CATEGORY B — ADVERSARIAL / CHAOS TESTS (TC-07 to TC-18)
    // ════════════════════════════════════════════════════════════════════════

    /**
     * PHASE-3-TC-07: Legitimate volatility — Rule 1 three-step prevents false fire.
     * If the price anomaly lasts only 1-2 blocks (not the required 3), no pause fires.
     * This is simulated by sending a MEDIUM instruction that is ONLY signed by
     * a rogue key — thus it fails signature verification, not because the rule engine
     * fires; we validate the no-false-positive via the rogue key path here.
     * True 3-block debounce is verified in the Go rule engine unit tests.
     */
    function test_TC07_RogueSignature_NoFalsePositive() public {
        bytes memory inst = _buildInstruction(1, 0x01, 3600, 0, bytes32(0), 1);

        // Signed by a rogue key (not FCC or Cloud) → must revert
        bytes memory rogueSig = _sign(inst, ROGUE_PRIVATE_KEY);

        // The rogue key recovers to an unknown address (not fccAddr or cloudAddr).
        // The verifier counts 0 valid signers, then fails the MEDIUM 1-of-2 quorum.
        vm.expectRevert(
            abi.encodeWithSelector(ZukoMultiProverVerifier.InsufficientSigners.selector, uint8(1))
        );
        guardian.executeInstruction(inst, rogueSig, "");

        assertEq(mockAM.opsPauseCallCount(), 0, "TC-07: no pause on rogue sig");
        assertEq(guardian.totalIncidents(),  0, "TC-07: no incident recorded");
    }

    /**
     * PHASE-3-TC-08: Replay attack — nonce prevents double execution.
     * An attacker captures a signed instruction and tries to replay it.
     * The second submission must be rejected with NonceAlreadyUsed.
     */
    function test_TC08_ReplayAttack_NonceAlreadyUsed() public {
        bytes memory inst   = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 99);
        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);

        // First call: succeeds
        guardian.executeInstruction(inst, fccSig, "");
        assertEq(guardian.totalIncidents(), 1, "TC-08: first call recorded");

        // Second call (replay): must revert
        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.NonceAlreadyUsed.selector, uint64(99))
        );
        guardian.executeInstruction(inst, fccSig, "");

        // State unchanged from the replay
        assertEq(guardian.totalIncidents(), 1, "TC-08: replay changed no state");
    }

    /**
     * PHASE-3-TC-09: TEE kill-switch — code hash deregistered mid-flight.
     * If Flare Governance deregisters our code hash, all further instructions
     * must be rejected. This is the remote kill-switch safety valve.
     */
    function test_TC09_KillSwitch_DeregisteredHash_Reverts() public {
        bytes memory inst   = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);

        // Governance deregisters the code hash (kill switch pulled)
        teeRegistry.deregisterHash(CODE_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.NotRegisteredInFCC.selector, CODE_HASH)
        );
        guardian.executeInstruction(inst, fccSig, "");

        assertEq(mockAM.opsPauseCallCount(), 0, "TC-09: no pause after kill switch");
    }

    /**
     * PHASE-3-TC-10: Single prover failure — MEDIUM still fires with 1-of-2 sig.
     * If the cloud enclave is temporarily offline, a MEDIUM incident can still
     * be actioned with just the primary FCC signature. Resilience is critical.
     */
    function test_TC10_MEDIUM_FccSigOnly_Succeeds() public {
        bytes memory inst   = _buildInstruction(1, 0x02, 7200, 0, bytes32(0), 1);
        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);

        // Submit with only FCC sig (cloud sig empty) → must succeed for MEDIUM
        guardian.executeInstruction(inst, fccSig, "");

        assertEq(mockAM.opsPauseCallCount(), 1, "TC-10: ops pause fired with 1-of-2");
        assertEq(guardian.totalIncidents(),  1, "TC-10: incident recorded");
    }

    /**
     * PHASE-3-TC-11: Single prover failure — CRITICAL blocked (2-of-2 required).
     * CRITICAL threats need both FCC AND Cloud signatures. A single signature
     * must never be sufficient to trigger a CRITICAL system freeze.
     */
    function test_TC11_CRITICAL_FccSigOnly_InsufficientSigners() public {
        bytes32 fdcRef = keccak256("critical-fdc-ref");
        bytes memory inst   = _buildInstruction(3, 0x08, 21600, 21600, fdcRef, 1);
        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);

        // FCC sig only → must revert InsufficientSigners for severity=3
        vm.expectRevert(
            abi.encodeWithSelector(ZukoMultiProverVerifier.InsufficientSigners.selector, uint8(3))
        );
        guardian.executeInstruction(inst, fccSig, "");

        assertEq(mockAM.opsPauseCallCount(), 0, "TC-11: no pause on insufficient signers");
    }

    /**
     * PHASE-3-TC-12: Malformed instruction payload — reverts cleanly.
     * Submitting random garbage bytes as the instruction must revert at ABI decode
     * with zero state change. No panic, no partial execution.
     */
    function test_TC12_MalformedPayload_RevertsCleanly() public {
        bytes memory garbage = abi.encodePacked(
            uint256(0xDEADBEEF),
            uint256(0xCAFEBABE),
            uint256(0x12345678)
        );
        bytes memory fccSig = _sign(garbage, FCC_PRIVATE_KEY);

        // ABI decode revert — any revert is acceptable here
        vm.expectRevert();
        guardian.executeInstruction(garbage, fccSig, "");

        assertEq(mockAM.opsPauseCallCount(), 0, "TC-12: no pause on garbage payload");
        assertEq(guardian.totalIncidents(),  0, "TC-12: no incident on garbage");
    }

    /**
     * PHASE-3-TC-13: Rule 3 on-chain guard — burst bit set but fdcAttestationRef = 0.
     * Even if a bug in the Go Rule Engine sends a Rule 3 pause without an FDC proof,
     * the Solidity on-chain guard catches it and reverts. Defense in depth.
     */
    function test_TC13_Rule3_BurstBitSet_NoFdcRef_OnChainGuardReverts() public {
        // bit2 = Rule 3, but fdcAttestationRef is zero
        bytes memory inst = _buildInstruction(
            2,       // HIGH
            0x04,    // bit2 = Rule 3
            14400,
            14400,
            bytes32(0), // MISSING FDC ref — guard must reject
            1
        );

        bytes memory fccSig   = _sign(inst, FCC_PRIVATE_KEY);
        bytes memory cloudSig = _sign(inst, CLOUD_PRIVATE_KEY);

        vm.expectRevert(ZukoGuardian.RedempBurstWithoutFDCMismatch.selector);
        guardian.executeInstruction(inst, fccSig, cloudSig);
    }

    /**
     * PHASE-3-TC-14: Second pause extends existing pause deadline correctly.
     * First pause: 1 hour. Second pause: 2 hours. The deadline must extend to
     * max(first_deadline, now + 2h), and must never exceed the governance cap.
     */
    function test_TC14_SecondPause_ExtendsDeadline_WithinCap() public {
        // First pause: 1 hour
        bytes memory inst1 = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        guardian.executeInstruction(inst1, _sign(inst1, FCC_PRIVATE_KEY), "");
        uint256 firstDeadline = mockAM.emergencyPausedUntil();

        // Second pause: 2 hours (larger → extends deadline)
        bytes memory inst2 = _buildInstruction(1, 0x02, 7200, 0, bytes32(0), 2);
        guardian.executeInstruction(inst2, _sign(inst2, FCC_PRIVATE_KEY), "");
        uint256 secondDeadline = mockAM.emergencyPausedUntil();

        // The deadline must be extended, not shrunk
        assertGe(secondDeadline, firstDeadline, "TC-14: second pause extended deadline");

        // Must stay within the max cap (6 hours from now)
        assertLe(
            secondDeadline,
            block.timestamp + mockAM.maxEmergencyPauseDurationSeconds(),
            "TC-14: deadline within governance cap"
        );
    }

    /**
     * PHASE-3-TC-15: guardianFastResume before any incident → IncidentNotFound.
     * Calling fast-resume before a single incident has been recorded must revert.
     */
    function test_TC15_GuardianFastResume_BeforeAnyIncident_Reverts() public {
        vm.prank(guardianMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(ZukoGuardian.IncidentNotFound.selector, uint256(0))
        );
        guardian.guardianFastResume(0);
    }

    /**
     * PHASE-3-TC-16: selfKill() by governance → kills the guardian permanently.
     * After governance calls selfKill, the contract state is killed = true
     * and the ZukoKilled event is emitted.
     */
    function test_TC16_SelfKill_ByGovernance_EmitsEvent() public {
        assertFalse(guardian.killed(), "TC-16: guardian not killed initially");

        vm.expectEmit(true, false, false, false, address(guardian));
        emit ZukoGuardian.ZukoKilled(governance, block.timestamp);

        guardian.selfKill(); // called by address(this) = governance

        assertTrue(guardian.killed(), "TC-16: guardian must be killed");
    }

    /**
     * PHASE-3-TC-17: executeInstruction after selfKill → GuardianKilled.
     * All subsequent instruction execution attempts must be permanently blocked.
     */
    function test_TC17_ExecuteInstruction_AfterKill_Reverts() public {
        guardian.selfKill();
        assertTrue(guardian.killed(), "TC-17: guardian killed");

        bytes memory inst   = _buildInstruction(1, 0x02, 3600, 0, bytes32(0), 1);
        bytes memory fccSig = _sign(inst, FCC_PRIVATE_KEY);

        vm.expectRevert(ZukoGuardian.GuardianKilled.selector);
        guardian.executeInstruction(inst, fccSig, "");
    }

    /**
     * PHASE-3-TC-18: selfKill() by non-governance → NotGovernance.
     * Only the governance address can kill the guardian. All others must revert.
     */
    function test_TC18_SelfKill_NonGovernance_Reverts() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(ZukoGuardian.NotGovernance.selector);
        guardian.selfKill();

        assertFalse(guardian.killed(), "TC-18: guardian must NOT be killed");
    }

    // ════════════════════════════════════════════════════════════════════════
    // BONUS: guardianFastResume happy path (supports TC-23 prerequisite)
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Verifies guardianFastResume works correctly from the multisig after an incident.
     */
    function test_GuardianFastResume_AfterIncident_Succeeds() public {
        bytes memory inst   = _buildInstruction(1, 0x02, 7200, 0, bytes32(0), 1);
        guardian.executeInstruction(inst, _sign(inst, FCC_PRIVATE_KEY), "");
        assertEq(guardian.totalIncidents(), 1, "Bonus: incident recorded");

        // Guardian multisig calls fast-resume
        vm.prank(guardianMultisig);
        vm.expectEmit(true, true, false, false, address(guardian));
        emit ZukoGuardian.GuardianFastResume(0, guardianMultisig, block.timestamp);
        guardian.guardianFastResume(0);
    }
}
