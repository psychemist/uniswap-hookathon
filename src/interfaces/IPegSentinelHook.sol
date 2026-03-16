// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IPegSentinelHook {
    function updatePegConfidence(address token, uint8 confidence) external;
}
