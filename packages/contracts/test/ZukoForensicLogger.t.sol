// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ZukoForensicLogger.sol";

/**
 * @title ZukoForensicLoggerTest
 * @notice Covers: append-only semantics, incrementing IDs,
 *         access control, non-existent incident query, and event emission.
 *
 * Run: forge test --match-contract ZukoForensicLoggerTest -vvv
 */
contract ZukoForensicLoggerTest is Test {
    ZukoForensicLogger internal logger;
    address internal guardian = address(0x6001);

    function setUp() public {
        vm.roll(10);
        logger = new ZukoForensicLogger(guardian);
    }

    function _log(uint8 sev, uint8 rules) internal returns (uint256 id) {
        vm.prank(guardian);
        return logger.logIncident(
            sev, rules,
            bytes32(uint256(1)),
            1_000_000, 1_050_000,
            uint64(block.number - 5), uint64(block.number),
            bytes32(0),
            hex"aabb", hex"ccdd"
        );
    }

    function test_Log_StoresCorrectValues() public {
        uint256 id = _log(2, 0x06);
        assertEq(id, 0, "First incident must be id=0");

        ZukoForensicLogger.Incident memory inc = logger.getIncident(0);
        assertEq(inc.severity,       2);
        assertEq(inc.rulesTriggered, 0x06);
        assertEq(inc.feedValue,      1_000_000);
        assertEq(inc.anchorValue,    1_050_000);
    }

    function test_Log_IdsIncrement() public {
        uint256 a = _log(1, 0x01);
        uint256 b = _log(2, 0x02);
        uint256 c = _log(3, 0x08);
        assertEq(a, 0);
        assertEq(b, 1);
        assertEq(c, 2);
        assertEq(logger.totalIncidents(), 3);
    }

    function test_Log_NonGuardian_Reverts() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        logger.logIncident(1, 0x01, bytes32(0), 0, 0, 0, 0, bytes32(0), "", "");
    }

    function test_Get_NonExistentIncident_Reverts() public {
        vm.expectRevert();
        logger.getIncident(999);
    }

    function test_Log_EmitsEvent() public {
        vm.recordLogs();
        _log(1, 0x01);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == ZukoForensicLogger.IncidentLogged.selector) {
                found = true;
                break;
            }
        }
        assertTrue(found, "IncidentLogged event must be emitted");
    }
}
