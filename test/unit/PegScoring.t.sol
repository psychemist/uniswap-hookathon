// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/libraries/PegScoring.sol";

contract PegScoringTest is Test {
    using PegScoring for uint8;

    function testClampNeverOverflows(int256 rawScore) public pure {
        uint8 clamped = PegScoring.clampScore(rawScore);
        assertTrue(
            clamped >= PegScoring.MIN_SCORE && clamped <= PegScoring.MAX_SCORE
        );
        if (rawScore > int256(uint256(PegScoring.MAX_SCORE)))
            assertEq(clamped, PegScoring.MAX_SCORE);
        if (rawScore < int256(uint256(PegScoring.MIN_SCORE)))
            assertEq(clamped, PegScoring.MIN_SCORE);
    }

    function testChainlinkFullPeg() public pure {
        uint8 newScore = PegScoring.applyChainlinkDelta(
            100,
            PegScoring.PEG_TARGET
        );
        // PEG_TARGET deviation is 0 (which is < DEVIATION_RECOVERY_UNITS)
        // so it applies recovery delta (+2). But it clamps at 100.
        assertEq(newScore, 100);
    }

    function testChainlinkSmallDeviation() public pure {
        // Deviation of 4 bps (40,000) (< 0.05%)
        int256 answer = PegScoring.PEG_TARGET + 40_000;
        uint8 newScore = PegScoring.applyChainlinkDelta(80, answer);
        assertEq(newScore, 82); // 80 + 2
    }

    function testChainlinkLargeDeviation() public pure {
        // Deviation of 0.25% (25bps) -> 250,000
        int256 answer = PegScoring.PEG_TARGET - 250_000;
        uint8 newScore = PegScoring.applyChainlinkDelta(80, answer);
        // Penalty = (250_000 / 100_000) = 2 tiers => 2 * -5 = -10
        assertEq(newScore, 70); // 80 - 10
    }

    function testLargeTransferLowThreshold() public pure {
        uint8 newScore = PegScoring.applyTransferDelta(
            80,
            PegScoring.LARGE_TRANSFER_THRESHOLD_LOW
        );
        assertEq(newScore, 77); // 80 - 3
    }

    function testLargeTransferHighThreshold() public pure {
        uint8 newScore = PegScoring.applyTransferDelta(
            80,
            PegScoring.LARGE_TRANSFER_THRESHOLD_HIGH + 1_000_000
        );
        assertEq(newScore, 72); // 80 - 8
    }

    function testTransferBelowThresholdNoEffect() public pure {
        uint8 newScore = PegScoring.applyTransferDelta(
            80,
            PegScoring.LARGE_TRANSFER_THRESHOLD_LOW - 1
        );
        assertEq(newScore, 80);
    }

    function testMakerDaoStress() public pure {
        uint8 newScore = PegScoring.applyMakerDaoDelta(
            80,
            PegScoring.MAKERDAO_STRESS_THRESHOLD + 1
        );
        assertEq(newScore, 70);

        newScore = PegScoring.applyMakerDaoDelta(
            80,
            -(PegScoring.MAKERDAO_STRESS_THRESHOLD + 1)
        );
        assertEq(newScore, 70);

        newScore = PegScoring.applyMakerDaoDelta(
            80,
            PegScoring.MAKERDAO_STRESS_THRESHOLD - 1
        );
        assertEq(newScore, 80);
    }

    function testTimeRecoveryDoesNotExceed100() public pure {
        uint8 newScore = PegScoring.applyTimeRecovery(90, 15000);
        // 15 periods = +15 -> 105, clamps to 100
        assertEq(newScore, 100);

        newScore = PegScoring.applyTimeRecovery(80, 2000); // 2 periods -> 82
        assertEq(newScore, 82);
    }

    function testCallbackThreshold() public pure {
        assertFalse(PegScoring.shouldCallback(80, 80));
        assertFalse(PegScoring.shouldCallback(80, 82)); // 2 < 3
        assertTrue(PegScoring.shouldCallback(80, 83)); // 3 == 3
        assertTrue(PegScoring.shouldCallback(80, 77)); // diff 3
        assertTrue(PegScoring.shouldCallback(80, 70)); // diff 10
    }
}
