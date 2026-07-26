// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Mock FDC verification contract.
 *         Toggle attestation results per proof hash or globally.
 *         Default: all proofs succeed (bridge is healthy) —
 *         tests explicitly set failure for anomaly scenarios.
 */
contract MockFdcVerification {
    mapping(bytes32 => bool) private _results;
    bool public defaultResult = true;
    bool public usePerKeyResults = false;

    function setAttestation(bytes32 proofHash, bool result) external {
        _results[proofHash] = result;
        usePerKeyResults    = true;
    }

    function setDefaultResult(bool result) external {
        defaultResult = result;
    }

    function resetToDefault() external {
        usePerKeyResults = false;
        defaultResult    = true;
    }

    // Matches IFdcVerification.verifyPayment pattern
    function verifyPayment(bytes calldata proof)
        external view
        returns (bool proved, bytes memory response)
    {
        bytes32 h = keccak256(proof);
        proved   = usePerKeyResults ? _results[h] : defaultResult;
        response = proof;
    }
}
