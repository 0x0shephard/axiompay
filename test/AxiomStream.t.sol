// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AxiomStream.sol";
import "./mocks/MockERC20.sol";

contract AxiomStreamTest is Test {
    AxiomStream public axiomStream;
    MockERC20 public usdc;

    address public owner = address(0x1);
    address public payer = address(0x2);
    address public provider = address(0x3);
    address public feeRecipient = address(0x4);

    uint256 public constant INITIAL_BALANCE = 1_000_000 * 1e6; // 1M USDC
    uint256 public constant PROTOCOL_FEE_BPS = 10; // 0.10%

    event StreamStarted(
        uint256 indexed streamId,
        address indexed payer,
        address indexed provider,
        address token,
        uint256 totalAmount,
        uint256 ratePerSecond,
        uint256 duration
    );

    event StreamWithdrawn(
        uint256 indexed streamId,
        address indexed provider,
        uint256 amount,
        uint256 fee
    );

    event StreamStopped(
        uint256 indexed streamId,
        address indexed payer,
        uint256 providerAmount,
        uint256 payerRefund,
        uint256 fee
    );

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);
        axiomStream = new AxiomStream(owner, PROTOCOL_FEE_BPS);
        usdc = new MockERC20("USD Coin", "USDC", INITIAL_BALANCE);
        vm.stopPrank();

        // Fund payer
        vm.prank(owner);
        usdc.transfer(payer, INITIAL_BALANCE / 2);

        // Label addresses for better trace output
        vm.label(owner, "Owner");
        vm.label(payer, "Payer");
        vm.label(provider, "Provider");
        vm.label(feeRecipient, "FeeRecipient");
        vm.label(address(axiomStream), "AxiomStream");
        vm.label(address(usdc), "USDC");
    }

    /*//////////////////////////////////////////////////////////////
                        START STREAM TESTS
    //////////////////////////////////////////////////////////////*/

    function testStartStream() public {
        uint256 ratePerSecond = 1000; // 0.001 USDC per second (with 6 decimals)
        uint256 duration = 1800; // 30 minutes
        uint256 totalAmount = ratePerSecond * duration;

        // Approve and start stream
        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);

        vm.expectEmit(true, true, true, true);
        emit StreamStarted(0, payer, provider, address(usdc), totalAmount, ratePerSecond, duration);

        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Verify stream was created correctly
        assertEq(streamId, 0);
        
        AxiomStream.Stream memory stream = axiomStream.getStream(streamId);
        assertEq(stream.payer, payer);
        assertEq(stream.provider, provider);
        assertEq(address(stream.token), address(usdc));
        assertEq(stream.ratePerSecond, ratePerSecond);
        assertEq(stream.duration, duration);
        assertEq(stream.totalAmount, totalAmount);
        assertEq(stream.withdrawnAmount, 0);
        assertEq(stream.stopped, false);

        // Verify tokens were transferred
        assertEq(usdc.balanceOf(address(axiomStream)), totalAmount);
    }

    function testStartStreamInvalidProvider() public {
        vm.startPrank(payer);
        usdc.approve(address(axiomStream), 1000);

        vm.expectRevert(AxiomStream.InvalidProvider.selector);
        axiomStream.startStream(address(0), usdc, 1000, 60);
        vm.stopPrank();
    }

    function testStartStreamInvalidRate() public {
        vm.startPrank(payer);
        usdc.approve(address(axiomStream), 1000);

        vm.expectRevert(AxiomStream.InvalidRate.selector);
        axiomStream.startStream(provider, usdc, 0, 60);
        vm.stopPrank();
    }

    function testStartStreamInvalidDuration() public {
        vm.startPrank(payer);
        usdc.approve(address(axiomStream), 1000);

        vm.expectRevert(AxiomStream.InvalidDuration.selector);
        axiomStream.startStream(provider, usdc, 1000, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdrawFromStream() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Fast forward 10 minutes (600 seconds)
        vm.warp(block.timestamp + 600);

        // Provider withdraws
        uint256 earned = 600 * ratePerSecond;
        uint256 fee = (earned * PROTOCOL_FEE_BPS) / 10000;
        uint256 expectedAmount = earned - fee;

        vm.prank(provider);
        vm.expectEmit(true, true, false, true);
        emit StreamWithdrawn(streamId, provider, expectedAmount, fee);
        
        uint256 withdrawn = axiomStream.withdrawFromStream(streamId);

        assertEq(withdrawn, expectedAmount);
        assertEq(usdc.balanceOf(provider), expectedAmount);
        assertEq(axiomStream.accumulatedFees(usdc), fee);
    }

    function testWithdrawMultipleTimes() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // First withdrawal after 5 minutes
        vm.warp(block.timestamp + 300);
        vm.prank(provider);
        uint256 firstWithdrawal = axiomStream.withdrawFromStream(streamId);

        // Second withdrawal after another 5 minutes
        vm.warp(block.timestamp + 300);
        vm.prank(provider);
        uint256 secondWithdrawal = axiomStream.withdrawFromStream(streamId);

        // Verify both withdrawals happened
        assertTrue(firstWithdrawal > 0);
        assertTrue(secondWithdrawal > 0);
        assertEq(usdc.balanceOf(provider), firstWithdrawal + secondWithdrawal);
    }

    function testWithdrawUnauthorized() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        vm.warp(block.timestamp + 300);

        // Payer tries to withdraw (should fail)
        vm.prank(payer);
        vm.expectRevert(AxiomStream.Unauthorized.selector);
        axiomStream.withdrawFromStream(streamId);
    }

    function testWithdrawInsufficientEarned() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Try to withdraw immediately (no time elapsed)
        vm.prank(provider);
        vm.expectRevert(AxiomStream.InsufficientEarned.selector);
        axiomStream.withdrawFromStream(streamId);
    }

    function testWithdrawAfterDurationExpired() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Fast forward beyond duration
        vm.warp(block.timestamp + duration + 1000);

        // Provider withdraws - should only get up to totalAmount
        vm.prank(provider);
        uint256 withdrawn = axiomStream.withdrawFromStream(streamId);

        uint256 fee = (totalAmount * PROTOCOL_FEE_BPS) / 10000;
        uint256 expectedAmount = totalAmount - fee;

        assertEq(withdrawn, expectedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        STOP STREAM TESTS
    //////////////////////////////////////////////////////////////*/

    function testStopStream() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Fast forward 10 minutes
        vm.warp(block.timestamp + 600);

        uint256 earned = 600 * ratePerSecond;
        uint256 fee = (earned * PROTOCOL_FEE_BPS) / 10000;
        uint256 providerAmount = earned - fee;
        uint256 payerRefund = totalAmount - earned;

        // Stop the stream
        vm.prank(payer);
        vm.expectEmit(true, true, false, true);
        emit StreamStopped(streamId, payer, providerAmount, payerRefund, fee);
        
        axiomStream.stopStream(streamId);

        // Verify balances
        assertEq(usdc.balanceOf(provider), providerAmount);
        assertEq(usdc.balanceOf(payer), (INITIAL_BALANCE / 2) - totalAmount + payerRefund);
        assertEq(axiomStream.accumulatedFees(usdc), fee);

        // Verify stream is stopped
        AxiomStream.Stream memory stream = axiomStream.getStream(streamId);
        assertTrue(stream.stopped);
    }

    function testStopStreamUnauthorized() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Provider tries to stop (should fail)
        vm.prank(provider);
        vm.expectRevert(AxiomStream.Unauthorized.selector);
        axiomStream.stopStream(streamId);
    }

    function testStopStreamTwice() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        vm.warp(block.timestamp + 300);

        // Stop once
        vm.prank(payer);
        axiomStream.stopStream(streamId);

        // Try to stop again
        vm.prank(payer);
        vm.expectRevert(AxiomStream.StreamAlreadyStopped.selector);
        axiomStream.stopStream(streamId);
    }

    function testStopStreamAfterPartialWithdrawal() public {
        // Setup: Create a stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Fast forward and withdraw
        vm.warp(block.timestamp + 300);
        vm.prank(provider);
        uint256 firstWithdrawal = axiomStream.withdrawFromStream(streamId);

        // Fast forward more and stop
        vm.warp(block.timestamp + 300);
        uint256 totalEarned = 600 * ratePerSecond;
        uint256 alreadyWithdrawn = 300 * ratePerSecond;
        
        vm.prank(payer);
        axiomStream.stopStream(streamId);

        // Provider should have earned for 600 seconds total
        uint256 totalFee = (totalEarned * PROTOCOL_FEE_BPS) / 10000;
        uint256 expectedTotal = totalEarned - totalFee;
        
        assertEq(usdc.balanceOf(provider), expectedTotal);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetEarned() public {
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Check earned at different times
        vm.warp(block.timestamp + 300);
        assertEq(axiomStream.getEarned(streamId), 300 * ratePerSecond);

        vm.warp(block.timestamp + 300);
        assertEq(axiomStream.getEarned(streamId), 600 * ratePerSecond);

        // Check it caps at totalAmount
        vm.warp(block.timestamp + duration + 1000);
        assertEq(axiomStream.getEarned(streamId), totalAmount);
    }

    function testGetAvailableToWithdraw() public {
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        vm.warp(block.timestamp + 300);
        assertEq(axiomStream.getAvailableToWithdraw(streamId), 300 * ratePerSecond);

        // Withdraw
        vm.prank(provider);
        axiomStream.withdrawFromStream(streamId);

        // Available should be 0 now
        assertEq(axiomStream.getAvailableToWithdraw(streamId), 0);

        // More time passes
        vm.warp(block.timestamp + 300);
        assertEq(axiomStream.getAvailableToWithdraw(streamId), 300 * ratePerSecond);
    }

    function testGetRemainingTime() public {
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // Initially should be full duration
        assertEq(axiomStream.getRemainingTime(streamId), duration);

        // After 300 seconds
        vm.warp(block.timestamp + 300);
        assertEq(axiomStream.getRemainingTime(streamId), duration - 300);

        // After full duration
        vm.warp(block.timestamp + duration);
        assertEq(axiomStream.getRemainingTime(streamId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetProtocolFee() public {
        vm.prank(owner);
        axiomStream.setProtocolFee(50); // 0.50%

        assertEq(axiomStream.protocolFeeBps(), 50);
    }

    function testSetProtocolFeeExceedsMax() public {
        vm.prank(owner);
        vm.expectRevert(AxiomStream.ExcessiveProtocolFee.selector);
        axiomStream.setProtocolFee(101); // > 1%
    }

    function testSetProtocolFeeUnauthorized() public {
        vm.prank(payer);
        vm.expectRevert();
        axiomStream.setProtocolFee(50);
    }

    function testWithdrawProtocolFees() public {
        // Create and complete a stream to generate fees
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        vm.warp(block.timestamp + duration);
        
        vm.prank(provider);
        axiomStream.withdrawFromStream(streamId);

        uint256 expectedFees = (totalAmount * PROTOCOL_FEE_BPS) / 10000;
        assertEq(axiomStream.accumulatedFees(usdc), expectedFees);

        // Withdraw fees
        uint256 balanceBefore = usdc.balanceOf(feeRecipient);
        vm.prank(owner);
        axiomStream.withdrawProtocolFees(usdc, feeRecipient);

        assertEq(usdc.balanceOf(feeRecipient), balanceBefore + expectedFees);
        assertEq(axiomStream.accumulatedFees(usdc), 0);
    }

    function testWithdrawProtocolFeesNoFees() public {
        vm.prank(owner);
        vm.expectRevert(AxiomStream.NoFeesToWithdraw.selector);
        axiomStream.withdrawProtocolFees(usdc, feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullStreamLifecycle() public {
        // 1. Start stream
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        // 2. Provider withdraws after 5 minutes
        vm.warp(block.timestamp + 300);
        vm.prank(provider);
        axiomStream.withdrawFromStream(streamId);

        // 3. Stream continues for 10 more minutes
        vm.warp(block.timestamp + 600);

        // 4. Provider withdraws again
        vm.prank(provider);
        axiomStream.withdrawFromStream(streamId);

        // 5. Payer stops stream after 15 minutes total
        vm.prank(payer);
        axiomStream.stopStream(streamId);

        // Verify final state
        uint256 totalEarned = 900 * ratePerSecond;
        uint256 fee = (totalEarned * PROTOCOL_FEE_BPS) / 10000;
        uint256 providerTotal = totalEarned - fee;

        assertEq(usdc.balanceOf(provider), providerTotal);
        assertEq(axiomStream.accumulatedFees(usdc), fee);
    }

    function testMultipleStreams() public {
        uint256 ratePerSecond = 1000;
        uint256 duration = 1800;
        uint256 totalAmount = ratePerSecond * duration;

        // Create 3 streams
        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount * 3);
        
        uint256 streamId1 = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        uint256 streamId2 = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        uint256 streamId3 = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        assertEq(streamId1, 0);
        assertEq(streamId2, 1);
        assertEq(streamId3, 2);

        // Verify each stream is independent
        vm.warp(block.timestamp + 300);
        assertEq(axiomStream.getEarned(streamId1), 300 * ratePerSecond);
        assertEq(axiomStream.getEarned(streamId2), 300 * ratePerSecond);
        assertEq(axiomStream.getEarned(streamId3), 300 * ratePerSecond);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_StartStream(uint256 ratePerSecond, uint256 duration) public {
        // Bound inputs to reasonable ranges
        ratePerSecond = bound(ratePerSecond, 1, 1e12); // 1 to 1M USDC per second
        duration = bound(duration, 1, 365 days);

        uint256 totalAmount = ratePerSecond * duration;
        
        // Skip if overflow would occur
        if (totalAmount / duration != ratePerSecond) return;
        if (totalAmount > INITIAL_BALANCE / 2) return;

        vm.startPrank(payer);
        usdc.approve(address(axiomStream), totalAmount);
        uint256 streamId = axiomStream.startStream(provider, usdc, ratePerSecond, duration);
        vm.stopPrank();

        AxiomStream.Stream memory stream = axiomStream.getStream(streamId);
        assertEq(stream.totalAmount, totalAmount);
        assertEq(stream.ratePerSecond, ratePerSecond);
        assertEq(stream.duration, duration);
    }
}
