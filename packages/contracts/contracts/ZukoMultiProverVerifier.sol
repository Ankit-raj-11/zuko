// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ZukoMultiProverVerifier
 * @notice Verifies EIP-712 / ECDSA signatures from FCC primary enclave signer
 *         and secondary Cloud enclave signer.
 *
 *  THRESHOLD ENFORCEMENT:
 *    MEDIUM severity (1):   1-of-2 signatures (FCC OR Cloud)
 *    HIGH severity (2):     2-of-2 signatures (FCC AND Cloud)
 *    CRITICAL severity (3): 2-of-2 signatures (FCC AND Cloud)
 *
 *  Signer addresses are set at deploy time and can be rotated by governance.
 *  Zero-length signature bytes are treated as "not provided".
 */
contract ZukoMultiProverVerifier {
    // ── State ─────────────────────────────────────────────────────────────
    address public fccSigner;
    address public cloudSigner;
    address public governance;

    // ── Events ────────────────────────────────────────────────────────────
    event FccSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event CloudSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);

    // ── Errors ────────────────────────────────────────────────────────────
    error NotGovernance();
    error ZeroAddress();
    error InvalidSignature();
    error InsufficientSigners(uint8 severity);

    // ── Modifiers ─────────────────────────────────────────────────────────
    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────
    constructor(
        address _fccSigner,
        address _cloudSigner,
        address _governance
    ) {
        if (_governance == address(0)) revert ZeroAddress();
        fccSigner = _fccSigner;
        cloudSigner = _cloudSigner;
        governance = _governance;
    }

    // ── Core Verification ─────────────────────────────────────────────────

    /**
     * @notice Verify that the provided signatures meet the threshold for the
     *         given severity level.
     * @param digest      The EIP-191 eth_sign prefixed hash of the instruction payload
     * @param severity    1=MEDIUM, 2=HIGH, 3=CRITICAL
     * @param fccSig      Signature from FCC enclave (empty bytes = not provided)
     * @param cloudSig    Signature from Cloud enclave (empty bytes = not provided)
     * @return fccValid   True if FCC signature is valid
     * @return cloudValid True if Cloud signature is valid
     */
    function verify(
        bytes32 digest,
        uint8 severity,
        bytes calldata fccSig,
        bytes calldata cloudSig
    ) external view returns (bool fccValid, bool cloudValid) {
        fccValid = _isValidSignature(digest, fccSig, fccSigner);
        cloudValid = _isValidSignature(digest, cloudSig, cloudSigner);

        uint8 validCount = 0;
        if (fccValid) validCount++;
        if (cloudValid) validCount++;

        if (severity == 1) {
            // MEDIUM: 1-of-2
            if (validCount < 1) revert InsufficientSigners(severity);
        } else {
            // HIGH (2) or CRITICAL (3): 2-of-2
            if (validCount < 2) revert InsufficientSigners(severity);
        }
    }

    // ── Governance ────────────────────────────────────────────────────────

    function setFccSigner(address newSigner) external onlyGovernance {
        if (newSigner == address(0)) revert ZeroAddress();
        address old = fccSigner;
        fccSigner = newSigner;
        emit FccSignerUpdated(old, newSigner);
    }

    function setCloudSigner(address newSigner) external onlyGovernance {
        if (newSigner == address(0)) revert ZeroAddress();
        address old = cloudSigner;
        cloudSigner = newSigner;
        emit CloudSignerUpdated(old, newSigner);
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }

    // ── Internal ──────────────────────────────────────────────────────────

    /**
     * @dev Recover signer from an ECDSA signature and compare to expected.
     *      Empty signature (length 0) is treated as "not provided" → returns false.
     *      Invalid signature (length != 65 or recovery fails) → returns false.
     */
    function _isValidSignature(
        bytes32 digest,
        bytes calldata sig,
        address expected
    ) internal pure returns (bool) {
        if (sig.length == 0) return false;
        if (sig.length != 65) return false;
        if (expected == address(0)) return false;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 0x20))
            v := byte(0, calldataload(add(sig.offset, 0x40)))
        }

        // EIP-2: restrict s to lower half of the curve
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return false;
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) return false;

        address recovered = ecrecover(digest, v, r, s);
        return recovered != address(0) && recovered == expected;
    }
}
