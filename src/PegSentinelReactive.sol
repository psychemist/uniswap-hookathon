// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    AbstractReactive
} from "@reactive-network/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive-network/interfaces/IReactive.sol";
import {PegScoring} from "./libraries/PegScoring.sol";

contract PegSentinelReactive is AbstractReactive {
    using PegScoring for uint8;

    // --- Configuration ---
    uint256 constant MAINNET_CHAIN_ID = 1;
    uint256 constant UNICHAIN_CHAIN_ID = 1301; // Sepolia testnet

    // Callback destination
    address public immutable receiverContract;

    // Monitored contracts
    address constant CHAINLINK_USDC =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant CHAINLINK_DAI = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant CHAINLINK_USDT =
        0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address constant USDC_ERC20 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI_ERC20 = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MAKERDAO_VAT = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B; // Mock/VAT

    // Topic0 hashes
    bytes32 constant ANSWER_UPDATED_TOPIC =
        0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f;
    bytes32 constant TRANSFER_TOPIC =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    bytes32 constant FOLD_TOPIC = keccak256("fold(bytes32,address,int256)"); // verify

    // --- State ---
    mapping(address token => uint8 confidence) public confidence;
    mapping(address token => uint8 lastReportedConfidence) public lastReportedConfidence;
    mapping(address token => uint256 block) public lastNegativeBlock;
    mapping(address mainnetContract => address unichainToken)
        public tokenMapping;

    constructor(
        address _receiver,
        address unichainUSDC,
        address unichainDAI,
        address unichainUSDT
    ) {
        receiverContract = _receiver;

        // Subscribe to Chainlink
        service.subscribe(
            MAINNET_CHAIN_ID,
            CHAINLINK_USDC,
            uint256(ANSWER_UPDATED_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        service.subscribe(
            MAINNET_CHAIN_ID,
            CHAINLINK_DAI,
            uint256(ANSWER_UPDATED_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        service.subscribe(
            MAINNET_CHAIN_ID,
            CHAINLINK_USDT,
            uint256(ANSWER_UPDATED_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to transfers
        service.subscribe(
            MAINNET_CHAIN_ID,
            USDC_ERC20,
            uint256(TRANSFER_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        service.subscribe(
            MAINNET_CHAIN_ID,
            DAI_ERC20,
            uint256(TRANSFER_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Subscribe to MakerDAO fold
        service.subscribe(
            MAINNET_CHAIN_ID,
            MAKERDAO_VAT,
            uint256(FOLD_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        // Map tokens
        tokenMapping[CHAINLINK_USDC] = unichainUSDC;
        tokenMapping[CHAINLINK_DAI] = unichainDAI;
        tokenMapping[CHAINLINK_USDT] = unichainUSDT;
        tokenMapping[USDC_ERC20] = unichainUSDC;
        tokenMapping[DAI_ERC20] = unichainDAI;
        tokenMapping[MAKERDAO_VAT] = unichainDAI; // Fold affects DAI

        // Initialize assumed full confidence
        confidence[unichainUSDC] = 100;
        confidence[unichainDAI] = 100;
        confidence[unichainUSDT] = 100;
        lastReportedConfidence[unichainUSDC] = 100;
        lastReportedConfidence[unichainDAI] = 100;
        lastReportedConfidence[unichainUSDT] = 100;
    }

    function react(LogRecord calldata log) external override {
        if (log.chain_id != MAINNET_CHAIN_ID) return;

        bytes32 topic0 = bytes32(log.topic_0);
        if (topic0 == ANSWER_UPDATED_TOPIC) {
            _handleChainlinkUpdate(
                log._contract,
                log.topic_1,
                log.block_number
            );
        } else if (topic0 == TRANSFER_TOPIC) {
            _handleTransfer(log._contract, log.data, log.block_number);
        } else if (topic0 == FOLD_TOPIC) {
            _handleMakerDaoFold(log.data, log.block_number);
        }
    }

    function _handleChainlinkUpdate(
        address feed,
        uint256 answerRaw,
        uint256 blockNumber
    ) internal {
        address unichainToken = tokenMapping[feed];
        if (unichainToken == address(0)) return;

        // The answer is represented as signed int256 in chainlink event
        int256 answer = int256(answerRaw);
        uint8 oldConfidence = confidence[unichainToken];

        uint8 newConfidence = PegScoring.applyChainlinkDelta(
            oldConfidence,
            answer
        );

        uint256 blocksSinceNegative = blockNumber -
            lastNegativeBlock[unichainToken];
        newConfidence = PegScoring.applyTimeRecovery(
            newConfidence,
            blocksSinceNegative
        );

        if (newConfidence < oldConfidence) {
            lastNegativeBlock[unichainToken] = blockNumber;
        }

        confidence[unichainToken] = newConfidence;

        if (
            PegScoring.shouldCallback(
                lastReportedConfidence[unichainToken],
                newConfidence
            )
        ) {
            lastReportedConfidence[unichainToken] = newConfidence;
            _emitCallback(unichainToken, newConfidence);
        }
    }

    function _handleTransfer(
        address contractAddr,
        bytes calldata data,
        uint256 blockNumber
    ) internal {
        address unichainToken = tokenMapping[contractAddr];
        if (unichainToken == address(0)) return;

        // Decode the data for the transfer amount (topic1=from, topic2=to, data=amount)
        if (data.length < 32) return;
        uint256 amount = abi.decode(data, (uint256));

        uint8 oldConfidence = confidence[unichainToken];
        uint8 newConfidence = PegScoring.applyTransferDelta(
            oldConfidence,
            amount
        );

        uint256 blocksSinceNegative = blockNumber -
            lastNegativeBlock[unichainToken];
        newConfidence = PegScoring.applyTimeRecovery(
            newConfidence,
            blocksSinceNegative
        );

        if (newConfidence < oldConfidence) {
            lastNegativeBlock[unichainToken] = blockNumber;
        }

        confidence[unichainToken] = newConfidence;

        if (
            PegScoring.shouldCallback(
                lastReportedConfidence[unichainToken],
                newConfidence
            )
        ) {
            lastReportedConfidence[unichainToken] = newConfidence;
            _emitCallback(unichainToken, newConfidence);
        }
    }

    function _handleMakerDaoFold(
        bytes calldata data,
        uint256 blockNumber
    ) internal {
        address unichainToken = tokenMapping[MAKERDAO_VAT];
        if (unichainToken == address(0)) return;

        // Decode fold rate (data usually contains param, dart)
        if (data.length < 32) return;
        uint256 rateRaw = abi.decode(data, (uint256)); // naive decode for illustrative mock
        int256 rate = int256(rateRaw);

        uint8 oldConfidence = confidence[unichainToken];
        uint8 newConfidence = PegScoring.applyMakerDaoDelta(
            oldConfidence,
            rate
        );

        uint256 blocksSinceNegative = blockNumber -
            lastNegativeBlock[unichainToken];
        newConfidence = PegScoring.applyTimeRecovery(
            newConfidence,
            blocksSinceNegative
        );

        if (newConfidence < oldConfidence) {
            lastNegativeBlock[unichainToken] = blockNumber;
        }

        confidence[unichainToken] = newConfidence;

        if (
            PegScoring.shouldCallback(
                lastReportedConfidence[unichainToken],
                newConfidence
            )
        ) {
            lastReportedConfidence[unichainToken] = newConfidence;
            _emitCallback(unichainToken, newConfidence);
        }
    }

    function _emitCallback(
        address unichainToken,
        uint8 newConfidence
    ) internal {
        bytes memory payload = abi.encodeWithSignature(
            "updateConfidence(address,uint8)",
            unichainToken,
            newConfidence
        );
        emit Callback(UNICHAIN_CHAIN_ID, receiverContract, 1000000, payload);
    }
}
