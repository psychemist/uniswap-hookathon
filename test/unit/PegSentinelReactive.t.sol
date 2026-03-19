// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PegSentinelReactive} from "../../src/PegSentinelReactive.sol";
import {IReactive} from "@reactive-network/interfaces/IReactive.sol";
import {
    ISystemContract
} from "@reactive-network/interfaces/ISystemContract.sol";

// Mock system contract for subscription ignoring
contract MockService {
    function subscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {}
}

contract PegSentinelReactiveTest is Test {
    PegSentinelReactive rsc;
    address receiver = address(0x111);

    address unichainUSDC = address(0x222);
    address unichainDAI = address(0x333);
    address unichainUSDT = address(0x444);

    address CHAINLINK_USDC = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address USDC_ERC20 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 constant ANSWER_UPDATED_TOPIC =
        0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f;
    bytes32 constant TRANSFER_TOPIC =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    event Callback(
        uint256 indexed chain_id,
        address indexed _contract,
        uint64 indexed gas_limit,
        bytes payload
    );

    function setUp() public {
        // Deploy mock service at the hardcoded address
        MockService mockService = new MockService();
        vm.etch(
            0x0000000000000000000000000000000000fffFfF,
            address(mockService).code
        );

        rsc = new PegSentinelReactive(
            receiver,
            unichainUSDC,
            unichainDAI,
            unichainUSDT
        );
    }

    function testHandleChainlinkUpdateFullPeg() public {
        // 1e8 is $1.00
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: CHAINLINK_USDC,
            topic_0: uint256(ANSWER_UPDATED_TOPIC),
            topic_1: 1e8,
            topic_2: 0,
            topic_3: 0,
            data: "",
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        // Current confidence is 100.
        // Peg target is 1e8, answer is 1e8.
        // Diff = 0. Diff < DEVIATION_RECOVERY_UNITS (50_000).
        // It applies +2 recovery. 100 + 2 clamped to 100.
        // Old=100, New=100. Diff=0 < 3 (CALLBACK_THRESHOLD).
        // No callback emitted!

        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 100);
    }

    function testHandleChainlinkUpdateDepeg() public {
        // Drop to $0.98 -> 98,000,000. Diff = 2_000,000.
        // DEVIATION_PENALTY_UNITS is 100_000 (0.1%).
        // Tiers = 20. Penalty = 20 * -5 = -100.
        // New confidence = 0.
        // Expected callback!
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: CHAINLINK_USDC,
            topic_0: uint256(ANSWER_UPDATED_TOPIC),
            topic_1: 98_000_000,
            topic_2: 0,
            topic_3: 0,
            data: "",
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        bytes memory payload = abi.encodeWithSignature(
            "updateConfidence(address,uint8)",
            unichainUSDC,
            0
        );
        vm.expectEmit(true, true, true, true);
        emit Callback(1301, receiver, 1000000, payload);

        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 0);
    }

    function testHandleChainlinkUpdateRecovery() public {
        // Set confidence artificially low
        testHandleChainlinkUpdateDepeg();

        // 1.00 -> Diff = 0 -> +2 recovery.
        // Old=0. New=2. Diff=2. Threshold is 3. NO callback expected on just one.
        // Let's trigger it twice, so it hits 4. Diff=4 > 3! Callback!
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: CHAINLINK_USDC,
            topic_0: uint256(ANSWER_UPDATED_TOPIC),
            topic_1: 1e8,
            topic_2: 0,
            topic_3: 0,
            data: "",
            block_number: 101, // No time recovery since last negative was block 100
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 2);

        log.block_number = 102;
        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 4);
    }

    function testHandleLargeTransferLow() public {
        // $25M transfer = > 20M = -3 confidence.
        // Old=100. New=97. Diff(100, 97) = 3. Thresh = 3. Callback!
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: USDC_ERC20,
            topic_0: uint256(TRANSFER_TOPIC),
            topic_1: 0,
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(25_000_000e6),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        bytes memory payload = abi.encodeWithSignature(
            "updateConfidence(address,uint8)",
            unichainUSDC,
            97
        );
        vm.expectEmit(true, true, true, true);
        emit Callback(1301, receiver, 1000000, payload);

        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 97);
    }

    function testHandleLargeTransferHigh() public {
        // $55M transfer = > 50M = -8 confidence.
        // Old=100. New=92. Diff = 8. Callback!
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: USDC_ERC20,
            topic_0: uint256(TRANSFER_TOPIC),
            topic_1: 0,
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(55_000_000e6),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        bytes memory payload = abi.encodeWithSignature(
            "updateConfidence(address,uint8)",
            unichainUSDC,
            92
        );
        vm.expectEmit(true, true, true, true);
        emit Callback(1301, receiver, 1000000, payload);

        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 92);
    }

    function testHandleSmallTransferNoEffect() public {
        // $50k transfer
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: USDC_ERC20,
            topic_0: uint256(TRANSFER_TOPIC),
            topic_1: 0,
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(50_000e6),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        rsc.react(log);
        assertEq(rsc.confidence(unichainUSDC), 100);
    }

    function testTimeRecoveryApplied() public {
        // Force drop
        testHandleLargeTransferHigh(); // confidence is 92 at block 100.
        assertEq(rsc.lastNegativeBlock(unichainUSDC), 100);

        // Advance 2100 blocks = 2 intervals = +2 confidence
        // Next action (small transfer) shouldn't trigger anything, but time recovery is applied first
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1,
            _contract: USDC_ERC20,
            topic_0: uint256(TRANSFER_TOPIC),
            topic_1: 0,
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(5_000e6),
            block_number: 2200,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        rsc.react(log);
        // From 92, +0 from transfer, +2 from time = 94.
        assertEq(rsc.confidence(unichainUSDC), 94);

        // However, if we advance 4000 blocks = 4 points. newScore = 94 + 0 + 4 = 98.
        // diff(92, 98) = 6 >= 3. Callback emitted, state saved!
        IReactive.LogRecord memory log2 = IReactive.LogRecord({
            chain_id: 1,
            _contract: USDC_ERC20,
            topic_0: uint256(TRANSFER_TOPIC),
            topic_1: 0,
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(5_000e6),
            block_number: 4100, // 4000 blocks since 100
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        bytes memory payload = abi.encodeWithSignature(
            "updateConfidence(address,uint8)",
            unichainUSDC,
            98
        );
        vm.expectEmit(true, true, true, true);
        emit Callback(1301, receiver, 1000000, payload);

        rsc.react(log2);

        assertEq(rsc.confidence(unichainUSDC), 98);
    }
}
