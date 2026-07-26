// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IFtsoV2Minimal {
    function getFeedById(bytes21 feedId)
        external payable
        returns (uint256 value, int8 decimals, uint64 timestamp);
}

/**
 * @title ZukoFTSOWatcher
 * @notice On-chain ring buffer and z-score computation helper for FTSOv2 price feeds.
 *         Normalizes all incoming FTSOv2 values to 1e18 WAD baseline regardless of native feed decimals.
 */
contract ZukoFTSOWatcher {
    uint8 public constant RING_SIZE = 50;
    uint8 public constant MIN_SAMPLES = 20;

    address public immutable ftsoV2;
    address public updater;
    uint256 public sigmaWarnThreshold; // E2 scaled (e.g., 200 = 2.00σ)

    struct FeedState {
        uint256[RING_SIZE] samples;
        uint8 head;
        uint8 count;
        uint256 lastAnchorValue; // WAD scaled
    }

    mapping(bytes21 => FeedState) private _feedStates;

    event FeedSampleUpdated(bytes21 indexed feedId, uint256 rawValue, uint256 normalizedValue, int8 decimals);
    event AnchorValueSet(bytes21 indexed feedId, uint256 anchorValue);
    event UpdaterUpdated(address indexed oldUpdater, address indexed newUpdater);
    event SigmaThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    error NotUpdater(address caller, address expected);
    error ZeroAddress();

    modifier onlyUpdater() {
        if (msg.sender != updater) revert NotUpdater(msg.sender, updater);
        _;
    }

    constructor(address _ftsoV2, address _updater, uint256 _sigmaWarnThreshold) {
        if (_ftsoV2 == address(0) || _updater == address(0)) revert ZeroAddress();
        ftsoV2 = _ftsoV2;
        updater = _updater;
        sigmaWarnThreshold = _sigmaWarnThreshold;
    }

    /// @dev Normalize a raw FTSOv2 feed value to 1e18 WAD baseline regardless of native decimals.
    function _normalize(uint256 rawValue, int8 decimals) internal pure returns (uint256 normalized) {
        int256 diff = int256(18) - int256(decimals);
        if (diff >= 0) {
            normalized = rawValue * (10 ** uint256(diff));
        } else {
            normalized = rawValue / (10 ** uint256(-diff));
        }
    }

    /// @notice Update feed sample by reading live from FTSOv2 contract.
    function updateFeedSample(bytes21 feedId) external onlyUpdater returns (uint256 normalizedValue) {
        (uint256 rawValue, int8 decimals, ) = IFtsoV2Minimal(ftsoV2).getFeedById(feedId);
        normalizedValue = _normalize(rawValue, decimals);

        FeedState storage state = _feedStates[feedId];
        state.samples[state.head] = normalizedValue;
        state.head = uint8((uint256(state.head) + 1) % RING_SIZE);
        if (state.count < RING_SIZE) {
            state.count++;
        }

        emit FeedSampleUpdated(feedId, rawValue, normalizedValue, decimals);
    }

    /// @notice Set anchor value for deviation checking (must be 1e18 WAD scaled).
    function setAnchorValue(bytes21 feedId, uint256 anchorValueWad) external onlyUpdater {
        _feedStates[feedId].lastAnchorValue = anchorValueWad;
        emit AnchorValueSet(feedId, anchorValueWad);
    }

    /// @notice Returns current sample count in ring buffer.
    function sampleCount(bytes21 feedId) external view returns (uint8) {
        return _feedStates[feedId].count;
    }

    /// @notice Returns the latest normalized sample.
    function latestSample(bytes21 feedId) external view returns (uint256) {
        FeedState storage state = _feedStates[feedId];
        if (state.count == 0) return 0;
        uint8 latestIdx = state.head == 0 ? state.count - 1 : state.head - 1;
        return state.samples[latestIdx];
    }

    /// @notice Returns rolling mean of normalized samples in WAD.
    function rollingMean(bytes21 feedId) public view returns (int256) {
        FeedState storage state = _feedStates[feedId];
        if (state.count == 0) return 0;

        uint256 sum = 0;
        for (uint8 i = 0; i < state.count; i++) {
            sum += state.samples[i];
        }
        return int256(sum / state.count);
    }

    /// @notice Computes z-score scaled by 100 (e.g. 200 = 2.00σ). Returns 0 if count < MIN_SAMPLES or zero variance.
    function computeZScore(bytes21 feedId) public view returns (int256) {
        FeedState storage state = _feedStates[feedId];
        if (state.count < MIN_SAMPLES) return 0;

        int256 mean = rollingMean(feedId);
        uint256 latestIdx = state.head == 0 ? state.count - 1 : state.head - 1;
        int256 current = int256(state.samples[latestIdx]);

        int256 diff = current - mean;
        if (diff == 0) return 0;

        uint256 sumSqDiff = 0;
        for (uint8 i = 0; i < state.count; i++) {
            int256 d = int256(state.samples[i]) - mean;
            sumSqDiff += uint256(d * d);
        }

        uint256 variance = sumSqDiff / state.count;
        uint256 stdDev = _sqrt(variance);
        if (stdDev == 0) return 0;

        // z-score scaled by 100 (E2)
        return (diff * 100) / int256(stdDev);
    }

    /// @notice Returns true if current z-score exceeds warning threshold.
    function isAboveWarnThreshold(bytes21 feedId) external view returns (bool) {
        int256 z = computeZScore(feedId);
        int256 absZ = z < 0 ? -z : z;
        return absZ > int256(sigmaWarnThreshold);
    }

    /// @notice Computes absolute anchor deviation scaled to E4 (e.g. 1000 = 10.00%, 150 = 1.50%).
    function anchorDeviation(bytes21 feedId) external view returns (uint256) {
        FeedState storage state = _feedStates[feedId];
        if (state.lastAnchorValue == 0 || state.count == 0) return 0;

        uint256 current = this.latestSample(feedId);
        uint256 anchor = state.lastAnchorValue;

        uint256 diff = current > anchor ? current - anchor : anchor - current;
        return (diff * 10000) / anchor;
    }

    function setUpdater(address _newUpdater) external onlyUpdater {
        if (_newUpdater == address(0)) revert ZeroAddress();
        emit UpdaterUpdated(updater, _newUpdater);
        updater = _newUpdater;
    }

    function setSigmaWarnThreshold(uint256 _newThreshold) external onlyUpdater {
        emit SigmaThresholdUpdated(sigmaWarnThreshold, _newThreshold);
        sigmaWarnThreshold = _newThreshold;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
