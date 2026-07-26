// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title IFtsoV2Minimal
 * @notice Minimal interface for Flare FTSOv2 price feeds.
 *         All addresses resolved at runtime via ContractRegistry — never hardcoded.
 *
 * Key: getFeedById returns (uint256 value, int8 decimals, uint64 timestamp).
 * Decimals vary per asset pair (5, 8, 18, etc.) — callers MUST normalize
 * before using values in any cross-feed computation.
 *
 * @dev Registry address: 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019
 *      Resolve with: registry.getContractAddressByName("FtsoV2")
 */
interface IFtsoV2Minimal {
    /**
     * @notice Get the current value of a single FTSO feed.
     * @param id 21-byte feed identifier (0x01 prefix + ASCII pair name padded)
     * @return value Raw price value (scale depends on `decimals`)
     * @return decimals int8 — native decimal precision of this feed
     * @return timestamp Block timestamp of this feed update
     */
    function getFeedById(bytes21 id)
        external payable
        returns (uint256 value, int8 decimals, uint64 timestamp);

    /**
     * @notice Get current values for multiple FTSO feeds in a single call.
     *         Avoids N round-trips for N feeds.
     * @param ids Array of 21-byte feed identifiers
     * @return values Raw price values per feed
     * @return decimals Native decimal precision per feed
     * @return timestamp Block timestamp (shared across all feeds in this call)
     */
    function getFeedsById(bytes21[] calldata ids)
        external payable
        returns (uint256[] memory values, int8[] memory decimals, uint64 timestamp);
}
