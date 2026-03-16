// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingAdapter} from "../interfaces/ILendingAdapter.sol";

/**
 * @title LendingAdapter
 * @notice A concrete implementation of ILendingAdapter for use in Unichain lending markets.
 *         In this production-grade stub, we simulate deposits and withdrawals to an ERC-4626 vault
 *         or similar yield-bearing protocol.
 */
contract LendingAdapter is ILendingAdapter {
    mapping(address token => uint256 amount) public deposits;

    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount);

    /**
     * @notice Deposit idle liquidity into the lending protocol.
     * @param token The token to deposit.
     * @param amount The amount of tokens to deposit.
     * @return shares The amount of shares minted by the protocol.
     */
    function deposit(
        address token,
        uint256 amount
    ) external override returns (uint256 shares) {
        // Transfer assets from caller to this adapter
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        deposits[token] += amount;

        // In this mock-like concrete implementation, shares = amount (1:1 ratio)
        shares = amount;

        emit Deposited(token, amount);
    }

    /**
     * @notice Withdraw liquidity from the lending protocol.
     * @param token The token to withdraw.
     * @param shares The amount of shares to redeem.
     * @return amount The amount of tokens withdrawn.
     */
    function withdraw(
        address token,
        uint256 shares
    ) external override returns (uint256 amount) {
        // In this 1:1 implementation, amount = shares
        amount = shares;
        require(deposits[token] >= amount, "Insufficient deposits");

        deposits[token] -= amount;
        IERC20(token).transfer(msg.sender, amount);

        emit Withdrawn(token, amount);
    }

    /**
     * @notice Returns the total amount of a token deposited in the protocol.
     * @param token The token to query.
     * @return The total deposited amount.
     */
    function totalDeposited(
        address token
    ) external view override returns (uint256) {
        return deposits[token];
    }
}
