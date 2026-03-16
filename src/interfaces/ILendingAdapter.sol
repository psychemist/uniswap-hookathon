// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILendingAdapter {
    function deposit(
        address token,
        uint256 amount
    ) external returns (uint256 shares);
    function withdraw(
        address token,
        uint256 shares
    ) external returns (uint256 amount);
    function totalDeposited(address token) external view returns (uint256);
}
