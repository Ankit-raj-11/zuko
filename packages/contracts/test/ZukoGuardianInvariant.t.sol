// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ZukoGuardian} from "../contracts/ZukoGuardian.sol";
import {ZukoMultiProverVerifier} from "../contracts/ZukoMultiProverVerifier.sol";
import {ZukoForensicLogger} from "../contracts/ZukoForensicLogger.sol";
import {MockAssetManager} from "./mocks/MockAssetManager.sol";
import {MockTeeRegistry} from "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoGuardianInvariant
 * @notice Phase 3 stateful invariant (fuzz) tests — TC-19 to TC-22.
 *
 *   forge test --match-contract ZukoGuardianInvariant --fuzz-runs 1000 -vvv
 *
 * Foundry's invariant engine randomly calls the exposed handler functions
 * below and asserts the invariants after every call sequence.
 */
contract ZukoGuardianInvariant is Test {
    // ── Contracts ─────────────────────────────────────────────────────────
    ZukoGuardian            public guardian;
    ZukoMultiProverVerifier public verifier;
    ZukoForensicLogger      public forensicLogger;
    MockAssetManager        public mockAM;
    MockTeeRegistry         public teeRegistry;

    // Handler that the fuzzer calls
    ZukoGuardianHandler public handler;

    function setUp() public {
        uint256 fccKey   = 0xA11CE;
        uint256 cloudKey = 0xB0B;

        address fccAddr   = vm.addr(fccKey);
        address cloudAddr = vm.addr(cloudKey);
        address governance = address(this);
        address multisig   = makeAddr("guardian-multisig");

        bytes32 codeHash = keccak256("zuko-invariant-v1");

        verifier   = new ZukoMultiProverVerifier(fccAddr, cloudAddr, governance);
        teeRegistry = new MockTeeRegistry();
        teeRegistry.registerHash(codeHash);

        mockAM = new MockAssetManager(address(0));

        address predicted = vm.computeCreateAddress(
            address(this),
            vm.getNonce(address(this)) + 1
        );
        forensicLogger = new ZukoForensicLogger(predicted);

        guardian = new ZukoGuardian(
            address(mockAM),
            address(verifier),
            address(teeRegistry),
            address(forensicLogger),
            governance,
            multisig,
            codeHash
        );

        mockAM.setPauseGuardian(address(guardian));

        // Deploy the handler — fuzzer will call methods on it
        handler = new ZukoGuardianHandler(
            guardian, mockAM, fccKey, cloudKey
        );

        // Target only the handler for fuzzing
        targetContract(address(handler));
    }

    // ════════════════════════════════════════════════════════════════════════
    // PHASE-3-TC-19: Pause duration never exceeds governance cap
    // ════════════════════════════════════════════════════════════════════════
    function invariant_PauseDurationNeverExceedsCap() public view {
        uint256 opsDeadline      = mockAM.emergencyPausedUntil();
        uint256 transferDeadline = mockAM.transfersEmergencyPausedUntil();
        uint256 opsMax           = mockAM.maxEmergencyPauseDurationSeconds();
        uint256 transferMax      = mockAM.maxTransferPauseDurationSeconds();

        if (opsDeadline > block.timestamp) {
            assertLe(
                opsDeadline - block.timestamp,
                opsMax,
                "TC-19: ops pause deadline exceeds governance max"
            );
        }
        if (transferDeadline > block.timestamp) {
            assertLe(
                transferDeadline - block.timestamp,
                transferMax,
                "TC-19: transfer pause deadline exceeds governance max"
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // PHASE-3-TC-20: Nonce is strictly monotonically increasing
    // Each nonce in usedNonces[n] == true means n was submitted exactly once.
    // The total incidents count == total unique nonces consumed.
    // ════════════════════════════════════════════════════════════════════════
    function invariant_NonceIsMonotonic() public view {
        uint256 incidents = guardian.totalIncidents();
        // All nonces from 1..incidents must be consumed, none skipped
        for (uint64 i = 1; i <= uint64(incidents); i++) {
            assertTrue(
                guardian.usedNonces(i),
                "TC-20: nonce not marked used for incident"
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // PHASE-3-TC-21: Pause call count never exceeds valid instruction count
    // Each valid instruction triggers AT MOST one ops pause and one transfer pause.
    // ════════════════════════════════════════════════════════════════════════
    function invariant_PauseCallsMatchInstructions() public view {
        uint256 incidents = guardian.totalIncidents();
        assertLe(
            mockAM.opsPauseCallCount(),
            incidents,
            "TC-21: ops pause calls exceeded incident count"
        );
        assertLe(
            mockAM.transferPauseCallCount(),
            incidents,
            "TC-21: transfer pause calls exceeded incident count"
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    // PHASE-3-TC-22: Incident count matches successful pause executions
    // ForensicLogger incidents == ZukoGuardian incidents (logged on every exec)
    // ════════════════════════════════════════════════════════════════════════
    function invariant_IncidentCountMatchesForensicLogger() public view {
        assertEq(
            guardian.totalIncidents(),
            forensicLogger.totalIncidents(),
            "TC-22: guardian and forensicLogger incident counts must match"
        );
    }
}

/**
 * @title ZukoGuardianHandler
 * @notice Stateful handler that the Foundry fuzzer calls to drive ZukoGuardian.
 * Maintains a nonce counter and always signs with real ECDSA keys so that
 * all invariant checks operate on valid, accepted instructions.
 */
contract ZukoGuardianHandler is Test {
    ZukoGuardian    public guardian;
    MockAssetManager public mockAM;

    uint256 immutable fccKey;
    uint256 immutable cloudKey;

    uint64 public nextNonce = 1;

    constructor(
        ZukoGuardian _guardian,
        MockAssetManager _mockAM,
        uint256 _fccKey,
        uint256 _cloudKey
    ) {
        guardian  = _guardian;
        mockAM    = _mockAM;
        fccKey    = _fccKey;
        cloudKey  = _cloudKey;
    }

    // ── Handler: submit a MEDIUM instruction (1-of-2) ─────────────────────
    function submitMediumInstruction(uint32 opsDuration) external {
        // Clamp to valid range to avoid trivial reverts unrelated to invariants
        opsDuration = uint32(bound(opsDuration, 60, 6 hours));

        bytes memory inst = _build(1, 0x02, opsDuration, 0, bytes32(0));
        bytes memory fccSig = _sign(inst, fccKey);

        try guardian.executeInstruction(inst, fccSig, "") {
            nextNonce++;
        } catch { /* acceptable — invariants still checked */ }
    }

    // ── Handler: submit a HIGH instruction (2-of-2) with FDC ref ──────────
    function submitHighInstruction(uint32 opsDuration, uint32 transferDuration) external {
        opsDuration      = uint32(bound(opsDuration,      60, 6 hours));
        transferDuration = uint32(bound(transferDuration, 60, 6 hours));

        bytes32 fdcRef = keccak256(abi.encode("fdc-ref", nextNonce));
        bytes memory inst     = _build(2, 0x04, opsDuration, transferDuration, fdcRef);
        bytes memory fccSig   = _sign(inst, fccKey);
        bytes memory cloudSig = _sign(inst, cloudKey);

        try guardian.executeInstruction(inst, fccSig, cloudSig) {
            nextNonce++;
        } catch { /* acceptable */ }
    }

    // ── Handler: submit a CRITICAL instruction (2-of-2) ───────────────────
    function submitCriticalInstruction() external {
        bytes32 fdcRef    = keccak256(abi.encode("critical-fdc", nextNonce));
        bytes memory inst     = _build(3, 0x08, 21600, 21600, fdcRef);
        bytes memory fccSig   = _sign(inst, fccKey);
        bytes memory cloudSig = _sign(inst, cloudKey);

        try guardian.executeInstruction(inst, fccSig, cloudSig) {
            nextNonce++;
        } catch { /* acceptable */ }
    }

    // ── Internal helpers ──────────────────────────────────────────────────

    function _build(
        uint8   severity,
        uint8   rulesTriggered,
        uint32  opsPause,
        uint32  transferPause,
        bytes32 fdcRef
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
                nonce:                  nextNonce,
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
}
