// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/libraries/FeeComputation.sol";

contract FeeComputationTest is Test {
    using FeeComputation for uint8;

    function testFeeAtFullConfidence() public pure {
        uint24 feeIn = FeeComputation.computeTokenInFee(100);
        assertEq(feeIn, FeeComputation.BASE_FEE);
        uint24 feeOut = FeeComputation.computeTokenOutFee(100);
        assertEq(feeOut, FeeComputation.BASE_FEE);
    }

    function testFeeAtZeroConfidence() public pure {
        uint24 feeIn = FeeComputation.computeTokenInFee(0);
        // (90 - 0) * 50 = 4500
        // fee = 3000 + 3000 * 4500 / 1000 = 3000 + 13500 = 16500. Not hitting max fee.
        assertEq(feeIn, 16500);

        uint24 feeOut = FeeComputation.computeTokenOutFee(0);
        assertEq(feeOut, FeeComputation.MIN_FEE); // Clamped
    }

    function testFeeNeverBelowMin(uint8 confidence) public pure {
        vm.assume(confidence <= 100);
        uint24 feeIn = FeeComputation.computeTokenInFee(confidence);
        assertTrue(feeIn >= FeeComputation.MIN_FEE);

        uint24 feeOut = FeeComputation.computeTokenOutFee(confidence);
        assertTrue(feeOut >= FeeComputation.MIN_FEE);
    }

    function testFeeNeverAboveMax(uint8 confidence) public pure {
        vm.assume(confidence <= 100);
        uint24 feeIn = FeeComputation.computeTokenInFee(confidence);
        assertTrue(feeIn <= FeeComputation.MAX_FEE);

        uint24 feeOut = FeeComputation.computeTokenOutFee(confidence);
        assertTrue(feeOut <= FeeComputation.MAX_FEE);
    }

    function testFeeMonotonicallyIncreasingAsConfidenceDecreases() public pure {
        uint24 lastFee = FeeComputation.computeTokenInFee(100);
        for (uint8 c = 99; c <= 100; c--) {
            uint24 fee = FeeComputation.computeTokenInFee(c);
            assertTrue(fee >= lastFee);
            lastFee = fee;
            if (c == 0) break;
        }
    }

    function testFeeMonotonicallyDecreasingAsConfidenceDecreases() public pure {
        uint24 lastFee = FeeComputation.computeTokenOutFee(100);
        for (uint8 c = 99; c <= 100; c--) {
            uint24 fee = FeeComputation.computeTokenOutFee(c);
            assertTrue(fee <= lastFee);
            lastFee = fee;
            if (c == 0) break;
        }
    }

    function testSelectFeeZeroForOne() public pure {
        uint24 fee = FeeComputation.selectFee(true, 100, 50);
        // cIn = 100 -> feeIn = 3000
        // cOut = 50 -> feeOut = 3000 * 50 / 100 = 1500
        // return max(3000, 1500) = 3000
        assertEq(fee, 3000);

        fee = FeeComputation.selectFee(true, 50, 100);
        // cIn = 50 -> feeIn = 3000 + 3000 * 40 * 30 / 1000 = 3000 + 3600 = 6600
        // cOut = 100 -> feeOut = 3000
        // return max(6600, 3000) = 6600
        assertEq(fee, 6600);
    }

    function testSelectFeeOneForZero() public pure {
        uint24 fee = FeeComputation.selectFee(false, 100, 50);
        // cIn = 50 -> feeIn = 6600
        // cOut = 100 -> feeOut = 3000
        assertEq(fee, 6600);

        fee = FeeComputation.selectFee(false, 50, 100);
        // cIn = 100 -> feeIn = 3000
        // cOut = 50 -> feeOut = 1500
        assertEq(fee, 3000);
    }
}
