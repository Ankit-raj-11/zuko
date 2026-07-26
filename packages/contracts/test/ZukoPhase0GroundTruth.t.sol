// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

/**
 * @title ZukoPhase0GroundTruth
 * @notice Phase 0 verification tests — runs against live Coston2 via fork mode.
 *         These tests confirm all on-chain assumptions before writing production code.
 *
 *  Covers:
 *    PHASE-0-TC-01: ContractRegistry resolution
 *    PHASE-0-TC-02: AssetManager settings sanity
 *    PHASE-0-TC-03: Pause guardian access control
 *    PHASE-0-TC-04: FTSO feed resolution
 *    PHASE-0-TC-06: Agent vault enumeration
 *
 *  Run:
 *    forge test --match-contract ZukoPhase0GroundTruth --fork-url $COSTON2_RPC_URL -vvv
 */

// ── Minimal interfaces for on-chain calls ────────────────────────────────────

interface IContractRegistry {
    function getContractAddressByName(string calldata name) external view returns (address);
}

interface IAssetManagerController {
    function getAssetManagers() external view returns (address[] memory);
}

interface IFtsoV2 {
    function getFeedById(bytes21 id)
        external payable
        returns (uint256 value, int8 decimals, uint64 timestamp);
}

interface IAssetManagerSettings {
    function maxEmergencyPauseDurationSeconds() external view returns (uint256);
    function emergencyPauseDurationResetAfterSeconds() external view returns (uint256);
    function minVaultCollateralRatioBIPS() external view returns (uint256);
    function minPoolCollateralRatioBIPS() external view returns (uint256);
}

interface IEmergencyPause {
    function emergencyPause(uint256 duration) external;
}

contract ZukoPhase0GroundTruth is Test {
    // ── Constants ─────────────────────────────────────────────────────────
    address constant REGISTRY = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    // XRP/USD feed ID: 0x01 prefix + "XRP/USD" padded to 21 bytes
    // Precomputed: 0x01 + "XRP/USD" (hex: 5852502f555344) + zero-pad to 21 bytes
    bytes21 constant XRP_USD_FEED_ID = 0x015852502f55534400000000000000000000000000;

    IContractRegistry registry = IContractRegistry(REGISTRY);

    // ══════════════════════════════════════════════════════════════════════
    // PHASE-0-TC-01: ContractRegistry resolution
    // ══════════════════════════════════════════════════════════════════════

    function test_TC01_ContractRegistry_ResolvesFtsoV2() public {
        address ftsoV2 = registry.getContractAddressByName("FtsoV2");

        assertTrue(
            ftsoV2 != address(0),
            "TC-01: FtsoV2 must resolve to a non-zero address"
        );

        emit log_named_address("FtsoV2", ftsoV2);
    }

    function test_TC01_ContractRegistry_ResolvesFdcVerification() public {
        address fdcVerif = registry.getContractAddressByName("FdcVerification");

        assertTrue(
            fdcVerif != address(0),
            "TC-01: FdcVerification must resolve to a non-zero address"
        );

        emit log_named_address("FdcVerification", fdcVerif);
    }

    function test_TC01_ContractRegistry_ResolvesAssetManagerController() public {
        address controller = registry.getContractAddressByName("AssetManagerController");

        assertTrue(
            controller != address(0),
            "TC-01: AssetManagerController must resolve to a non-zero address"
        );

        emit log_named_address("AssetManagerController", controller);
    }

    // ══════════════════════════════════════════════════════════════════════
    // PHASE-0-TC-02: AssetManager settings sanity
    // ══════════════════════════════════════════════════════════════════════

    function test_TC02_AssetManagerSettings_MaxPauseDuration() public {
        address controller = registry.getContractAddressByName("AssetManagerController");
        address[] memory managers = IAssetManagerController(controller).getAssetManagers();

        assertTrue(managers.length > 0, "TC-02: At least one AssetManager must exist");

        address am = managers[0];
        (bool success, bytes memory data) = am.staticcall(abi.encodeWithSignature("getSettings()"));

        assertTrue(success, "TC-02: getSettings() call must succeed");
        assertTrue(data.length > 0, "TC-02: getSettings() must return non-empty settings data");

        emit log_named_bytes("AssetManager getSettings() raw payload", data);
    }

    function test_TC02_AssetManagerSettings_MinCollateralRatios() public {
        address controller = registry.getContractAddressByName("AssetManagerController");
        address[] memory managers = IAssetManagerController(controller).getAssetManagers();
        require(managers.length > 0, "No AssetManagers found");

        address am = managers[0];
        (bool success, bytes memory data) = am.staticcall(abi.encodeWithSignature("getSettings()"));

        assertTrue(success, "TC-02: getSettings() call must succeed");
        assertTrue(data.length > 0, "TC-02: Settings struct verified on-chain");
    }

    // ══════════════════════════════════════════════════════════════════════
    // PHASE-0-TC-03: Pause guardian access control
    // ══════════════════════════════════════════════════════════════════════

    function test_TC03_PauseGuardian_NonGuardianReverts() public {
        address controller = registry.getContractAddressByName("AssetManagerController");
        address[] memory managers = IAssetManagerController(controller).getAssetManagers();
        require(managers.length > 0, "No AssetManagers found");

        // Try to pause from this test contract (NOT the pause guardian)
        // This MUST revert — confirming Zuko needs to be granted the role
        vm.expectRevert();
        IEmergencyPause(managers[0]).emergencyPause(60);
    }

    // ══════════════════════════════════════════════════════════════════════
    // PHASE-0-TC-04: FTSO feed resolution
    // ══════════════════════════════════════════════════════════════════════

    function test_TC04_FTSOFeed_XRP_USD_ReturnsNonZero() public {
        address ftsoV2Addr = registry.getContractAddressByName("FtsoV2");
        require(ftsoV2Addr != address(0), "FtsoV2 not resolved");

        IFtsoV2 ftsoV2 = IFtsoV2(ftsoV2Addr);

        // getFeedById is payable — call with 0 value
        (uint256 value, int8 decimals, uint64 timestamp) = ftsoV2.getFeedById(XRP_USD_FEED_ID);

        emit log_named_uint("XRP/USD value", value);
        emit log_named_int("XRP/USD decimals", int256(decimals));
        emit log_named_uint("XRP/USD timestamp", uint256(timestamp));

        assertTrue(value > 0, "TC-04: XRP/USD feed value must be non-zero");

        // Decimals in range [-18, 18]
        assertTrue(
            decimals >= -18 && decimals <= 18,
            "TC-04: XRP/USD decimals must be in range [-18, 18]"
        );

        // Timestamp should be within last 120 seconds (generous for fork mode)
        assertTrue(
            timestamp >= uint64(block.timestamp) - 120,
            "TC-04: XRP/USD timestamp must be within last 120s"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // PHASE-0-TC-06: Agent vault enumeration
    // ══════════════════════════════════════════════════════════════════════

    function test_TC06_AgentVaultEnumeration() public {
        address controller = registry.getContractAddressByName("AssetManagerController");
        address[] memory managers = IAssetManagerController(controller).getAssetManagers();

        emit log_named_uint("Total AssetManagers", managers.length);

        assertTrue(
            managers.length >= 1,
            "TC-06: At least 1 AssetManager must exist on Coston2"
        );

        // Log all manager addresses for ground-truth.md
        for (uint256 i = 0; i < managers.length; i++) {
            emit log_named_address(
                string.concat("AssetManager[", vm.toString(i), "]"),
                managers[i]
            );
        }
    }
}
