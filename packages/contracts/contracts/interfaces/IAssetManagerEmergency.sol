// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IAssetManagerEmergency
 * @notice Interface covering AssetManager emergency pause facets and settings.
 *         Zuko reads ALL settings LIVE before every executeInstruction call.
 *         These values are NEVER cached — governance may change them at any time.
 *
 * PAUSE MECHANISM (CRITICAL):
 *   AssetManager uses TWO separate duration-based pause facets:
 *     1. EmergencyPauseFacet.emergencyPause(duration) — halts ops
 *     2. EmergencyPauseTransfersFacet.emergencyPauseTransfers(duration) — halts transfers
 *   Duration is in seconds, capped at governance-set maximums.
 *
 * @dev Resolve via ContractRegistry → AssetManagerController → AssetManager(FXRP)
 */
interface IAssetManagerEmergency {
    // ── EmergencyPauseFacet ──────────────────────────────────────────────

    /// @notice Pause all minting/redeeming operations for `duration` seconds.
    function emergencyPause(uint256 duration) external;

    /// @notice Check if operations are currently paused.
    function isEmergencyPaused() external view returns (bool);

    /// @notice Unix timestamp when the current ops pause expires.
    function emergencyPausedUntil() external view returns (uint256);

    // ── EmergencyPauseTransfersFacet ─────────────────────────────────────

    /// @notice Pause all FAsset transfers for `duration` seconds.
    function emergencyPauseTransfers(uint256 duration) external;

    /// @notice Check if transfers are currently paused.
    function isTransferEmergencyPaused() external view returns (bool);

    /// @notice Unix timestamp when the current transfer pause expires.
    function transfersEmergencyPausedUntil() external view returns (uint256);

    // ── Settings (always read live, never cache) ─────────────────────────

    /// @notice Maximum allowed ops pause duration in seconds.
    function maxEmergencyPauseDurationSeconds() external view returns (uint256);

    /// @notice Duration after which the ops pause accumulator resets.
    function emergencyPauseDurationResetAfterSeconds() external view returns (uint256);

    /// @notice Maximum allowed transfer pause duration in seconds.
    function maxTransferPauseDurationSeconds() external view returns (uint256);

    /// @notice Minimum vault collateral ratio in BIPS (e.g. 15000 = 150%).
    function minVaultCollateralRatioBIPS() external view returns (uint256);

    /// @notice Minimum pool collateral ratio in BIPS.
    function minPoolCollateralRatioBIPS() external view returns (uint256);
}
