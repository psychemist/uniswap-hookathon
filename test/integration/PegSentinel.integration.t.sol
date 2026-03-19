// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {
    Currency,
    CurrencyLibrary
} from "@uniswap/v4-core/src/types/Currency.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {PegSentinelHook} from "../../src/PegSentinelHook.sol";
import {PegSentinelVault} from "../../src/PegSentinelVault.sol";
import {PegSentinelReceiver} from "../../src/PegSentinelReceiver.sol";
import {LendingAdapter} from "../../src/libraries/LendingAdapter.sol";
import {FeeComputation} from "../../src/libraries/FeeComputation.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {EasyPosm} from "../utils/libraries/EasyPosm.sol";
import {
    IPositionManager
} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract PegSentinelIntegrationTest is BaseTest {
    using EasyPosm for IPositionManager;
    using LPFeeLibrary for uint24;

    uint256 constant MIN_UPDATE_INTERVAL = 100;

    PegSentinelHook hook;
    PegSentinelVault vault;
    PegSentinelReceiver receiver;
    LendingAdapter lendingAdapter;

    Currency usdc;
    Currency dai;
    PoolKey poolKey;

    address alice;
    address reactiveContract = address(0xBBBB);

    uint256 unichainFork;
    uint256 mainnetFork;

    function setUp() public {
        // Optional fork setup. If RPC env vars are not set, tests run locally.
        string memory unichainRpc = vm.envOr(
            "UNICHAIN_SEPOLIA_RPC",
            string("")
        );
        string memory mainnetRpc = vm.envOr("MAINNET_RPC", string(""));

        if (bytes(unichainRpc).length != 0) {
            unichainFork = vm.createSelectFork(unichainRpc);
        }
        if (bytes(mainnetRpc).length != 0) {
            mainnetFork = vm.createFork(mainnetRpc);
        }

        deployArtifactsAndLabel();
        (usdc, dai) = deployCurrencyPair();

        // Receiver enforces MIN_UPDATE_INTERVAL starting from block 0.
        // Ensure we're past the initial window so the first update can succeed.
        vm.roll(101);

        // Use the test contract as LP + swapper since Deployers.mint/approvals
        // are configured for address(this) by default.
        alice = address(this);

        // 1. Deploy Receiver
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x7777 << 144)
        );

        receiver = new PegSentinelReceiver(
            hookAddress,
            reactiveContract,
            address(this)
        );

        // 2. Deploy Hook
        bytes memory constructorArgs = abi.encode(
            poolManager,
            address(receiver),
            address(this)
        );
        deployCodeTo(
            "PegSentinelHook.sol:PegSentinelHook",
            constructorArgs,
            hookAddress
        );
        hook = PegSentinelHook(hookAddress);

        // 3. Deploy Lending Adapter and Vault
        lendingAdapter = new LendingAdapter();
        vault = new PegSentinelVault(
            IERC20(Currency.unwrap(usdc)),
            "Peg Sentinel USDC",
            "psUSDC",
            address(hook),
            lendingAdapter
        );
        hook.setVault(address(vault));

        // 4. Initialize Pool
        poolKey = PoolKey(
            usdc,
            dai,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            60,
            IHooks(hook)
        );
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Initialize confidences for the dynamically deployed test tokens.
        // PegSentinelHook constructor only seeds a few known addresses; without this,
        // pegConfidence defaults to 0 (max penalty) for our local test currencies.
        vm.startPrank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 100);
        receiver.updateConfidence(Currency.unwrap(dai), 100);
        vm.stopPrank();

        // Move past the per-token rate limit window so tests can freely
        // simulate subsequent confidence updates without flaking.
        vm.roll(block.number + MIN_UPDATE_INTERVAL + 1);

        // Setup Alice
        vm.label(alice, "Alice");

        // PoolManager may attempt to pull via ERC20.transferFrom during swap settlement.
        IERC20(Currency.unwrap(usdc)).approve(address(poolManager), type(uint256).max);
        IERC20(Currency.unwrap(dai)).approve(address(poolManager), type(uint256).max);
    }

    function _swap(
        bool zeroForOne,
        int256 amountSpecified,
        address swapper
    ) internal returns (BalanceDelta delta) {
        vm.startPrank(swapper);
        delta = swapRouter.swap(
            amountSpecified,
            0,
            zeroForOne,
            poolKey,
            "",
            swapper,
            block.timestamp
        );
        vm.stopPrank();
    }

    function _addLiquidity(address lp) internal {
        vm.startPrank(lp);
        positionManager.mint(
            poolKey,
            TickMath.minUsableTick(60),
            TickMath.maxUsableTick(60),
            100e18,
            200e18,
            200e18,
            lp,
            block.timestamp,
            abi.encode(lp)
        );
        vm.stopPrank();

        assertTrue(vault.balanceOf(lp) > 0);
    }

    function testSanity_AllowancesAndBalances() public view {
        // Balances
        assertTrue(IERC20(Currency.unwrap(usdc)).balanceOf(alice) > 1e18);
        assertTrue(IERC20(Currency.unwrap(dai)).balanceOf(alice) > 1e18);

        // Allowances (Solmate ERC20 exposes allowance mapping as a public getter)
        assertEq(
            MockERC20(Currency.unwrap(usdc)).allowance(alice, address(poolManager)),
            type(uint256).max
        );
        assertEq(
            MockERC20(Currency.unwrap(dai)).allowance(alice, address(poolManager)),
            type(uint256).max
        );
    }

    // Scenario 1: Normal conditions
    function testNormalConditions() public {
        _addLiquidity(alice);

        // Perform swap under normal (high-confidence) conditions
        uint256 yieldBefore = vault.accruedYield();
        _swap(true, -1e18, alice);

        // Vault accruedYield should increase after a swap
        assertTrue(vault.accruedYield() > 0);
        assertTrue(vault.accruedYield() >= yieldBefore);
    }

    // Scenario 2: Depeg event
    function testDepegEvent() public {
        _addLiquidity(alice);

        // Compare under identical pool state using snapshots.

        // --- USDC -> DAI (should worsen when USDC confidence is low) ---
        uint256 snap0 = vm.snapshotState();
        uint256 daiBefore = IERC20(Currency.unwrap(dai)).balanceOf(alice);
        _swap(true, -1e18, alice);
        uint256 amountOutNormal_USDCtoDAI = IERC20(Currency.unwrap(dai)).balanceOf(alice) - daiBefore;
        vm.revertToState(snap0);

        vm.prank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 60);
        daiBefore = IERC20(Currency.unwrap(dai)).balanceOf(alice);
        _swap(true, -1e18, alice);
        uint256 amountOutDepeg_USDCtoDAI = IERC20(Currency.unwrap(dai)).balanceOf(alice) - daiBefore;
        assertTrue(amountOutDepeg_USDCtoDAI < amountOutNormal_USDCtoDAI);

        // --- DAI -> USDC (should improve when USDC confidence is low) ---
        uint256 snap1 = vm.snapshotState();
        uint256 usdcBefore = IERC20(Currency.unwrap(usdc)).balanceOf(alice);
        _swap(false, -1e18, alice);
        uint256 amountOutNormal_DAItoUSDC = IERC20(Currency.unwrap(usdc)).balanceOf(alice) - usdcBefore;
        vm.revertToState(snap1);

        // Receiver rate-limits updates per token; advance blocks before sending a second USDC update.
        vm.roll(block.number + MIN_UPDATE_INTERVAL + 1);
        vm.prank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 60);
        usdcBefore = IERC20(Currency.unwrap(usdc)).balanceOf(alice);
        _swap(false, -1e18, alice);
        uint256 amountOutDepeg_DAItoUSDC = IERC20(Currency.unwrap(usdc)).balanceOf(alice) - usdcBefore;
        // With conservative fee selection (max of tokenIn/tokenOut fee), this direction
        // should not become worse when only the output token is depegged.
        assertTrue(amountOutDepeg_DAItoUSDC >= amountOutNormal_DAItoUSDC);
    }

    // Scenario 3: Multiple stablecoins
    function testMultipleStablecoins() public {
        _addLiquidity(alice);

        // USDC confidence 60, DAI confidence 100
        vm.startPrank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 60);
        receiver.updateConfidence(Currency.unwrap(dai), 100);
        vm.stopPrank();

        // Under a USDC depeg, USDC->DAI should be the "worse" direction than DAI->USDC.
        uint256 snap = vm.snapshotState();
        uint256 balanceBeforeDAI = IERC20(Currency.unwrap(dai)).balanceOf(alice);
        _swap(true, -1e18, alice);
        uint256 amountOut_USDCtoDAI = IERC20(Currency.unwrap(dai)).balanceOf(alice) -
            balanceBeforeDAI;
        vm.revertToState(snap);

        uint256 balanceBeforeUSDC = IERC20(Currency.unwrap(usdc)).balanceOf(alice);
        _swap(false, -1e18, alice);
        uint256 amountOut_DAItoUSDC = IERC20(Currency.unwrap(usdc)).balanceOf(alice) -
            balanceBeforeUSDC;

        assertTrue(amountOut_USDCtoDAI < amountOut_DAItoUSDC);
    }

    // Scenario 4: Rate limiting
    function testRateLimitingIntegration() public {
        vm.prank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 80);

        // Update again in same block should fail
        vm.expectRevert();
        vm.prank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 70);

        // Advance MIN_UPDATE_INTERVAL + 1 blocks
        vm.roll(block.number + MIN_UPDATE_INTERVAL + 1);
        vm.prank(reactiveContract);
        receiver.updateConfidence(Currency.unwrap(usdc), 70);
        assertEq(hook.pegConfidence(Currency.unwrap(usdc)), 70);
    }

    // Scenario 5: Vault ERC-4626 compliance
    function testVaultComplianceIntegration() public {
        IERC20(Currency.unwrap(usdc)).approve(address(vault), 10e18);
        vault.deposit(10e18, alice);
        uint256 shares = vault.balanceOf(alice);
        assertEq(shares, 10e18);

        // Generate some yield
        testNormalConditions();

        // totalAssets should increase
        assertTrue(vault.totalAssets() > 10e18);

        // Alice redeem some shares
        uint256 redeemed = vault.redeem(1e18, alice, alice);
        assertTrue(redeemed > 1e18);
    }
}
