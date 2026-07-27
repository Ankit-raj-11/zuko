// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ZukoMultiProverVerifier} from "../contracts/ZukoMultiProverVerifier.sol";

/**
 * @title ZukoMultiProverVerifierTest
 * @notice Phase 2 test cases TC-01..04 for multi-prover signature verification.
 *         Uses real ECDSA signatures from Foundry vm.sign() — no mocks.
 */
contract ZukoMultiProverVerifierTest is Test {
    ZukoMultiProverVerifier public verifier;

    // Test keys — derived from Foundry's vm.sign
    uint256 constant FCC_PRIVATE_KEY   = 0x1;
    uint256 constant CLOUD_PRIVATE_KEY = 0x2;
    uint256 constant ROGUE_PRIVATE_KEY = 0x3;

    address fccAddr;
    address cloudAddr;
    address rogueAddr;
    address governance;

    function setUp() public {
        fccAddr   = vm.addr(FCC_PRIVATE_KEY);
        cloudAddr = vm.addr(CLOUD_PRIVATE_KEY);
        rogueAddr = vm.addr(ROGUE_PRIVATE_KEY);
        governance = address(this);

        verifier = new ZukoMultiProverVerifier(fccAddr, cloudAddr, governance);
    }

    // ── Helper: create a test digest and sign it ──────────────────────────

    function _testDigest() internal pure returns (bytes32) {
        // Simulate what ZukoGuardian does: hash the payload, then eth_sign prefix
        bytes memory payload = abi.encode(
            uint8(1),       // severity
            uint8(0x01),    // rulesTriggered
            uint32(3600),   // opsPauseDuration
            uint32(0),      // transfersPauseDuration
            bytes32(0),     // feedId
            uint256(1e18),  // feedValue
            uint256(1e18),  // anchorValue
            uint64(100),    // blockRangeStart
            uint64(110),    // blockRangeEnd
            bytes32(0),     // fdcAttestationRef
            uint64(1),      // nonce
            uint32(114)     // chainId
        );
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(payload)
            )
        );
    }

    function _sign(uint256 privKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ── PHASE-2-TC-01: MEDIUM passes with FCC sig only ───────────────────

    function test_VerifyMediumSeverity_OneFccSig_Passes() public view {
        bytes32 digest = _testDigest();
        bytes memory fccSig = _sign(FCC_PRIVATE_KEY, digest);
        bytes memory emptySig = "";

        (bool fccValid, bool cloudValid) = verifier.verify(
            digest,
            1, // MEDIUM
            fccSig,
            emptySig
        );

        assertTrue(fccValid, "FCC sig should be valid");
        assertFalse(cloudValid, "Cloud sig should be invalid (empty)");
    }

    // ── PHASE-2-TC-02: MEDIUM passes with cloud sig only ─────────────────

    function test_VerifyMediumSeverity_OneCloudSig_Passes() public view {
        bytes32 digest = _testDigest();
        bytes memory emptySig = "";
        bytes memory cloudSig = _sign(CLOUD_PRIVATE_KEY, digest);

        (bool fccValid, bool cloudValid) = verifier.verify(
            digest,
            1, // MEDIUM
            emptySig,
            cloudSig
        );

        assertFalse(fccValid, "FCC sig should be invalid (empty)");
        assertTrue(cloudValid, "Cloud sig should be valid");
    }

    // ── PHASE-2-TC-03: CRITICAL requires both sigs ───────────────────────

    function test_VerifyCritical_BothSigs_Passes() public view {
        bytes32 digest = _testDigest();
        bytes memory fccSig = _sign(FCC_PRIVATE_KEY, digest);
        bytes memory cloudSig = _sign(CLOUD_PRIVATE_KEY, digest);

        (bool fccValid, bool cloudValid) = verifier.verify(
            digest,
            3, // CRITICAL
            fccSig,
            cloudSig
        );

        assertTrue(fccValid, "FCC sig should be valid");
        assertTrue(cloudValid, "Cloud sig should be valid");
    }

    function test_VerifyCritical_OnlyFccSig_Fails() public {
        bytes32 digest = _testDigest();
        bytes memory fccSig = _sign(FCC_PRIVATE_KEY, digest);
        bytes memory emptySig = "";

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(3)
            )
        );
        verifier.verify(digest, 3, fccSig, emptySig);
    }

    function test_VerifyCritical_OnlyCloudSig_Fails() public {
        bytes32 digest = _testDigest();
        bytes memory emptySig = "";
        bytes memory cloudSig = _sign(CLOUD_PRIVATE_KEY, digest);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(3)
            )
        );
        verifier.verify(digest, 3, emptySig, cloudSig);
    }

    // ── PHASE-2-TC-03b: HIGH also requires both sigs ─────────────────────

    function test_VerifyHigh_BothSigs_Passes() public view {
        bytes32 digest = _testDigest();
        bytes memory fccSig = _sign(FCC_PRIVATE_KEY, digest);
        bytes memory cloudSig = _sign(CLOUD_PRIVATE_KEY, digest);

        (bool fccValid, bool cloudValid) = verifier.verify(
            digest,
            2, // HIGH
            fccSig,
            cloudSig
        );

        assertTrue(fccValid);
        assertTrue(cloudValid);
    }

    function test_VerifyHigh_OnlyFccSig_Fails() public {
        bytes32 digest = _testDigest();
        bytes memory fccSig = _sign(FCC_PRIVATE_KEY, digest);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(2)
            )
        );
        verifier.verify(digest, 2, fccSig, "");
    }

    // ── PHASE-2-TC-04: Wrong signer rejected ─────────────────────────────

    function test_VerifyWrongSigner_Fails() public {
        bytes32 digest = _testDigest();
        // Sign with rogue key, not the registered FCC or cloud key
        bytes memory rogueSig = _sign(ROGUE_PRIVATE_KEY, digest);

        // MEDIUM with rogue sig as both — neither matches FCC or cloud signer
        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(1)
            )
        );
        verifier.verify(digest, 1, rogueSig, "");
    }

    function test_VerifyWrongSigner_BothRogue_Fails() public {
        bytes32 digest = _testDigest();
        bytes memory rogueSig = _sign(ROGUE_PRIVATE_KEY, digest);

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(1)
            )
        );
        verifier.verify(digest, 1, rogueSig, rogueSig);
    }

    // ── Additional edge cases ─────────────────────────────────────────────

    function test_VerifyMedium_BothEmpty_Fails() public {
        bytes32 digest = _testDigest();

        vm.expectRevert(
            abi.encodeWithSelector(
                ZukoMultiProverVerifier.InsufficientSigners.selector,
                uint8(1)
            )
        );
        verifier.verify(digest, 1, "", "");
    }

    function test_VerifyMedium_BothValid_Passes() public view {
        bytes32 digest = _testDigest();
        bytes memory fccSig = _sign(FCC_PRIVATE_KEY, digest);
        bytes memory cloudSig = _sign(CLOUD_PRIVATE_KEY, digest);

        (bool fccValid, bool cloudValid) = verifier.verify(
            digest,
            1, // MEDIUM
            fccSig,
            cloudSig
        );

        assertTrue(fccValid);
        assertTrue(cloudValid);
    }

    // ── Governance tests ──────────────────────────────────────────────────

    function test_SetFccSigner_GovernanceOnly() public {
        address newSigner = address(0x1234);
        verifier.setFccSigner(newSigner);
        assertEq(verifier.fccSigner(), newSigner);
    }

    function test_SetFccSigner_NonGovernance_Reverts() public {
        vm.prank(address(0xdead));
        vm.expectRevert(ZukoMultiProverVerifier.NotGovernance.selector);
        verifier.setFccSigner(address(0x1234));
    }

    function test_SetCloudSigner_GovernanceOnly() public {
        address newSigner = address(0x5678);
        verifier.setCloudSigner(newSigner);
        assertEq(verifier.cloudSigner(), newSigner);
    }

    function test_SetFccSigner_ZeroAddress_Reverts() public {
        vm.expectRevert(ZukoMultiProverVerifier.ZeroAddress.selector);
        verifier.setFccSigner(address(0));
    }

    function test_TransferGovernance() public {
        address newGov = address(0xBEEF);
        verifier.transferGovernance(newGov);
        assertEq(verifier.governance(), newGov);

        // Old governance (this) should no longer work
        vm.expectRevert(ZukoMultiProverVerifier.NotGovernance.selector);
        verifier.setFccSigner(address(0x1));
    }
}
