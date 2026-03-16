// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library PegScoring {
    int256 public constant CHAINLINK_PRECISION = 1e8; // Chainlink uses 8 decimals
    int256 public constant PEG_TARGET = 1e8; // $1.00 in 8-decimal units

    uint8 public constant MAX_SCORE = 100;
    uint8 public constant MIN_SCORE = 0;

    // Deviation thresholds in bps of CHAINLINK_PRECISION (1e8 * 1 / 10000 = 10000)
    // 0.05% = 5 bps = 50,000 in 8-decimals
    // 0.1% = 10 bps = 100,000 in 8-decimals
    int256 public constant DEVIATION_RECOVERY_UNITS = 50_000;
    int256 public constant DEVIATION_PENALTY_UNITS = 100_000;

    uint256 public constant LARGE_TRANSFER_THRESHOLD_LOW = 20_000_000e6; // $20M (USDC 6 dec)
    uint256 public constant LARGE_TRANSFER_THRESHOLD_HIGH = 50_000_000e6; // $50M

    int8 public constant DELTA_CHAINLINK_RECOVERY = 2;
    // 5 points per 0.1% above threshold
    int8 public constant DELTA_CHAINLINK_PENALTY_PER_BPS = -5; // Used effectively as -5 per 100,000 unit tier

    int8 public constant DELTA_TRANSFER_LOW = -3;
    int8 public constant DELTA_TRANSFER_HIGH = -8;
    int8 public constant DELTA_MAKERDAO_STRESS = -10;
    int8 public constant DELTA_TIME_RECOVERY = 1;

    uint256 public constant CALLBACK_THRESHOLD = 3; // min score delta to trigger callback
    uint256 public constant TIME_RECOVERY_BLOCK_INTERVAL = 1000;

    // Baseline allowed rate for MakerDAO fold
    int256 public constant MAKERDAO_STRESS_THRESHOLD = 1e27; // Baseline multiplier indicating high stress

    /// @notice Clamp a score delta application safely
    function clampScore(int256 rawScore) internal pure returns (uint8) {
        if (rawScore > int256(uint256(MAX_SCORE))) {
            return MAX_SCORE;
        } else if (rawScore < int256(uint256(MIN_SCORE))) {
            return MIN_SCORE;
        }
        return uint8(uint256(rawScore));
    }

    /// @notice Apply a Chainlink AnswerUpdated delta to an existing score
    function applyChainlinkDelta(
        uint8 currentScore,
        int256 answer
    ) internal pure returns (uint8 newScore) {
        int256 diff = answer > PEG_TARGET
            ? answer - PEG_TARGET
            : PEG_TARGET - answer;

        if (diff < DEVIATION_RECOVERY_UNITS) {
            // recovery signal
            return
                clampScore(
                    int256(uint256(currentScore)) + DELTA_CHAINLINK_RECOVERY
                );
        } else if (diff >= DEVIATION_PENALTY_UNITS) {
            // -5 per 0.1% above threshold
            int256 penaltyTiers = diff / DEVIATION_PENALTY_UNITS;
            int256 penalty = penaltyTiers * DELTA_CHAINLINK_PENALTY_PER_BPS;
            return clampScore(int256(uint256(currentScore)) + penalty);
        }

        return currentScore;
    }

    /// @notice Apply a large transfer delta to an existing score
    /// @param amount Transfer amount in the token's native decimals
    function applyTransferDelta(
        uint8 currentScore,
        uint256 amount
    ) internal pure returns (uint8 newScore) {
        if (amount >= LARGE_TRANSFER_THRESHOLD_HIGH) {
            return
                clampScore(int256(uint256(currentScore)) + DELTA_TRANSFER_HIGH);
        } else if (amount >= LARGE_TRANSFER_THRESHOLD_LOW) {
            return
                clampScore(int256(uint256(currentScore)) + DELTA_TRANSFER_LOW);
        }
        return currentScore;
    }

    /// @notice Apply MakerDAO fold stress delta
    function applyMakerDaoDelta(
        uint8 currentScore,
        int256 rate
    ) internal pure returns (uint8 newScore) {
        // Simple abs logic for rate (since fold can be negative depending on debt mechanics)
        int256 absRate = rate < 0 ? -rate : rate;
        if (absRate > MAKERDAO_STRESS_THRESHOLD) {
            return
                clampScore(
                    int256(uint256(currentScore)) + DELTA_MAKERDAO_STRESS
                );
        }
        return currentScore;
    }

    /// @notice Apply block-based time recovery
    function applyTimeRecovery(
        uint8 currentScore,
        uint256 blocksSinceLastNegative
    ) internal pure returns (uint8 newScore) {
        uint256 recoveryPeriods = blocksSinceLastNegative /
            TIME_RECOVERY_BLOCK_INTERVAL;
        int256 totalRecovery = int256(recoveryPeriods) * DELTA_TIME_RECOVERY;
        return clampScore(int256(uint256(currentScore)) + totalRecovery);
    }

    /// @notice Returns true if the score delta warrants firing a callback
    function shouldCallback(
        uint8 oldScore,
        uint8 newScore
    ) internal pure returns (bool) {
        int256 diff = int256(uint256(newScore)) - int256(uint256(oldScore));
        int256 absDiff = diff < 0 ? -diff : diff;
        return absDiff >= int256(CALLBACK_THRESHOLD);
    }
}
