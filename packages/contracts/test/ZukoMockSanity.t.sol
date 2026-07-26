// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "./mocks/MockFtsoV2.sol";
import "./mocks/MockAssetManager.sol";
import "./mocks/MockFdcVerification.sol";
import "./mocks/MockTeeRegistry.sol";

/**
 * @title ZukoMockSanity
 * @notice Verifies that all mock contracts behave correctly before they are
 *         used in production contract test suites (Phase 1–3).
 *
 * Run: forge test --match-contract ZukoMockSanity -vvv
 */
contract ZukoMockSanity is Test {

    // ── MockFtsoV2 ────────────────────────────────────────────────────────

    function test_MockFtsoV2_SetAndGetFeed() public {
        MockFtsoV2 ftso = new MockFtsoV2();
        bytes21 feedId = bytes21(uint168(0x01));

        ftso.setFeed(feedId, 58210, 5);

        (uint256 value, int8 decimals, uint64 timestamp) = ftso.getFeedById(feedId);

        assertEq(value, 58210, "Value must match what was set");
        assertEq(decimals, 5, "Decimals must match what was set");
        assertGt(timestamp, 0, "Timestamp must be non-zero");
    }

    function test_MockFtsoV2_GetFeedsById_Batch() public {
        MockFtsoV2 ftso = new MockFtsoV2();
        bytes21 feed1 = bytes21(uint168(0x01));
        bytes21 feed2 = bytes21(uint168(0x02));

        ftso.setFeed(feed1, 100, 5);
        ftso.setFeed(feed2, 200, 8);

        bytes21[] memory ids = new bytes21[](2);
        ids[0] = feed1;
        ids[1] = feed2;

        (uint256[] memory values, int8[] memory decimals, uint64 timestamp) =
            ftso.getFeedsById(ids);

        assertEq(values[0], 100);
        assertEq(values[1], 200);
        assertEq(decimals[0], 5);
        assertEq(decimals[1], 8);
        assertGt(timestamp, 0);
    }

    function test_MockFtsoV2_UnsetFeed_ReturnsZero() public {
        MockFtsoV2 ftso = new MockFtsoV2();
        bytes21 feedId = bytes21(uint168(0xFF));

        (uint256 value, int8 decimals,) = ftso.getFeedById(feedId);
        assertEq(value, 0, "Unset feed value must be 0");
        assertEq(decimals, 0, "Unset feed decimals must be 0");
    }

    // ── MockAssetManager ──────────────────────────────────────────────────

    function test_MockAssetManager_PauseByGuardian() public {
        MockAssetManager am = new MockAssetManager(address(this));

        am.emergencyPause(3600);

        assertEq(am.opsPauseCallCount(), 1);
        assertEq(am.lastOpsPauseDuration(), 3600);
        assertTrue(am.isEmergencyPaused());
    }

    function test_MockAssetManager_PauseByNonGuardian_Reverts() public {
        MockAssetManager am = new MockAssetManager(address(0xBEEF));

        vm.expectRevert(
            abi.encodeWithSelector(
                MockAssetManager.NotPauseGuardian.selector,
                address(this),
                address(0xBEEF)
            )
        );
        am.emergencyPause(3600);
    }

    function test_MockAssetManager_TransferPause() public {
        MockAssetManager am = new MockAssetManager(address(this));

        am.emergencyPauseTransfers(7200);

        assertEq(am.transferPauseCallCount(), 1);
        assertEq(am.lastTransferPauseDuration(), 7200);
        assertTrue(am.isTransferEmergencyPaused());
    }

    function test_MockAssetManager_DefaultSettings() public {
        MockAssetManager am = new MockAssetManager(address(this));

        assertEq(am.maxEmergencyPauseDurationSeconds(), 6 hours);
        assertEq(am.emergencyPauseDurationResetAfterSeconds(), 24 hours);
        assertEq(am.maxTransferPauseDurationSeconds(), 6 hours);
        assertEq(am.minVaultCollateralRatioBIPS(), 15000);
        assertEq(am.minPoolCollateralRatioBIPS(), 15000);
    }

    function test_MockAssetManager_SetMaxPauseDuration() public {
        MockAssetManager am = new MockAssetManager(address(this));

        am.setMaxPauseDuration(1800);
        assertEq(am.maxEmergencyPauseDurationSeconds(), 1800);
    }

    // ── MockFdcVerification ───────────────────────────────────────────────

    function test_MockFdc_DefaultResult_True() public {
        MockFdcVerification fdc = new MockFdcVerification();

        (bool proved,) = fdc.verifyPayment(hex"aabbccdd");
        assertTrue(proved, "Default result must be true (bridge healthy)");
    }

    function test_MockFdc_SetDefaultFalse() public {
        MockFdcVerification fdc = new MockFdcVerification();

        fdc.setDefaultResult(false);
        (bool proved,) = fdc.verifyPayment(hex"aabbccdd");
        assertFalse(proved, "Must return false after setDefaultResult(false)");
    }

    function test_MockFdc_PerKeyResult() public {
        MockFdcVerification fdc = new MockFdcVerification();

        bytes memory proof = hex"deadbeef";
        bytes32 proofHash = keccak256(proof);

        fdc.setAttestation(proofHash, false);

        (bool proved,) = fdc.verifyPayment(proof);
        assertFalse(proved, "Per-key result must override default");
    }

    function test_MockFdc_ResetToDefault() public {
        MockFdcVerification fdc = new MockFdcVerification();

        fdc.setDefaultResult(false);
        fdc.resetToDefault();

        (bool proved,) = fdc.verifyPayment(hex"aabb");
        assertTrue(proved, "Reset must restore default=true");
    }

    // ── MockTeeRegistry ───────────────────────────────────────────────────

    function test_MockTee_RegisterAndCheck() public {
        MockTeeRegistry tee = new MockTeeRegistry();
        bytes32 hash = keccak256("zuko-v1");

        assertFalse(tee.isHashRegistered(hash), "Initially not registered");

        tee.registerHash(hash);
        assertTrue(tee.isHashRegistered(hash), "Must be registered after registerHash");
    }

    function test_MockTee_DeregisterHash() public {
        MockTeeRegistry tee = new MockTeeRegistry();
        bytes32 hash = keccak256("zuko-v1");

        tee.registerHash(hash);
        assertTrue(tee.isHashRegistered(hash));

        tee.deregisterHash(hash);
        assertFalse(tee.isHashRegistered(hash), "Must be deregistered after deregisterHash");
    }
}
