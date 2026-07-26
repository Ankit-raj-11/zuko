// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IZukoGuardian
 * @notice Interface for the ZukoGuardian contract — InstructionSender-compatible
 *         FAssets circuit breaker.
 *
 *  MULTI-PROVER SIGNATURE REQUIREMENTS:
 *    MEDIUM severity (1):  1-of-2 sigs (FCC OR cloud)
 *    HIGH severity (2):    2-of-2 sigs (FCC AND cloud)
 *    CRITICAL severity (3):2-of-2 sigs (FCC AND cloud) — NO pre-execution delay
 *
 *  FORENSIC LOG:
 *    Every executeInstruction emits ZukoForensicLog with full rule context,
 *    feed values, block range, and both TEE attestation signatures.
 */
interface IZukoGuardian {

    // ── Structs ───────────────────────────────────────────────────────────

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

    // ── Events ────────────────────────────────────────────────────────────

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

    // ── Errors ────────────────────────────────────────────────────────────

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

    // ── Core functions ────────────────────────────────────────────────────

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
