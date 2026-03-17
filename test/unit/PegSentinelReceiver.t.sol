// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PegSentinelReceiver} from "../../src/PegSentinelReceiver.sol";
import {IPegSentinelHook} from "../../src/interfaces/IPegSentinelHook.sol";

contract MockHook is IPegSentinelHook {
    uint8 public lastConfidence;
    address public lastToken;

    function updatePegConfidence(
        address token,
        uint8 confidence
    ) external override {
        lastToken = token;
        lastConfidence = confidence;
    }
}

contract PegSentinelReceiverTest is Test {
    PegSentinelReceiver receiver;
    MockHook hook;
    address owner = address(0x111);
    address reactiveContract = address(0x222);
    address token = address(0x333);

    function setUp() public {
        hook = new MockHook();
        receiver = new PegSentinelReceiver(
            address(hook),
            reactiveContract,
            owner
        );
    }

    function testOnlyReactiveContractCanUpdate() public {
        vm.roll(101);
        vm.prank(address(0xbad));
        vm.expectRevert(
            PegSentinelReceiver.NotAuthorizedReactiveContract.selector
        );
        receiver.updateConfidence(token, 50);

        vm.prank(reactiveContract);
        receiver.updateConfidence(token, 50);
        assertEq(hook.lastConfidence(), 50);
        assertEq(hook.lastToken(), token);
    }

    function testInvalidConfidenceReverts() public {
        vm.prank(reactiveContract);
        vm.expectRevert(PegSentinelReceiver.InvalidConfidenceValue.selector);
        receiver.updateConfidence(token, 101);
    }

    function testRateLimitingBlocksFrequentUpdates() public {
        // First update at block 101
        vm.roll(101);
        vm.startPrank(reactiveContract);
        receiver.updateConfidence(token, 50);

        // Update at block 150 should fail (MIN_UPDATE_INTERVAL is 100)
        vm.roll(150);
        vm.expectRevert(PegSentinelReceiver.RateLimitExceeded.selector);
        receiver.updateConfidence(token, 40);

        // Update at block 201 should succeed
        vm.roll(201);
        receiver.updateConfidence(token, 40);

        // Assert state updated
        assertEq(hook.lastConfidence(), 40);
        vm.stopPrank();
    }

    function testRateLimitingIsPerToken() public {
        vm.roll(101);
        vm.startPrank(reactiveContract);
        receiver.updateConfidence(token, 50);

        address token2 = address(0x444);
        // Should succeed on the same block since it's a different token
        receiver.updateConfidence(token2, 80);

        assertEq(hook.lastConfidence(), 80);
        assertEq(hook.lastToken(), token2);
        vm.stopPrank();
    }
}
