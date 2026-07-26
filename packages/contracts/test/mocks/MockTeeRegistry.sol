// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @notice Minimal mock of FCC's TeeExtensionRegistry.
 *         Allows tests to register and deregister code hashes to verify
 *         ZukoGuardian correctly checks its own registration before
 *         executing any instruction. This is the kill-switch test vector.
 */
contract MockTeeRegistry {
    mapping(bytes32 => bool) public registeredHashes;

    function registerHash(bytes32 codeHash) external {
        registeredHashes[codeHash] = true;
    }

    function deregisterHash(bytes32 codeHash) external {
        registeredHashes[codeHash] = false;
    }

    function isHashRegistered(bytes32 codeHash)
        external view returns (bool)
    {
        return registeredHashes[codeHash];
    }
}
