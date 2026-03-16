// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library FeeComputation {
    uint24 public constant BASE_FEE = 3000; // 30 bps (in hundredths of a bip)
    uint24 public constant MIN_FEE = 100; // 1 bps
    uint24 public constant MAX_FEE = 50000; // 500 bps

    /// @notice Compute the fee for tokenIn given its peg confidence
    /// @param confidence Peg confidence [0, 100]. 100 = fully pegged.
    /// @return fee uint24 fee in hundredths of a bip (v4 units)
    function computeTokenInFee(
        uint8 confidence
    ) internal pure returns (uint24 fee) {
        if (confidence >= 90) {
            fee = BASE_FEE;
        } else if (confidence >= 70) {
            // fee = BASE_FEE * (1 + (90 - c) * 0.015)
            // 0.015 = 15 / 1000
            uint256 delta = 90 - confidence;
            fee = uint24(BASE_FEE + (BASE_FEE * delta * 15) / 1000);
        } else if (confidence >= 50) {
            // fee = BASE_FEE * (1 + (90 - c) * 0.03)
            // 0.03 = 30 / 1000
            uint256 delta = 90 - confidence;
            fee = uint24(BASE_FEE + (BASE_FEE * delta * 30) / 1000);
        } else {
            // fee = BASE_FEE * (1 + (90 - c) * 0.05)
            // 0.05 = 50 / 1000
            uint256 delta = 90 - confidence;
            fee = uint24(BASE_FEE + (BASE_FEE * delta * 50) / 1000);
        }

        if (fee < MIN_FEE) {
            fee = MIN_FEE;
        } else if (fee > MAX_FEE) {
            fee = MAX_FEE;
        }
    }

    /// @notice Compute the fee for tokenOut given its peg confidence
    /// @dev Lower confidence on tokenOut = cheaper to buy (incentivize rescue arb)
    function computeTokenOutFee(
        uint8 confidence
    ) internal pure returns (uint24 fee) {
        // fee = BASE_FEE * (c / 100)
        uint256 computed = (uint256(BASE_FEE) * confidence) / 100;
        fee = uint24(computed);

        if (fee < MIN_FEE) {
            fee = MIN_FEE;
        } else if (fee > MAX_FEE) {
            fee = MAX_FEE;
        }
    }

    /// @notice Select which fee applies given swap direction and per-token confidence
    /// @param zeroForOne true if token0 → token1
    /// @param confidence0 peg confidence of token0
    /// @param confidence1 peg confidence of token1
    function selectFee(
        bool zeroForOne,
        uint8 confidence0,
        uint8 confidence1
    ) internal pure returns (uint24 fee) {
        // zeroForOne: token0 is tokenIn, token1 is tokenOut
        uint8 cIn = zeroForOne ? confidence0 : confidence1;
        uint8 cOut = zeroForOne ? confidence1 : confidence0;

        uint24 feeIn = computeTokenInFee(cIn);
        uint24 feeOut = computeTokenOutFee(cOut);

        // take the higher of the two computed fees (conservative LP protection)
        return feeIn > feeOut ? feeIn : feeOut;
    }
}
