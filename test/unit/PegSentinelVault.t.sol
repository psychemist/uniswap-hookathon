// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PegSentinelVault} from "../../src/PegSentinelVault.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ILendingAdapter} from "../../src/interfaces/ILendingAdapter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary,
    toBalanceDelta
} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockLendingAdapter is ILendingAdapter {
    mapping(address => uint256) public deposits;

    function deposit(
        address token,
        uint256 amount
    ) external override returns (uint256) {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        deposits[token] += amount;
        return amount; // 1:1 shares
    }

    function withdraw(
        address token,
        uint256 shares
    ) external override returns (uint256) {
        deposits[token] -= shares;
        IERC20(token).transfer(msg.sender, shares);
        return shares;
    }

    function totalDeposited(
        address token
    ) external view override returns (uint256) {
        return deposits[token];
    }
}

contract PegSentinelVaultTest is Test {
    PegSentinelVault vault;
    MockERC20 token0;
    MockLendingAdapter adapter;
    address hook = address(0x1337);

    function setUp() public {
        token0 = new MockERC20("Token 0", "TK0");
        adapter = new MockLendingAdapter();
        vault = new PegSentinelVault(
            token0,
            "Peg Vault",
            "pegVLT",
            hook,
            adapter
        );
    }

    function testShareMintingOnFirstDeposit() public {
        vm.startPrank(hook);
        // Minting 100 liquidity
        BalanceDelta delta = toBalanceDelta(-100, -100);
        PoolKey memory key; // dummy

        vault.onLiquidityAdded(address(0xabc), key, delta, "");
        vm.stopPrank();

        assertEq(vault.balanceOf(address(0xabc)), 100);
        assertEq(vault.totalAssets(), 100);
    }

    function testShareMintingWithExistingShares() public {
        vm.startPrank(hook);
        BalanceDelta delta1 = toBalanceDelta(-100, -100);
        PoolKey memory key;
        vault.onLiquidityAdded(address(0xabc), key, delta1, "");

        // manually increase vault assets (yield)
        vault.onFeeAccrued(key, toBalanceDelta(100, 100)); // adds 100 to totalAssets -> total is 200

        // New deposit of 100 should mint 50 shares
        BalanceDelta delta2 = toBalanceDelta(-100, -100);
        vault.onLiquidityAdded(address(0xdef), key, delta2, "");
        vm.stopPrank();

        assertEq(vault.balanceOf(address(0xdef)), 50);
        assertEq(vault.totalAssets(), 300);
    }

    function testShareBurningReturnsProportionalAssets() public {
        vm.startPrank(hook);
        BalanceDelta delta1 = toBalanceDelta(-100, -100);
        PoolKey memory key;
        vault.onLiquidityAdded(address(0xabc), key, delta1, "");

        vault.onFeeAccrued(key, toBalanceDelta(100, 0)); // total assets 200

        // Remove 50 liquidity
        BalanceDelta delta2 = toBalanceDelta(50, 50);
        vault.onLiquidityRemoved(address(0xabc), key, delta2, "");
        vm.stopPrank();

        // 50 assets is approx 25% of 200 total assets.
        // Due to OZ's virtual shares offset (+1 to total supply and assets), it computes exactly 26 shares to burn
        // Balance should be 100 - 26 = 74 shares remaining.
        assertEq(vault.balanceOf(address(0xabc)), 74);
        assertEq(vault.totalAssets(), 150);
    }

    function testFeeAccrualIncreasesTotalAssets() public {
        vm.prank(hook);
        vault.onFeeAccrued(
            PoolKey(
                Currency.wrap(address(0)),
                Currency.wrap(address(0)),
                0,
                0,
                IHooks(address(0))
            ),
            toBalanceDelta(500, 0)
        );
        assertEq(vault.totalAssets(), 500);
    }

    function testRehypothecationDeposit() public {
        token0.mint(address(vault), 1000);
        vault.rehypothecate(1000);
        assertEq(adapter.totalDeposited(address(token0)), 1000);
        // Ensure totalAssets accurately includes adapter's balance
        assertEq(vault.totalAssets(), 1000);
    }

    function testRehypothecationWithdrawOnSwap() public {
        token0.mint(address(vault), 1000);
        vault.rehypothecate(1000);
        vault.recall(500);
        assertEq(adapter.totalDeposited(address(token0)), 500);
        assertEq(token0.balanceOf(address(vault)), 500);
        assertEq(vault.totalAssets(), 1000);
    }

    function testERC4626PreviewDepositEqualsDeposit(
        uint256 depositAssets
    ) public {
        vm.assume(depositAssets > 0 && depositAssets < 1e30);
        uint256 expectedShares = vault.previewDeposit(depositAssets);
        token0.mint(address(this), depositAssets);
        token0.approve(address(vault), depositAssets);
        uint256 actualShares = vault.deposit(depositAssets, address(this));
        assertEq(expectedShares, actualShares);
    }

    function testERC4626PreviewWithdrawEqualsWithdraw(
        uint256 withdrawAssets
    ) public {
        vm.assume(withdrawAssets > 0 && withdrawAssets < 1e30);
        token0.mint(address(this), withdrawAssets * 2);
        token0.approve(address(vault), withdrawAssets * 2);
        vault.deposit(withdrawAssets * 2, address(this));

        uint256 expectedShares = vault.previewWithdraw(withdrawAssets);
        uint256 actualShares = vault.withdraw(
            withdrawAssets,
            address(this),
            address(this)
        );
        assertEq(expectedShares, actualShares);
    }

    function testTotalAssetsNeverDecreasesWithoutWithdrawal(
        uint256 yield
    ) public {
        vm.assume(yield < 1e30);
        vm.startPrank(hook);
        BalanceDelta delta = toBalanceDelta(-100, -100);
        PoolKey memory key;
        vault.onLiquidityAdded(address(0xabc), key, delta, "");

        uint256 beforeAssets = vault.totalAssets();
        vault.onFeeAccrued(key, toBalanceDelta(int128(uint128(yield)), 0));
        uint256 afterAssets = vault.totalAssets();

        assertTrue(afterAssets >= beforeAssets);
        vm.stopPrank();
    }
}
