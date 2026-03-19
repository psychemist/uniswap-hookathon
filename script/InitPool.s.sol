// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

contract InitPoolScript is Script {
    IPositionManager constant POSITION_MANAGER =
        IPositionManager(0xf969Aee60879C54bAAed9F3eD26147Db216Fd664);
    IPermit2 constant PERMIT2 =
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    struct PoolCfg {
        address t0;
        address t1;
        uint256 amt0;
        uint256 amt1;
        uint160 sqrtPriceX96;
        int24   tickSpacing;
        address hook;
        address owner;
    }

    function _buildPoolKey(PoolCfg memory c) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0:   Currency.wrap(c.t0),
            currency1:   Currency.wrap(c.t1),
            fee:         LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: c.tickSpacing,
            hooks:       IHooks(c.hook)
        });
    }

    function _approve(address t0, address t1) internal {
        IERC20(t0).approve(address(PERMIT2), type(uint256).max);
        IERC20(t1).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(t0, address(POSITION_MANAGER), type(uint160).max, type(uint48).max);
        PERMIT2.approve(t1, address(POSITION_MANAGER), type(uint160).max, type(uint48).max);
    }

    function _addLiquidity(PoolCfg memory c, PoolKey memory poolKey) internal {
        int24 currentTick = TickMath.getTickAtSqrtPrice(c.sqrtPriceX96);
        int24 tickLower = (currentTick - 750 * c.tickSpacing) / c.tickSpacing * c.tickSpacing;
        int24 tickUpper = (currentTick + 750 * c.tickSpacing) / c.tickSpacing * c.tickSpacing;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            c.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            c.amt0,
            c.amt1
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            poolKey, tickLower, tickUpper,
            liquidity, c.amt0 + 1, c.amt1 + 1,
            c.owner, abi.encode(c.owner)
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, c.owner);
        params[3] = abi.encode(poolKey.currency1, c.owner);

        POSITION_MANAGER.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 3600
        );
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        PoolCfg memory c;
        c.owner        = vm.addr(pk);
        c.hook         = vm.envAddress("HOOK");
        c.sqrtPriceX96 = uint160(vm.envOr("STARTING_PRICE_X96", uint256(2 ** 96)));
        c.tickSpacing  = int24(int256(vm.envOr("TICK_SPACING", uint256(10))));
        c.amt0         = vm.envOr("LIQ_TOKEN0", uint256(100e18));
        c.amt1         = vm.envOr("LIQ_TOKEN1", uint256(100e18));

        address tokenA = vm.envAddress("TOKEN0");
        address tokenB = vm.envAddress("TOKEN1");

        (c.t0, c.t1, c.amt0, c.amt1) = tokenA < tokenB
            ? (tokenA, tokenB, c.amt0, c.amt1)
            : (tokenB, tokenA, c.amt1, c.amt0);

        PoolKey memory poolKey = _buildPoolKey(c);

        vm.startBroadcast(pk);
        _approve(c.t0, c.t1);
        POSITION_MANAGER.initializePool(poolKey, c.sqrtPriceX96);
        _addLiquidity(c, poolKey);
        vm.stopBroadcast();

        console2.log("Pool initialized. Hook:", c.hook);
        console2.log("token0:", c.t0, "token1:", c.t1);
    }
}