// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {PegSentinelHook} from "../src/PegSentinelHook.sol";

/// @notice Mines the address and deploys the PegSentinelHook.sol Hook contract
contract DeployHookScript is BaseScript {
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(
            poolManager,
            address(uint160(uint256(keccak256("receiver")))),
            msg.sender
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(PegSentinelHook).creationCode,
            constructorArgs
        );

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        PegSentinelHook counter = new PegSentinelHook{salt: salt}(
            poolManager,
            address(uint160(uint256(keccak256("receiver")))),
            msg.sender
        );
        vm.stopBroadcast();

        require(
            address(counter) == hookAddress,
            "DeployHookScript: Hook Address Mismatch"
        );
    }
}
