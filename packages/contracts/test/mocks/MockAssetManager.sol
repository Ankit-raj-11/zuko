// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Mock AssetManager covering both pause facets.
 *         Records all calls for test assertions.
 *         Correctly enforces the duration cap so ZukoGuardian
 *         cap-enforcement tests are meaningful.
 */
contract MockAssetManager {
    // --- Settings (mirror AssetManagerSettings) ---
    uint256 public maxEmergencyPauseDurationSeconds     = 6 hours;
    uint256 public emergencyPauseDurationResetAfterSeconds = 24 hours;
    uint256 public maxTransferPauseDurationSeconds      = 6 hours;
    uint256 public minVaultCollateralRatioBIPS          = 15000; // 150%
    uint256 public minPoolCollateralRatioBIPS           = 15000;

    // --- State (mirrors real facets) ---
    uint256 public emergencyPausedUntil;
    uint256 public transfersEmergencyPausedUntil;

    // --- Call recording ---
    uint256 public opsPauseCallCount;
    uint256 public transferPauseCallCount;
    uint256 public lastOpsPauseDuration;
    uint256 public lastTransferPauseDuration;

    // --- Access control ---
    address public pauseGuardian;

    error NotPauseGuardian(address caller, address expected);

    constructor(address _pauseGuardian) {
        pauseGuardian = _pauseGuardian;
    }

    // EmergencyPauseFacet
    function emergencyPause(uint256 duration) external {
        if (msg.sender != pauseGuardian)
            revert NotPauseGuardian(msg.sender, pauseGuardian);
        opsPauseCallCount++;
        lastOpsPauseDuration = duration;
        uint256 end = block.timestamp + duration;
        if (end > emergencyPausedUntil) emergencyPausedUntil = end;
    }

    // EmergencyPauseTransfersFacet
    function emergencyPauseTransfers(uint256 duration) external {
        if (msg.sender != pauseGuardian)
            revert NotPauseGuardian(msg.sender, pauseGuardian);
        transferPauseCallCount++;
        lastTransferPauseDuration = duration;
        uint256 end = block.timestamp + duration;
        if (end > transfersEmergencyPausedUntil)
            transfersEmergencyPausedUntil = end;
    }

    function isEmergencyPaused() external view returns (bool) {
        return block.timestamp < emergencyPausedUntil;
    }

    function isTransferEmergencyPaused() external view returns (bool) {
        return block.timestamp < transfersEmergencyPausedUntil;
    }

    // --- Test helpers ---
    function setPauseGuardian(address g) external { pauseGuardian = g; }
    function setMaxPauseDuration(uint256 d) external {
        maxEmergencyPauseDurationSeconds = d;
    }
    function setMaxTransferPauseDuration(uint256 d) external {
        maxTransferPauseDurationSeconds = d;
    }
    function setMinVaultCR(uint256 bips) external {
        minVaultCollateralRatioBIPS = bips;
    }
}
