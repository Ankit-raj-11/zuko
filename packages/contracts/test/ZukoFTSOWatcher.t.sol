// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoFTSOWatcher.sol";
import "./mocks/MockFtsoV2.sol";

/**
 * @title ZukoFTSOWatcherTest
 * @notice Covers: ring-buffer accumulation and wrap-around,
 *         z-score math (stable / spike / gradual / insufficient samples),
 *         anchor deviation calculation, updater access control,
 *         and decimal normalization.
 *
 * Run: forge test --match-contract ZukoFTSOWatcherTest -vvv
 */
contract ZukoFTSOWatcherTest is Test {
    ZukoFTSOWatcher internal watcher;
    MockFtsoV2      internal ftso;

    // XRP/USD feed ID — 0x01 prefix + ASCII "XRP/USD" padded to 21 bytes
    bytes21 internal constant XRP_USD =
        0x015852502f55534400000000000000000000000000;

    address internal updater = address(0xABC1);

    function setUp() public {
        ftso    = new MockFtsoV2();
        watcher = new ZukoFTSOWatcher(
            address(ftso),
            updater,
            200   // sigmaWarnThreshold = 2.00σ (E2 scaled)
        );
    }

    // ── Helper: push N identical samples ────────────────────────────────

    function _fill(uint256 value, uint8 n) internal {
        for (uint8 i; i < n; i++) {
            ftso.setFeed(XRP_USD, value, 6);
            vm.prank(updater);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 2);
        }
    }

    // ── Ring buffer ───────────────────────────────────────────────────────

    function test_Ring_AccumulatesUpToRingSize() public {
        _fill(1_000_000, 30);
        assertEq(watcher.sampleCount(XRP_USD), 30);
    }

    function test_Ring_DoesNotGrowBeyondRingSize() public {
        _fill(1_000_000, 50); // fill
        ftso.setFeed(XRP_USD, 999_000, 6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        assertEq(watcher.sampleCount(XRP_USD), 50, "Ring must wrap at RING_SIZE");
    }

    function test_Ring_OverwritesOldest_ValueChanges() public {
        _fill(1_000_000, 50);
        int256 meanBefore = watcher.rollingMean(XRP_USD);

        ftso.setFeed(XRP_USD, 1_500_000, 6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);

        int256 meanAfter = watcher.rollingMean(XRP_USD);
        assertGt(meanAfter, meanBefore, "Mean must rise after inserting higher value");
    }

    // ── Access control ────────────────────────────────────────────────────

    function test_Update_NonUpdater_Reverts() public {
        ftso.setFeed(XRP_USD, 1_000_000, 6);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        watcher.updateFeedSample(XRP_USD);
    }

    // ── Z-score ───────────────────────────────────────────────────────────

    function test_ZScore_ZeroVariance_ReturnsZero() public {
        _fill(1_000_000, 50);
        assertEq(watcher.computeZScore(XRP_USD), 0, "Zero variance must produce z=0");
    }

    function test_ZScore_LargeSpike_ExceedsThreshold() public {
        _fill(1_000_000, 49);
        ftso.setFeed(XRP_USD, 1_500_000, 6); // +50% spike
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);

        int256 z = watcher.computeZScore(XRP_USD);
        assertGt(z, 200, unicode"50% spike must exceed 2σ threshold");
        assertTrue(watcher.isAboveWarnThreshold(XRP_USD));
    }

    function test_ZScore_SmallNoise_BelowThreshold() public {
        for (uint8 i; i < 50; i++) {
            uint256 v = 1_000_000 + (i % 2 == 0 ? 3_000 : 0); // ±0.3%
            ftso.setFeed(XRP_USD, v, 6);
            vm.prank(updater);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        assertFalse(watcher.isAboveWarnThreshold(XRP_USD), "Sub-threshold noise must not trigger warning");
    }

    function test_ZScore_InsufficientSamples_ReturnsZero() public {
        _fill(1_000_000, 5);
        assertEq(watcher.computeZScore(XRP_USD), 0, "Insufficient samples must return 0");
        assertFalse(watcher.isAboveWarnThreshold(XRP_USD));
    }

    function test_ZScore_GradualDecline_DoesNotFire() public {
        for (uint8 i; i < 50; i++) {
            uint256 v = 1_000_000 - uint256(i) * 5_000;
            ftso.setFeed(XRP_USD, v, 6);
            vm.prank(updater);
            watcher.updateFeedSample(XRP_USD);
            vm.roll(block.number + 1);
        }
        assertFalse(watcher.isAboveWarnThreshold(XRP_USD), "Linear price decline must not fire anomaly");
    }

    // ── Anchor deviation ─────────────────────────────────────────────────

    function test_AnchorDeviation_WhenEqual_IsZero() public {
        ftso.setFeed(XRP_USD, 1_000_000, 6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        vm.prank(updater);
        watcher.setAnchorValue(XRP_USD, 1_000_000 * 1e12); // WAD scaled

        assertEq(watcher.anchorDeviation(XRP_USD), 0);
    }

    function test_AnchorDeviation_TenPercent_ReturnsCorrectScaled() public {
        ftso.setFeed(XRP_USD, 900_000, 6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        vm.prank(updater);
        watcher.setAnchorValue(XRP_USD, 1_000_000 * 1e12); // WAD scaled

        assertEq(watcher.anchorDeviation(XRP_USD), 1000, "10% deviation must return 1000 (1e4 scaled)");
    }

    function test_AnchorDeviation_NoAnchorSet_ReturnsZero() public {
        ftso.setFeed(XRP_USD, 1_000_000, 6);
        vm.prank(updater);
        watcher.updateFeedSample(XRP_USD);
        assertEq(watcher.anchorDeviation(XRP_USD), 0, "Unset anchor must return 0 deviation");
    }

    // ── Normalization test ───────────────────────────────────────────────

    function test_Normalize_NonStandardDecimals_CorrectWAD() public {
        bytes21 feedA = bytes21(uint168(0x01));
        ftso.setFeed(feedA, 58210, 5);
        vm.prank(updater);
        watcher.updateFeedSample(feedA);

        uint256 storedA = watcher.latestSample(feedA);
        assertEq(storedA, 58210 * 1e13, "5-decimal feed must normalize to WAD");

        bytes21 feedB = bytes21(uint168(0x02));
        ftso.setFeed(feedB, 97420000, 8);
        vm.prank(updater);
        watcher.updateFeedSample(feedB);

        uint256 storedB = watcher.latestSample(feedB);
        assertEq(storedB, 97420000 * 1e10, "8-decimal feed must normalize to WAD");
    }
}
