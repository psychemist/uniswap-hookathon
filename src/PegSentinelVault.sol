// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    ERC4626
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPegSentinelVault} from "./interfaces/IPegSentinelVault.sol";
import {ILendingAdapter} from "./interfaces/ILendingAdapter.sol";

contract PegSentinelVault is ERC4626, IPegSentinelVault {
    address public immutable hook;
    ILendingAdapter public lendingAdapter;

    uint256 public totalTrackedLiquidity;
    uint256 public accruedYield;

    error OnlyHook();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _hook,
        ILendingAdapter _adapter
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        hook = _hook;
        lendingAdapter = _adapter;
    }

    function setLendingAdapter(ILendingAdapter _adapter) external {
        lendingAdapter = _adapter;
    }

    // Underlying asset denominated in token0 units.
    function totalAssets() public view override returns (uint256) {
        // Assets = idle tokens in vault + lending adapter + estimated value of LP
        uint256 lent = address(lendingAdapter) != address(0)
            ? lendingAdapter.totalDeposited(asset())
            : 0;

        return
            super.totalAssets() + totalTrackedLiquidity + accruedYield + lent;
    }

    // --- IPegSentinelVault ---

    function onLiquidityAdded(
        address sender,
        PoolKey calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyHook {
        // BalanceDelta sign conventions depend on call context (caller vs pool).
        // For LP share accounting we care about magnitude of token0 moved.
        int128 delta0 = delta.amount0();
        uint256 amount0Added = delta0 < 0
            ? uint256(uint128(-delta0))
            : uint256(uint128(delta0));

        if (amount0Added > 0) {
            uint256 shares = previewDeposit(amount0Added);
            totalTrackedLiquidity += amount0Added;
            _mint(sender, shares);
        }
    }

    function onLiquidityRemoved(
        address sender,
        PoolKey calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyHook {
        // For LP share accounting we care about magnitude of token0 moved.
        int128 delta0 = delta.amount0();
        uint256 amount0Removed = delta0 < 0
            ? uint256(uint128(-delta0))
            : uint256(uint128(delta0));

        if (amount0Removed > 0) {
            uint256 shares = previewWithdraw(amount0Removed);
            totalTrackedLiquidity -= amount0Removed;
            _burn(sender, shares);
        }
    }

    function onFeeAccrued(
        PoolKey calldata,
        BalanceDelta feeDelta
    ) external override onlyHook {
        // feeDelta is now expected to contain ONLY the fee amounts (calculated by hook)
        int128 delta0 = feeDelta.amount0();
        if (delta0 > 0) {
            accruedYield += uint256(uint128(delta0));
        }
    }

    // --- Rehypothecation ---

    function rehypothecate(uint256 amount) external {
        // Idle liquidity goes to lending adapter
        IERC20(asset()).approve(address(lendingAdapter), amount);
        lendingAdapter.deposit(asset(), amount);
    }

    function recall(uint256 shares) external {
        lendingAdapter.withdraw(asset(), shares);
    }
}
