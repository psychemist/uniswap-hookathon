// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {Deployers} from "test/utils/Deployers.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

/**
 * Initializes a Uniswap v4 pool with the PegSentinel hook (DYNAMIC_FEE_FLAG)
 * and optionally mints an initial liquidity position.
 *
 * Env vars:
 * - DEPLOYER_PRIVATE_KEY: private key used for broadcasting
 * - HOOK: PegSentinelHook address
 * - TOKEN0: ERC20 address (one of the pool currencies)
 * - TOKEN1: ERC20 address (the other pool currency)
 * - STARTING_PRICE_X96 (optional, default = 2**96)
 * - TICK_SPACING (optional, default = 60)
 * - LIQ_TOKEN0 (optional, default = 100e18)
 * - LIQ_TOKEN1 (optional, default = 100e18)
 */
contract InitPoolScript is Script, Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    struct Config {
        address owner;
        address hook;
        address tokenA;
        address tokenB;
        uint160 startingPriceX96;
        int24 tickSpacing;
        uint256 amountA;
        uint256 amountB;
    }

    struct MintCfg {
        PoolKey poolKey;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidity;
        uint256 amount0Max;
        uint256 amount1Max;
        address recipient;
        bytes hookData;
    }

    function _etch(address, bytes memory) internal pure override {
        revert("Etch not supported on live networks");
    }

    function truncateTickSpacing(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        /// forge-lint: disable-next-line(divide-before-multiply)
        return ((tick / tickSpacing) * tickSpacing);
    }

    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            poolKey,
            _tickLower,
            _tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            recipient,
            hookData
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, recipient);
        params[3] = abi.encode(poolKey.currency1, recipient);

        return (actions, params);
    }

    function _mintLiquidityParams2(
        MintCfg memory m
    ) internal pure returns (bytes memory, bytes[] memory) {
        return
            _mintLiquidityParams(
                m.poolKey,
                m.tickLower,
                m.tickUpper,
                m.liquidity,
                m.amount0Max,
                m.amount1Max,
                m.recipient,
                m.hookData
            );
    }

    function _sortedPoolKeyAndAmounts(
        Config memory cfg
    ) internal pure returns (PoolKey memory poolKey, uint256 amount0, uint256 amount1) {
        require(cfg.tokenA != cfg.tokenB, "TOKEN0==TOKEN1");

        if (cfg.tokenA < cfg.tokenB) {
            poolKey = PoolKey({
                currency0: Currency.wrap(cfg.tokenA),
                currency1: Currency.wrap(cfg.tokenB),
                fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                tickSpacing: cfg.tickSpacing,
                hooks: IHooks(cfg.hook)
            });
            amount0 = cfg.amountA;
            amount1 = cfg.amountB;
        } else {
            poolKey = PoolKey({
                currency0: Currency.wrap(cfg.tokenB),
                currency1: Currency.wrap(cfg.tokenA),
                fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                tickSpacing: cfg.tickSpacing,
                hooks: IHooks(cfg.hook)
            });
            amount0 = cfg.amountB;
            amount1 = cfg.amountA;
        }
    }

    function _ticksAroundPrice(
        uint160 startingPriceX96,
        int24 tickSpacing
    ) internal pure returns (int24 tickLower, int24 tickUpper) {
        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPriceX96);
        tickLower = truncateTickSpacing(
            currentTick - 750 * tickSpacing,
            tickSpacing
        );
        tickUpper = truncateTickSpacing(
            currentTick + 750 * tickSpacing,
            tickSpacing
        );
    }

    function _buildPoolInitAndMintMulticall(
        Config memory cfg,
        uint256 deadline
    ) internal pure returns (PoolKey memory poolKey, bytes[] memory params) {
        (uint256 amount0Desired, uint256 amount1Desired) = (0, 0);
        (poolKey, amount0Desired, amount1Desired) = _sortedPoolKeyAndAmounts(cfg);

        (int24 tickLower, int24 tickUpper) = _ticksAroundPrice(
            cfg.startingPriceX96,
            cfg.tickSpacing
        );

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            cfg.startingPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        MintCfg memory m;
        m.poolKey = poolKey;
        m.tickLower = tickLower;
        m.tickUpper = tickUpper;
        m.liquidity = liquidity;
        m.amount0Max = amount0Desired + 1;
        m.amount1Max = amount1Desired + 1;
        m.recipient = cfg.owner;
        m.hookData = abi.encode(cfg.owner);

        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams2(
            m
        );

        params = new bytes[](2);
        params[0] = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "initializePool((address,address,uint24,int24,address),uint160,bytes)"
                )
            ),
            poolKey,
            cfg.startingPriceX96,
            m.hookData
        );
        params[1] = abi.encodeWithSelector(
            bytes4(keccak256("modifyLiquidities(bytes,uint256)")),
            abi.encode(actions, mintParams),
            deadline
        );
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.addr(pk);

        Config memory cfg;
        cfg.owner = owner;
        cfg.hook = vm.envAddress("HOOK");
        cfg.tokenA = vm.envAddress("TOKEN0");
        cfg.tokenB = vm.envAddress("TOKEN1");
        cfg.startingPriceX96 = uint160(
            vm.envOr("STARTING_PRICE_X96", uint256(2 ** 96))
        );
        cfg.tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        cfg.amountA = vm.envOr("LIQ_TOKEN0", uint256(100e18));
        cfg.amountB = vm.envOr("LIQ_TOKEN1", uint256(100e18));

        deployArtifacts();

        (PoolKey memory poolKey, bytes[] memory params) = _buildPoolInitAndMintMulticall(
            cfg,
            block.timestamp + 3600
        );

        vm.startBroadcast(pk);

        // Permit2 approvals for PositionManager pulls.
        IERC20(Currency.unwrap(poolKey.currency0)).approve(
            address(permit2),
            type(uint256).max
        );
        IERC20(Currency.unwrap(poolKey.currency1)).approve(
            address(permit2),
            type(uint256).max
        );
        IPermit2(address(permit2)).approve(
            Currency.unwrap(poolKey.currency0),
            address(positionManager),
            type(uint160).max,
            type(uint48).max
        );
        IPermit2(address(permit2)).approve(
            Currency.unwrap(poolKey.currency1),
            address(positionManager),
            type(uint160).max,
            type(uint48).max
        );

        positionManager.multicall(params);

        vm.stopBroadcast();

        console2.log("=== Pool initialized ===");
        console2.log("hook");
        console2.logAddress(cfg.hook);
        console2.log("currency0");
        console2.logAddress(Currency.unwrap(poolKey.currency0));
        console2.log("currency1");
        console2.logAddress(Currency.unwrap(poolKey.currency1));
    }
}

