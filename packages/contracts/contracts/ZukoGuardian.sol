// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ZukoMultiProverVerifier} from "./ZukoMultiProverVerifier.sol";
import {ZukoForensicLogger} from "./ZukoForensicLogger.sol";

/**
 * @title ZukoGuardian
 * @notice InstructionSender-compatible FAssets circuit breaker.
 *
 *  PAUSE MECHANISM (CRITICAL):
 *  AssetManager uses TWO separate duration-based pause facets:
 *    1. EmergencyPauseFacet.emergencyPause(duration) — halts ops
 *    2. EmergencyPauseTransfersFacet.emergencyPauseTransfers(duration) — halts transfers
 *  Zuko reads maxEmergencyPauseDurationSeconds and maxTransferPauseDurationSeconds
 *  LIVE from AssetManagerSettings before every executeInstruction call.
 *  These values are NEVER cached. Governance may change them at any time.
 *
 *  MULTI-PROVER:
 *  MEDIUM severity (1):  1-of-2 sigs (FCC OR cloud)
 *  HIGH severity (2):    2-of-2 sigs (FCC AND cloud)
 *  CRITICAL severity (3):2-of-2 sigs (FCC AND cloud) — NO pre-execution delay
 *
 *  FORENSIC LOG:
 *  Every executeInstruction emits ZukoForensicLog with full rule context,
 *  feed values, block range, and both TEE attestation signatures.
 *  This log is the primary input for guardianFastResume review.
 */
contract ZukoGuardian {
    // ── Types ─────────────────────────────────────────────────────────────

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

    event GuardianFastResume(
        uint256 indexed incidentId,
        address indexed guardian,
        uint256 ts
    );

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

    // ── Immutables & State ────────────────────────────────────────────────

    address public immutable assetManager;
    ZukoMultiProverVerifier public immutable verifier;
    address public immutable teeRegistry;
    ZukoForensicLogger public immutable forensicLogger;

    address public governance;
    address public guardianMultisig;
    bytes32 public registeredCodeHash;
    bool public killed;
    uint256 public totalIncidents;

    mapping(uint64 => bool) public usedNonces;
    mapping(uint256 => ZukoInstruction) public incidents;

    // ── Constructor ───────────────────────────────────────────────────────

    constructor(
        address _assetManager,
        address _verifier,
        address _teeRegistry,
        address _forensicLogger,
        address _governance,
        address _guardianMultisig,
        bytes32 _registeredCodeHash
    ) {
        assetManager = _assetManager;
        verifier = ZukoMultiProverVerifier(_verifier);
        teeRegistry = _teeRegistry;
        forensicLogger = ZukoForensicLogger(_forensicLogger);
        governance = _governance;
        guardianMultisig = _guardianMultisig;
        registeredCodeHash = _registeredCodeHash;
    }

    // ── Modifiers ─────────────────────────────────────────────────────────

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardianMultisig) revert NotGuardian();
        _;
    }

    modifier notKilled() {
        if (killed) revert GuardianKilled();
        _;
    }

    // ── Core Functions ────────────────────────────────────────────────────

    /**
     * @notice Execute a signed instruction from the TEE enclaves.
     * @dev Split into internal helpers to avoid stack-too-deep.
     */
    function executeInstruction(
        bytes calldata encodedInstruction,
        bytes calldata fccSignature,
        bytes calldata cloudSignature
    ) external notKilled {
        ZukoInstruction memory inst = abi.decode(encodedInstruction, (ZukoInstruction));

        // Validate: chainId, nonce, TEE registry, Rule 3 guard, signatures
        _validateInstruction(inst, encodedInstruction, fccSignature, cloudSignature);

        // Execute pauses and emit forensic log
        _executePausesAndLog(inst, fccSignature, cloudSignature);
    }

    // ── Internal: Validation ──────────────────────────────────────────────

    function _validateInstruction(
        ZukoInstruction memory inst,
        bytes calldata encodedInstruction,
        bytes calldata fccSignature,
        bytes calldata cloudSignature
    ) internal {
        // 1. Chain ID check
        if (inst.chainId != uint32(block.chainid)) {
            revert InvalidChainId(uint32(block.chainid), inst.chainId);
        }

        // 2. Nonce replay protection
        if (usedNonces[inst.nonce]) {
            revert NonceAlreadyUsed(inst.nonce);
        }
        usedNonces[inst.nonce] = true;

        // 3. TeeExtensionRegistry code hash verification (FCC kill-switch)
        _checkTeeRegistration();

        // 4. Rule 3 on-chain guard: burst without FDC ref is rejected
        if ((inst.rulesTriggered & 0x04) != 0 && inst.fdcAttestationRef == bytes32(0)) {
            revert RedempBurstWithoutFDCMismatch();
        }

        // 5. Multi-prover signature verification
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(encodedInstruction)
            )
        );
        verifier.verify(digest, inst.severity, fccSignature, cloudSignature);
    }

    function _checkTeeRegistration() internal view {
        (bool regSuccess, bytes memory regResult) = teeRegistry.staticcall(
            abi.encodeWithSignature("isHashRegistered(bytes32)", registeredCodeHash)
        );
        if (!regSuccess || !abi.decode(regResult, (bool))) {
            revert NotRegisteredInFCC(registeredCodeHash);
        }
    }

    // ── Internal: Execute Pauses & Log ────────────────────────────────────

    function _executePausesAndLog(
        ZukoInstruction memory inst,
        bytes calldata fccSignature,
        bytes calldata cloudSignature
    ) internal {
        // Read live pause settings
        uint256 maxOpsDuration = _readUint256(assetManager, "maxEmergencyPauseDurationSeconds()");
        uint256 maxTransferDuration = _readUint256(assetManager, "maxTransferPauseDurationSeconds()");

        // Cap durations (silently capped, not reverted)
        uint256 opsDuration = inst.opsPauseDuration;
        if (opsDuration > maxOpsDuration) opsDuration = maxOpsDuration;

        uint256 transferDuration = inst.transfersPauseDuration;
        if (transferDuration > maxTransferDuration) transferDuration = maxTransferDuration;

        // Execute pauses
        uint256 opsPausedUntil = _executePause(opsDuration, "emergencyPause(uint256)", "emergencyPausedUntil()");
        uint256 transfersPausedUntil = _executePause(transferDuration, "emergencyPauseTransfers(uint256)", "transfersEmergencyPausedUntil()");

        // Record incident
        uint256 incidentId = totalIncidents++;
        incidents[incidentId] = inst;

        // Log to ForensicLogger
        _logToForensicLogger(inst, fccSignature, cloudSignature);

        // Emit ZukoForensicLog event
        _emitForensicLog(incidentId, inst, fccSignature, cloudSignature, opsPausedUntil, transfersPausedUntil);
    }

    function _executePause(
        uint256 duration,
        string memory pauseSig,
        string memory readSig
    ) internal returns (uint256 pausedUntil) {
        if (duration == 0) return 0;

        (bool success,) = assetManager.call(
            abi.encodeWithSignature(pauseSig, duration)
        );
        if (success) {
            pausedUntil = _readUint256(assetManager, readSig);
        }
    }

    function _logToForensicLogger(
        ZukoInstruction memory inst,
        bytes calldata fccSignature,
        bytes calldata cloudSignature
    ) internal {
        forensicLogger.logIncident(
            inst.severity,
            inst.rulesTriggered,
            inst.feedId,
            inst.feedValue,
            inst.anchorValue,
            inst.blockRangeStart,
            inst.blockRangeEnd,
            inst.fdcAttestationRef,
            fccSignature,
            cloudSignature
        );
    }

    function _emitForensicLog(
        uint256 incidentId,
        ZukoInstruction memory inst,
        bytes calldata fccSignature,
        bytes calldata cloudSignature,
        uint256 opsPausedUntil,
        uint256 transfersPausedUntil
    ) internal {
        emit ZukoForensicLog(
            incidentId,
            inst.severity,
            inst.rulesTriggered,
            inst.feedId,
            inst.feedValue,
            inst.anchorValue,
            inst.blockRangeStart,
            inst.blockRangeEnd,
            inst.fdcAttestationRef,
            fccSignature,
            cloudSignature,
            opsPausedUntil,
            transfersPausedUntil
        );
    }

    // ── Guardian Fast Resume ──────────────────────────────────────────────

    function guardianFastResume(uint256 incidentId) external onlyGuardian {
        if (incidentId >= totalIncidents) revert IncidentNotFound(incidentId);
        emit GuardianFastResume(incidentId, msg.sender, block.timestamp);
    }

    // ── Self Kill ─────────────────────────────────────────────────────────

    function selfKill() external onlyGovernance {
        killed = true;
        emit ZukoKilled(msg.sender, block.timestamp);
    }

    // ── View Functions ────────────────────────────────────────────────────

    function getLivePauseSettings()
        external
        view
        returns (
            uint256 maxOpsDuration,
            uint256 maxTransferDuration,
            uint256 opsResetAfter,
            uint256 transferResetAfter
        )
    {
        maxOpsDuration = _readUint256(assetManager, "maxEmergencyPauseDurationSeconds()");
        maxTransferDuration = _readUint256(assetManager, "maxTransferPauseDurationSeconds()");
        opsResetAfter = _readUint256(assetManager, "emergencyPauseDurationResetAfterSeconds()");
        // transferResetAfter may not exist on all AssetManager versions
        (bool success, bytes memory data) = assetManager.staticcall(
            abi.encodeWithSignature("transferPauseDurationResetAfterSeconds()")
        );
        if (success && data.length >= 32) {
            transferResetAfter = abi.decode(data, (uint256));
        }
    }

    function nextNonce() external view returns (uint64) {
        for (uint64 i = 0; i < type(uint64).max; i++) {
            if (!usedNonces[i]) return i;
        }
        return 0;
    }

    // ── Governance Setters ────────────────────────────────────────────────

    function setGuardianMultisig(address _guardian) external onlyGovernance {
        guardianMultisig = _guardian;
    }

    function setRegisteredCodeHash(bytes32 _codeHash) external onlyGovernance {
        registeredCodeHash = _codeHash;
    }

    function transferGovernance(address _newGov) external onlyGovernance {
        governance = _newGov;
    }

    // ── Internal Helpers ──────────────────────────────────────────────────

    function _readUint256(address target, string memory sig)
        internal
        view
        returns (uint256 value)
    {
        (bool success, bytes memory data) = target.staticcall(
            abi.encodeWithSignature(sig)
        );
        require(success && data.length >= 32, "ZukoGuardian: staticcall failed");
        value = abi.decode(data, (uint256));
    }
}
