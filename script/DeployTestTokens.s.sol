// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/**
 * Deploys mock DAI and USDT tokens on Unichain Sepolia for pool testing.
 * Mints an initial supply to the deployer.
 *
 * Env vars:
 * - DEPLOYER_PRIVATE_KEY: private key used for broadcasting
 *
 * Usage:
 *   forge script script/DeployTestTokens.s.sol:DeployTestTokensScript \
 *     --rpc-url "$UNICHAIN_SEPOLIA_RPC" --broadcast
 */
contract DeployTestTokensScript is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockERC20 dai = new MockERC20("Mock DAI", "DAI", 18);
        MockERC20 usdt = new MockERC20("Mock USDT", "USDT", 6);

        // Mint initial supply to deployer
        dai.mint(deployer, 1_000_000e18);
        usdt.mint(deployer, 1_000_000e6);

        vm.stopBroadcast();

        console2.log("=== Test Token Deployment ===");
        console2.log("DAI:");
        console2.logAddress(address(dai));
        console2.log("USDT:");
        console2.logAddress(address(usdt));
        console2.log("Deployer:");
        console2.logAddress(deployer);
    }
}
