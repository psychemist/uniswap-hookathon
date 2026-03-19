// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {PegSentinelReactive} from "../src/PegSentinelReactive.sol";

/**
 * Reactive Lasna deployment script for the RSC.
 *
 * Env vars:
 * - DEPLOYER_PRIVATE_KEY: private key used for broadcasting on Reactive Lasna
 * - UNICHAIN_RECEIVER: PegSentinelReceiver address on Unichain Sepolia
 * - UNICHAIN_USDC: bridged USDC token address on Unichain Sepolia
 * - UNICHAIN_DAI: bridged DAI token address on Unichain Sepolia
 * - UNICHAIN_USDT: bridged USDT token address on Unichain Sepolia
 */
contract DeployReactiveScript is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address unichainReceiver = vm.envAddress("UNICHAIN_RECEIVER");
        address unichainUSDC = vm.envAddress("UNICHAIN_USDC");
        address unichainDAI = vm.envAddress("UNICHAIN_DAI");
        address unichainUSDT = vm.envAddress("UNICHAIN_USDT");

        vm.startBroadcast(pk);
        PegSentinelReactive rsc = new PegSentinelReactive(
            unichainReceiver,
            unichainUSDC,
            unichainDAI,
            unichainUSDT
        );
        vm.stopBroadcast();

        console2.log("=== PegSentinel Reactive Deployment ===");
        console2.log("rsc");
        console2.logAddress(address(rsc));
        console2.log("unichainReceiver");
        console2.logAddress(unichainReceiver);
    }
}

