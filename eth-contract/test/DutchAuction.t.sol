// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/DutchAuction.sol";
import "../src/interfaces/IDutchAuction.sol";
import "../src/interfaces/ILimitOrderProtocol.sol";

contract MockLimitOrderProtocol {
    address public immutable owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
}

contract DutchAuctionTest is Test {
    DutchAuction public dutchAuction;
    MockLimitOrderProtocol public mockLimitOrder;
    
    address public limitOrderProtocol;
    bytes32 public orderHash = keccak256("test-order");
    
    ILimitOrderProtocol.DutchAuctionConfig public auctionConfig;
    
    function setUp() public {
        mockLimitOrder = new MockLimitOrderProtocol();
        limitOrderProtocol = address(mockLimitOrder);
        
        dutchAuction = new DutchAuction(limitOrderProtocol);
        
        // Setup auction config
        auctionConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + 1 hours,
            startRate: 1.2e18, // 120%
            endRate: 1.0e18,   // 100%
            decreaseRate: 0    // Auto-calculate
        });
    }
    
    function testInitializeAuction() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // Verify auction was initialized
        (
            bytes32 _orderHash,
            uint256 _startTime,
            uint256 _endTime,
            uint256 _startRate,
            uint256 _endRate,
            uint256 _decreaseRate,
            bool _isActive
        ) = dutchAuction.getAuction(orderHash);
        
        assertEq(_orderHash, orderHash);
        assertEq(_startTime, auctionConfig.auctionStartTime);
        assertEq(_endTime, auctionConfig.auctionEndTime);
        assertEq(_startRate, auctionConfig.startRate);
        assertEq(_endRate, auctionConfig.endRate);
        assertTrue(_decreaseRate > 0); // Should be auto-calculated
        assertTrue(_isActive);
    }
    
    function testInitializeAuctionOnlyLimitOrderProtocol() public {
        vm.expectRevert(IDutchAuction.OnlyLimitOrderProtocol.selector);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
    }
    
    function testInitializeAuctionInvalidTimes() public {
        ILimitOrderProtocol.DutchAuctionConfig memory badConfig = auctionConfig;
        badConfig.auctionEndTime = badConfig.auctionStartTime - 1;
        
        vm.prank(limitOrderProtocol);
        vm.expectRevert(IDutchAuction.InvalidAuctionTimes.selector);
        dutchAuction.initializeAuction(orderHash, badConfig);
    }
    
    function testInitializeAuctionInvalidRates() public {
        ILimitOrderProtocol.DutchAuctionConfig memory badConfig = auctionConfig;
        badConfig.startRate = 0;
        
        vm.prank(limitOrderProtocol);
        vm.expectRevert(IDutchAuction.InvalidRates.selector);
        dutchAuction.initializeAuction(orderHash, badConfig);
    }
    
    function testInitializeAuctionInvalidRateProgression() public {
        ILimitOrderProtocol.DutchAuctionConfig memory badConfig = auctionConfig;
        badConfig.startRate = 1.0e18;
        badConfig.endRate = 1.2e18; // End rate higher than start rate
        
        vm.prank(limitOrderProtocol);
        vm.expectRevert(IDutchAuction.InvalidRateProgression.selector);
        dutchAuction.initializeAuction(orderHash, badConfig);
    }
    
    function testCalculateCurrentRateAtStart() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // At start time, should return start rate
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        assertEq(currentRate, auctionConfig.startRate);
    }
    
    function testCalculateCurrentRateBeforeStart() public {
        ILimitOrderProtocol.DutchAuctionConfig memory futureConfig = auctionConfig;
        futureConfig.auctionStartTime = block.timestamp + 1 hours;
        futureConfig.auctionEndTime = block.timestamp + 2 hours;
        
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, futureConfig);
        
        // Before start time, should return 0
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        assertEq(currentRate, 0);
    }
    
    function testCalculateCurrentRateAfterEnd() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // Fast forward past end time
        vm.warp(auctionConfig.auctionEndTime + 1);
        
        // After end time, should return end rate
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        assertEq(currentRate, auctionConfig.endRate);
    }
    
    function testCalculateCurrentRateMidway() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // Fast forward to halfway point
        uint256 halfwayPoint = auctionConfig.auctionStartTime + 
            (auctionConfig.auctionEndTime - auctionConfig.auctionStartTime) / 2;
        vm.warp(halfwayPoint);
        
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        
        // Should be approximately halfway between start and end rates
        uint256 expectedRate = (auctionConfig.startRate + auctionConfig.endRate) / 2;
        uint256 tolerance = 1e15; // Small tolerance for rounding
        
        assertTrue(currentRate >= expectedRate - tolerance);
        assertTrue(currentRate <= expectedRate + tolerance);
    }
    
    function testCalculateRateAtTime() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        uint256 specificTime = auctionConfig.auctionStartTime + 15 minutes;
        uint256 rateAtTime = dutchAuction.calculateRateAtTime(orderHash, specificTime);
        
        // Warp to that time and check consistency
        vm.warp(specificTime);
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        
        assertEq(rateAtTime, currentRate);
    }
    
    function testCancelAuction() public {
        // Initialize auction
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // Cancel auction
        vm.prank(limitOrderProtocol);
        dutchAuction.cancelAuction(orderHash);
        
        // Verify auction is cancelled
        assertFalse(dutchAuction.isAuctionActive(orderHash));
        
        // Rate should return 0 for cancelled auction
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        assertEq(currentRate, 0);
    }
    
    function testCancelAuctionOnlyLimitOrderProtocol() public {
        // Initialize auction
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // Try to cancel from unauthorized address
        vm.expectRevert(IDutchAuction.OnlyLimitOrderProtocol.selector);
        dutchAuction.cancelAuction(orderHash);
    }
    
    function testIsProfitableForResolver() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        uint256 lowCost = 1e17; // 0.1 ETH
        uint256 highCost = 1.5e18; // 1.5 ETH
        
        // At start (high rate), should be profitable for low cost
        assertTrue(dutchAuction.isProfitableForResolver(orderHash, lowCost));
        
        // At start (high rate), should not be profitable for very high cost
        assertFalse(dutchAuction.isProfitableForResolver(orderHash, highCost));
    }
    
    function testGetRemainingTime() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        uint256 remainingTime = dutchAuction.getRemainingTime(orderHash);
        uint256 expectedRemaining = auctionConfig.auctionEndTime - block.timestamp;
        
        assertEq(remainingTime, expectedRemaining);
        
        // Fast forward and check again
        vm.warp(block.timestamp + 30 minutes);
        remainingTime = dutchAuction.getRemainingTime(orderHash);
        expectedRemaining = auctionConfig.auctionEndTime - block.timestamp;
        
        assertEq(remainingTime, expectedRemaining);
        
        // After end time, should return 0
        vm.warp(auctionConfig.auctionEndTime + 1);
        remainingTime = dutchAuction.getRemainingTime(orderHash);
        assertEq(remainingTime, 0);
    }
    
    function testGetElapsedTime() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // At start, elapsed time should be 0
        uint256 elapsedTime = dutchAuction.getElapsedTime(orderHash);
        assertEq(elapsedTime, 0);
        
        // Fast forward and check
        vm.warp(block.timestamp + 30 minutes);
        elapsedTime = dutchAuction.getElapsedTime(orderHash);
        assertEq(elapsedTime, 30 minutes);
    }
    
    function testAuctionStateChecks() public {
        // Before initialization
        assertFalse(dutchAuction.isAuctionActive(orderHash));
        assertFalse(dutchAuction.hasAuctionStarted(orderHash));
        assertFalse(dutchAuction.hasAuctionEnded(orderHash));
        
        // Initialize auction
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // During auction
        assertTrue(dutchAuction.isAuctionActive(orderHash));
        assertTrue(dutchAuction.hasAuctionStarted(orderHash));
        assertFalse(dutchAuction.hasAuctionEnded(orderHash));
        
        // After auction ends
        vm.warp(auctionConfig.auctionEndTime + 1);
        assertFalse(dutchAuction.isAuctionActive(orderHash));
        assertTrue(dutchAuction.hasAuctionStarted(orderHash));
        assertTrue(dutchAuction.hasAuctionEnded(orderHash));
    }
    
    function testGetRateProgression() public {
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        uint256 steps = 10;
        (uint256[] memory timestamps, uint256[] memory rates) = 
            dutchAuction.getRateProgression(orderHash, steps);
        
        assertEq(timestamps.length, steps);
        assertEq(rates.length, steps);
        
        // First rate should be highest (start rate)
        assertTrue(rates[0] >= rates[steps-1]);
        
        // Rates should generally decrease (allowing for some tolerance)
        for (uint256 i = 1; i < steps; i++) {
            assertTrue(rates[i] <= rates[i-1] + 1e15); // Small tolerance for rounding
        }
    }
    
    function testFuzzAuctionDuration(uint256 duration) public {
        // Bound duration to reasonable values
        duration = bound(duration, 300, 86400); // 5 minutes to 24 hours
        
        ILimitOrderProtocol.DutchAuctionConfig memory fuzzConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + duration,
            startRate: 2e18, // 200%
            endRate: 1e18,   // 100%
            decreaseRate: 0
        });
        
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, fuzzConfig);
        
        // Test at various points during the auction
        uint256 quarterPoint = block.timestamp + duration / 4;
        uint256 halfPoint = block.timestamp + duration / 2;
        uint256 threeQuarterPoint = block.timestamp + (3 * duration) / 4;
        
        vm.warp(quarterPoint);
        uint256 quarterRate = dutchAuction.calculateCurrentRate(orderHash);
        
        vm.warp(halfPoint);
        uint256 halfRate = dutchAuction.calculateCurrentRate(orderHash);
        
        vm.warp(threeQuarterPoint);
        uint256 threeQuarterRate = dutchAuction.calculateCurrentRate(orderHash);
        
        // Rates should decrease over time
        assertTrue(quarterRate >= halfRate);
        assertTrue(halfRate >= threeQuarterRate);
        
        // All rates should be between start and end rates
        assertTrue(quarterRate <= fuzzConfig.startRate);
        assertTrue(quarterRate >= fuzzConfig.endRate);
        assertTrue(threeQuarterRate <= fuzzConfig.startRate);
        assertTrue(threeQuarterRate >= fuzzConfig.endRate);
    }
    
    function testFuzzRateRange(uint256 startRate, uint256 endRate) public {
        // Bound rates to reasonable values and ensure proper ordering
        startRate = bound(startRate, 1.1e18, 10e18); // 110% to 1000%
        endRate = bound(endRate, 1e18, startRate - 1e17); // 100% to just below startRate
        
        ILimitOrderProtocol.DutchAuctionConfig memory fuzzConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + 1 hours,
            startRate: startRate,
            endRate: endRate,
            decreaseRate: 0
        });
        
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, fuzzConfig);
        
        // Test at start
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        assertEq(currentRate, startRate);
        
        // Test at various points
        vm.warp(block.timestamp + 30 minutes);
        uint256 midRate = dutchAuction.calculateCurrentRate(orderHash);
        assertTrue(midRate <= startRate);
        assertTrue(midRate >= endRate);
        
        // Test at end
        vm.warp(fuzzConfig.auctionEndTime);
        uint256 finalRate = dutchAuction.calculateCurrentRate(orderHash);
        assertEq(finalRate, endRate);
    }
    
    function testAuctionAlreadyExists() public {
        // Initialize auction
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        // Try to initialize again
        vm.prank(limitOrderProtocol);
        vm.expectRevert(IDutchAuction.AuctionAlreadyExists.selector);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
    }
    
    function testCancelNonexistentAuction() public {
        vm.prank(limitOrderProtocol);
        vm.expectRevert(IDutchAuction.AuctionNotFound.selector);
        dutchAuction.cancelAuction(orderHash);
    }
    
    function testCancelAlreadyCancelledAuction() public {
        // Initialize and cancel auction
        vm.prank(limitOrderProtocol);
        dutchAuction.initializeAuction(orderHash, auctionConfig);
        
        vm.prank(limitOrderProtocol);
        dutchAuction.cancelAuction(orderHash);
        
        // Try to cancel again - should fail with AuctionNotActive since isActive is false
        vm.prank(limitOrderProtocol);
        vm.expectRevert(IDutchAuction.AuctionNotActive.selector);
        dutchAuction.cancelAuction(orderHash);
    }
    
    function testNonexistentAuctionOperations() public {
        bytes32 nonexistentOrder = keccak256("nonexistent");
        
        // All operations should return 0 or false for nonexistent auctions
        assertEq(dutchAuction.calculateCurrentRate(nonexistentOrder), 0);
        assertEq(dutchAuction.getRemainingTime(nonexistentOrder), 0);
        assertEq(dutchAuction.getElapsedTime(nonexistentOrder), 0);
        assertFalse(dutchAuction.isAuctionActive(nonexistentOrder));
        assertFalse(dutchAuction.hasAuctionStarted(nonexistentOrder));
        assertFalse(dutchAuction.hasAuctionEnded(nonexistentOrder));
        assertFalse(dutchAuction.isProfitableForResolver(nonexistentOrder, 1e18));
    }
}