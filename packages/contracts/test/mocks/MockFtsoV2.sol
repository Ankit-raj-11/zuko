// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Mock FTSOv2 for Foundry tests.
 *         Allows arbitrary feed values and simulates block-latency lag scenarios.
 *         Deliberately does NOT auto-advance values — tests set them explicitly
 *         so every assertion is against a known, deterministic value.
 */
contract MockFtsoV2 {
    struct FeedData {
        uint256 value;
        int8    decimals;
        uint64  timestamp;
    }

    mapping(bytes21 => FeedData) private _feeds;

    // Convenience: set a feed value with explicit decimals
    function setFeed(bytes21 feedId, uint256 value, int8 decimals) external {
        _feeds[feedId] = FeedData(value, decimals, uint64(block.timestamp));
    }

    // Mirror the real FtsoV2Interface
    function getFeedById(bytes21 feedId)
        external view
        returns (uint256 value, int8 decimals, uint64 timestamp)
    {
        FeedData memory d = _feeds[feedId];
        return (d.value, d.decimals, d.timestamp);
    }

    function getFeedsById(bytes21[] calldata feedIds)
        external view
        returns (
            uint256[] memory values,
            int8[]    memory decimals,
            uint64    timestamp
        )
    {
        values   = new uint256[](feedIds.length);
        decimals = new int8[](feedIds.length);
        for (uint256 i; i < feedIds.length; i++) {
            FeedData memory d = _feeds[feedIds[i]];
            values[i]   = d.value;
            decimals[i] = d.decimals;
        }
        timestamp = uint64(block.timestamp);
    }
}
