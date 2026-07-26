// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ZukoForensicLogger
 * @notice Append-only immutable incident ledger for on-chain forensic logging.
 *         Ensures no logged incident can be modified or deleted.
 */
contract ZukoForensicLogger {
    struct Incident {
        uint256 id;
        uint8 severity;
        uint8 rulesTriggered;
        bytes32 feedId;
        uint256 feedValue;
        uint256 anchorValue;
        uint64 blockRangeStart;
        uint64 blockRangeEnd;
        bytes32 fdcAttestationRef;
        bytes fccSignature;
        bytes cloudSignature;
        uint256 timestamp;
    }

    address public immutable guardian;
    Incident[] private _incidents;

    event IncidentLogged(
        uint256 indexed id,
        uint8 indexed severity,
        uint8 rulesTriggered,
        bytes32 feedId,
        uint256 feedValue,
        uint256 anchorValue,
        uint64 blockRangeStart,
        uint64 blockRangeEnd,
        bytes32 fdcAttestationRef,
        uint256 timestamp
    );

    error NotGuardian(address caller, address expected);
    error InvalidIncidentId(uint256 id);
    error ZeroAddress();

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian(msg.sender, guardian);
        _;
    }

    constructor(address _guardian) {
        if (_guardian == address(0)) revert ZeroAddress();
        guardian = _guardian;
    }

    /// @notice Appends a new immutable incident record to the forensic log.
    function logIncident(
        uint8 severity,
        uint8 rulesTriggered,
        bytes32 feedId,
        uint256 feedValue,
        uint256 anchorValue,
        uint64 blockRangeStart,
        uint64 blockRangeEnd,
        bytes32 fdcAttestationRef,
        bytes calldata fccSignature,
        bytes calldata cloudSignature
    ) external onlyGuardian returns (uint256 incidentId) {
        incidentId = _incidents.length;

        Incident memory incident = Incident({
            id: incidentId,
            severity: severity,
            rulesTriggered: rulesTriggered,
            feedId: feedId,
            feedValue: feedValue,
            anchorValue: anchorValue,
            blockRangeStart: blockRangeStart,
            blockRangeEnd: blockRangeEnd,
            fdcAttestationRef: fdcAttestationRef,
            fccSignature: fccSignature,
            cloudSignature: cloudSignature,
            timestamp: block.timestamp
        });

        _incidents.push(incident);

        emit IncidentLogged(
            incidentId,
            severity,
            rulesTriggered,
            feedId,
            feedValue,
            anchorValue,
            blockRangeStart,
            blockRangeEnd,
            fdcAttestationRef,
            block.timestamp
        );
    }

    /// @notice Total number of incidents logged.
    function totalIncidents() external view returns (uint256) {
        return _incidents.length;
    }

    /// @notice Get an incident record by ID.
    function getIncident(uint256 id) external view returns (Incident memory) {
        if (id >= _incidents.length) revert InvalidIncidentId(id);
        return _incidents[id];
    }
}
