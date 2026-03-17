// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {HookMiner} from "../test/utils/HookMiner.sol";
import {Deployers} from "test/utils/Deployers.sol";

import {PegSentinelHook} from "../src/PegSentinelHook.sol";
import {PegSentinelReceiver} from "../src/PegSentinelReceiver.sol";
import {PegSentinelVault} from "../src/PegSentinelVault.sol";
import {LendingAdapter} from "../src/libraries/LendingAdapter.sol";

/**
 * Unichain deployment script.
 *
 * Deploy order:
 * - Hook (receiver = address(0), owner = EOA) mined to correct hook flags
 * - Receiver (points to hook, allows Reactive callbacks)
 * - Hook.setReceiver(receiver) (one-time)
 * - LendingAdapter + Vault
 * - Hook.setVault(vault) (one-time)
 *
 * Env vars:
 * - DEPLOYER_PRIVATE_KEY: private key used for broadcasting
 * - REACTIVE_CONTRACT: authorized msg.sender for PegSentinelReceiver.updateConfidence() on Unichain
 * - VAULT_ASSET: ERC20 asset token address for PegSentinelVault (typically USDC on Unichain)
 * - VAULT_NAME (optional)
 * - VAULT_SYMBOL (optional)
 */
contract DeployScript is Script, Deployers {
    function _etch(address, bytes memory) internal pure override {
        revert("Etch not supported on live networks");
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.addr(pk);

        address reactiveContract = vm.envAddress("REACTIVE_CONTRACT");
        address vaultAsset = vm.envAddress("VAULT_ASSET");
        string memory vaultName = vm.envOr(
            "VAULT_NAME",
            string("Peg Sentinel Vault")
        );
        string memory vaultSymbol = vm.envOr("VAULT_SYMBOL", string("psVLT"));

        deployArtifacts(); // resolves canonical V4 addresses for this chain

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(
            poolManager,
            address(0), // receiver set after deploying PegSentinelReceiver
            owner
        );

        (address hookAddress, bytes32 hookSalt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(PegSentinelHook).creationCode,
            constructorArgs
        );

        vm.startBroadcast(pk);

        PegSentinelHook hook = new PegSentinelHook{salt: hookSalt}(
            IPoolManager(address(poolManager)),
            address(0),
            owner
        );
        require(address(hook) == hookAddress, "hook address mismatch");

        PegSentinelReceiver receiver = new PegSentinelReceiver(
            address(hook),
            reactiveContract,
            owner
        );

        hook.setReceiver(address(receiver));

        LendingAdapter lendingAdapter = new LendingAdapter();
        PegSentinelVault vault = new PegSentinelVault(
            IERC20(vaultAsset),
            vaultName,
            vaultSymbol,
            address(hook),
            lendingAdapter
        );
        hook.setVault(address(vault));

        vm.stopBroadcast();

        console2.log("=== PegSentinel Unichain Deployment ===");
        console2.log("owner");
        console2.logAddress(owner);
        console2.log("hook");
        console2.logAddress(address(hook));
        console2.log("receiver");
        console2.logAddress(address(receiver));
        console2.log("vault");
        console2.logAddress(address(vault));
        console2.log("lendingAdapter");
        console2.logAddress(address(lendingAdapter));
        console2.log("vaultAsset");
        console2.logAddress(vaultAsset);
        console2.log("reactiveContract");
        console2.logAddress(reactiveContract);
    }
}

