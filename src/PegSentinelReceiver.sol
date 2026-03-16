// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPegSentinelHook} from "./interfaces/IPegSentinelHook.sol";

contract PegSentinelReceiver is ReentrancyGuard, Ownable {
    IPegSentinelHook public immutable hook;

    /// @notice Authorized RSC contract address on Reactive Network
    address public immutable reactiveContract;

    uint256 public constant MIN_UPDATE_INTERVAL = 100; // blocks

    mapping(address => uint256) public lastUpdateBlock;

    event ConfidenceUpdateReceived(address indexed token, uint8 newConfidence);

    error NotAuthorizedReactiveContract();
    error RateLimitExceeded();
    error InvalidConfidenceValue();

    modifier onlyReactiveContract() {
        if (msg.sender != reactiveContract)
            revert NotAuthorizedReactiveContract();
        _;
    }

    constructor(
        address _hook,
        address _reactiveContract,
        address _owner
    ) Ownable(_owner) {
        hook = IPegSentinelHook(_hook);
        reactiveContract = _reactiveContract;
    }

    /// @notice Callback entry point for Reactive Network
    function updateConfidence(
        address token,
        uint8 confidence
    ) external nonReentrant onlyReactiveContract {
        if (confidence > 100) revert InvalidConfidenceValue();
        if (block.number < lastUpdateBlock[token] + MIN_UPDATE_INTERVAL)
            revert RateLimitExceeded();

        lastUpdateBlock[token] = block.number;
        hook.updatePegConfidence(token, confidence);

        emit ConfidenceUpdateReceived(token, confidence);
    }
}
