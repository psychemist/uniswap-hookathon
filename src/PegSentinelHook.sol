// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {
    SwapParams,
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {FeeComputation} from "./libraries/FeeComputation.sol";
import {IPegSentinelVault} from "./interfaces/IPegSentinelVault.sol";

contract PegSentinelHook is BaseHook {
    using LPFeeLibrary for uint24;

    // --- Storage ---

    /// @notice Peg confidence per token address. 100 = fully pegged.
    mapping(address token => uint8 confidence) public pegConfidence;

    /// @notice Address authorized to update peg confidence scores
    address public immutable receiver;

    /// @notice Address of the ERC-4626 vault for LP shares
    address public vault;

    // Events
    event PegConfidenceUpdated(
        address indexed token,
        uint8 oldConfidence,
        uint8 newConfidence
    );
    event VaultSet(address indexed vault);

    // Errors
    error OnlyReceiver();
    error OnlyVault();
    error InvalidConfidence();
    error VaultAlreadySet();

    constructor(
        IPoolManager _poolManager,
        address _receiver
    ) BaseHook(_poolManager) {
        receiver = _receiver;
        // initialize all known stablecoins to confidence 100
        // Currently initializing for Unichain Sepolia USDC + Mock DAI/USDT
        pegConfidence[0x31d0220469e10c4E71834a79b1f276d740d3768F] = 100; // USDC
        pegConfidence[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 100; // Mock DAI
        pegConfidence[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 100; // Mock USDT
    }

    // --- Hook Permissions ---

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true, // mint vault shares
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true, // burn vault shares
                beforeSwap: true, // apply asymmetric fees
                afterSwap: true, // accrue yield
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // --- Confidence Management ---

    /// @notice Called by PegSentinelReceiver with updated peg confidence
    function updatePegConfidence(address token, uint8 confidence) external {
        if (msg.sender != receiver) revert OnlyReceiver();
        uint8 old = pegConfidence[token];
        pegConfidence[token] = confidence;
        emit PegConfidenceUpdated(token, old, confidence);
    }

    /// @notice One-time vault registration
    function setVault(address _vault) external {
        if (vault != address(0)) revert VaultAlreadySet();
        vault = _vault;
        emit VaultSet(_vault);
    }

    // --- Hook Implementations ---

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint8 c0 = pegConfidence[Currency.unwrap(key.currency0)];
        uint8 c1 = pegConfidence[Currency.unwrap(key.currency1)];

        uint24 fee = FeeComputation.selectFee(params.zeroForOne, c0, c1);

        // Return 0 if we weren't instructed to override with a fee update flag?
        // No! The DYNAMIC_FEE_FLAG is enforced via pool key initialization, and we OR the OVERRIDE flag to charge the fee.
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (vault != address(0)) {
            IPegSentinelVault(vault).onLiquidityAdded(
                sender,
                key,
                delta,
                hookData
            );
        }
        return (
            BaseHook.afterAddLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (vault != address(0)) {
            IPegSentinelVault(vault).onLiquidityRemoved(
                sender,
                key,
                delta,
                hookData
            );
        }
        return (
            BaseHook.afterRemoveLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (vault != address(0)) {
            IPegSentinelVault(vault).onFeeAccrued(key, delta);
        }
        return (BaseHook.afterSwap.selector, 0);
    }
}
