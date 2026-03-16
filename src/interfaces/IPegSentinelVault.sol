// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

interface IPegSentinelVault {
    function onLiquidityAdded(
        address sender,
        PoolKey calldata key,
        BalanceDelta delta,
        bytes calldata hookData
    ) external;

    function onLiquidityRemoved(
        address sender,
        PoolKey calldata key,
        BalanceDelta delta,
        bytes calldata hookData
    ) external;

    function onFeeAccrued(PoolKey calldata key, BalanceDelta feeDelta) external;
}
