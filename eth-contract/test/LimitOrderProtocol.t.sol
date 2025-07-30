// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/LimitOrderProtocol.sol";
import "../src/core/DutchAuction.sol";
import "../src/core/ResolverNetwork.sol";
import "../src/core/EthereumEscrow.sol";
import "../src/interfaces/ILimitOrderProtocol.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
    
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
    
    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract LimitOrderProtocolTest is Test {
    LimitOrderProtocol public limitOrder;
    DutchAuction public dutchAuction;
    ResolverNetwork public resolverNetwork;
    EthereumEscrow public escrow;
    MockWETH public weth;
    
    address public admin = address(0x1);
    address public maker = address(0x2);
    address public resolver1 = address(0x3);
    address public resolver2 = address(0x4);
    
    uint256 public constant MIN_ORDER_AMOUNT = 1e15; // 0.001 WETH
    uint256 public sourceAmount = 1 ether;
    uint256 public destinationAmount = 2000 * 1e6; // 2000 USDT (assuming 6 decimals)
    
    ILimitOrderProtocol.DutchAuctionConfig public auctionConfig;
    
    function setUp() public {
        // Deploy WETH
        weth = new MockWETH();
        
        // Deploy contracts in correct order
        escrow = new EthereumEscrow(address(weth));
        
        // Deploy LimitOrderProtocol with temp addresses that we'll calculate
        // We need to predict the addresses of the contracts we'll deploy
        // This is complex, so let's use a simpler approach:
        
        // First, let's deploy the contracts in the right order without re-deployment
        // We'll use a factory pattern or just accept the circular dependency
        
        // For now, let's use the actual contracts that will be deployed
        // Calculate the future addresses (this is just an approximation)
        uint256 nonce = vm.getNonce(address(this));
        address futureAuction = computeCreateAddress(address(this), nonce + 1);
        address futureResolver = computeCreateAddress(address(this), nonce + 2);
        
        // Deploy LimitOrderProtocol with predicted addresses
        limitOrder = new LimitOrderProtocol(
            address(weth),
            futureAuction,
            futureResolver,
            address(escrow)
        );
        
        // Now deploy the dependent contracts (these should match the predicted addresses)
        dutchAuction = new DutchAuction(address(limitOrder));
        resolverNetwork = new ResolverNetwork(address(limitOrder), address(weth), admin);
        
        // Verify addresses match
        require(address(dutchAuction) == futureAuction, "DutchAuction address mismatch");
        require(address(resolverNetwork) == futureResolver, "ResolverNetwork address mismatch");
        
        // Setup auction config
        auctionConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + 1 hours,
            startRate: 1.2e18, // 120% start rate
            endRate: 1.0e18,   // 100% end rate
            decreaseRate: 0    // Let Dutch auction auto-calculate
        });
        
        // Give test addresses ETH and WETH
        vm.deal(maker, 10 ether);
        vm.deal(resolver1, 10 ether);
        vm.deal(resolver2, 10 ether);
        
        vm.prank(maker);
        weth.deposit{value: 5 ether}();
        vm.prank(resolver1);
        weth.deposit{value: 5 ether}();
        vm.prank(resolver2);
        weth.deposit{value: 5 ether}();
        
        // Register resolvers
        vm.prank(resolver1);
        weth.approve(address(resolverNetwork), 1e18);
        vm.prank(resolver1);
        resolverNetwork.registerResolver();
        
        vm.prank(resolver2);
        weth.approve(address(resolverNetwork), 1e18);
        vm.prank(resolver2);
        resolverNetwork.registerResolver();
    }
    
    function testCreateCrossChainOrder() public {
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Verify order was created
        (
            address _maker,
            address _taker,
            uint256 _sourceAmount,
            uint256 _destinationAmount,
            uint256 _deadline,
            bool _isActive,
            ILimitOrderProtocol.DutchAuctionConfig memory _auctionConfig,
            uint256 _filledAmount,
            bytes32 _escrowId,
            uint256 _createdAt
        ) = limitOrder.getOrder(orderHash);
        
        assertEq(_maker, maker);
        assertEq(_taker, address(0));
        assertEq(_sourceAmount, sourceAmount);
        assertEq(_destinationAmount, destinationAmount);
        assertEq(_deadline, auctionConfig.auctionEndTime);
        assertTrue(_isActive);
        assertEq(_auctionConfig.startRate, auctionConfig.startRate);
        assertEq(_filledAmount, 0);
        assertEq(_escrowId, bytes32(0));
        assertEq(_createdAt, block.timestamp);
    }
    
    function testCreateCrossChainOrderInvalidAmount() public {
        vm.startPrank(maker);
        weth.approve(address(limitOrder), MIN_ORDER_AMOUNT - 1);
        
        vm.expectRevert(ILimitOrderProtocol.InvalidSourceAmount.selector);
        limitOrder.createCrossChainOrder(
            MIN_ORDER_AMOUNT - 1,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
    }
    
    function testCreateCrossChainOrderInvalidAuctionTimes() public {
        ILimitOrderProtocol.DutchAuctionConfig memory badConfig = auctionConfig;
        badConfig.auctionEndTime = badConfig.auctionStartTime - 1;
        
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        vm.expectRevert(ILimitOrderProtocol.InvalidAuctionTimes.selector);
        limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            badConfig
        );
        
        vm.stopPrank();
    }
    
    function testCreateEscrowForOrder() public {
        // Create order first
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        // Create escrow for order
        bytes32 hashLock = keccak256(abi.encodePacked("secret"));
        uint256 timeLock = block.timestamp + 2 hours;
        
        // Need to approve escrow contract to spend WETH
        weth.approve(address(escrow), sourceAmount);
        
        bytes32 escrowId = limitOrder.createEscrowForOrder(
            orderHash,
            hashLock,
            timeLock
        );
        
        vm.stopPrank();
        
        // Verify escrow was created
        assertTrue(escrowId != bytes32(0));
        
        // Verify order was updated with escrow ID
        (,,,,,,,, bytes32 _escrowId,) = limitOrder.getOrder(orderHash);
        assertEq(_escrowId, escrowId);
    }
    
    function testFillLimitOrder() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Fill order
        bytes32 secret = bytes32("secret");
        uint256 initialBalance = weth.balanceOf(resolver1);
        
        vm.prank(resolver1);
        limitOrder.fillLimitOrder(orderHash, secret);
        
        // Verify resolver received tokens based on current rate
        uint256 currentRate = limitOrder.getCurrentRate(orderHash);
        uint256 expectedFillAmount = (sourceAmount * currentRate) / 1e18;
        
        assertEq(weth.balanceOf(resolver1), initialBalance + expectedFillAmount);
        
        // Verify order was filled
        (,,,,,,, uint256 filledAmount,,) = limitOrder.getOrder(orderHash);
        assertEq(filledAmount, expectedFillAmount);
    }
    
    function testFillLimitOrderUnauthorizedResolver() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Try to fill with unauthorized resolver
        address unauthorizedResolver = address(0x999);
        bytes32 secret = bytes32("secret");
        
        vm.prank(unauthorizedResolver);
        vm.expectRevert(ILimitOrderProtocol.UnauthorizedResolver.selector);
        limitOrder.fillLimitOrder(orderHash, secret);
    }
    
    function testCancelOrder() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        uint256 initialBalance = weth.balanceOf(maker);
        
        // Cancel order
        limitOrder.cancelOrder(orderHash);
        
        vm.stopPrank();
        
        // Verify order was cancelled and funds refunded
        (,,,,,bool isActive,,,,) = limitOrder.getOrder(orderHash);
        assertFalse(isActive);
        
        // Verify refund
        assertEq(weth.balanceOf(maker), initialBalance + sourceAmount);
    }
    
    function testCancelOrderOnlyMaker() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Try to cancel from non-maker
        vm.prank(resolver1);
        vm.expectRevert(ILimitOrderProtocol.OnlyMaker.selector);
        limitOrder.cancelOrder(orderHash);
    }
    
    function testGetCurrentRate() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Check initial rate
        uint256 currentRate = limitOrder.getCurrentRate(orderHash);
        assertEq(currentRate, auctionConfig.startRate);
        
        // Fast forward and check decreased rate
        vm.warp(block.timestamp + 30 minutes);
        uint256 newRate = limitOrder.getCurrentRate(orderHash);
        assertTrue(newRate < auctionConfig.startRate);
        assertTrue(newRate > auctionConfig.endRate);
    }
    
    function testCanFillOrder() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Check authorized resolver can fill
        assertTrue(limitOrder.canFillOrder(orderHash, resolver1));
        
        // Check unauthorized resolver cannot fill
        assertFalse(limitOrder.canFillOrder(orderHash, address(0x999)));
    }
    
    function testGetRemainingAmount() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Initially should equal source amount
        assertEq(limitOrder.getRemainingAmount(orderHash), sourceAmount);
        
        // After partial fill
        bytes32 secret = bytes32("secret");
        vm.prank(resolver1);
        limitOrder.fillLimitOrder(orderHash, secret);
        
        uint256 currentRate = limitOrder.getCurrentRate(orderHash);
        uint256 fillAmount = (sourceAmount * currentRate) / 1e18;
        assertEq(limitOrder.getRemainingAmount(orderHash), sourceAmount - fillAmount);
    }
    
    function testOrderExpiration() public {
        // Create order
        vm.startPrank(maker);
        weth.approve(address(limitOrder), sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );
        
        vm.stopPrank();
        
        // Fast forward past expiration
        vm.warp(auctionConfig.auctionEndTime + 1);
        
        // Try to fill expired order
        bytes32 secret = bytes32("secret");
        vm.prank(resolver1);
        vm.expectRevert(ILimitOrderProtocol.OrderExpired.selector);
        limitOrder.fillLimitOrder(orderHash, secret);
    }
    
    function testFuzzCreateOrder(
        uint256 _sourceAmount,
        uint256 _destinationAmount,
        uint256 _duration
    ) public {
        // Bound inputs
        _sourceAmount = bound(_sourceAmount, MIN_ORDER_AMOUNT, 1000 ether);
        _destinationAmount = bound(_destinationAmount, 1, 1e12);
        _duration = bound(_duration, 300, 86400); // 5 min to 24 hours
        
        // Give maker enough WETH
        vm.deal(maker, _sourceAmount);
        vm.prank(maker);
        weth.deposit{value: _sourceAmount}();
        
        ILimitOrderProtocol.DutchAuctionConfig memory fuzzConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + _duration,
            startRate: 1.2e18,
            endRate: 1.0e18,
            decreaseRate: 0
        });
        
        vm.startPrank(maker);
        weth.approve(address(limitOrder), _sourceAmount);
        
        bytes32 orderHash = limitOrder.createCrossChainOrder(
            _sourceAmount,
            _destinationAmount,
            fuzzConfig
        );
        
        vm.stopPrank();
        
        // Verify order creation
        (
            address _maker,
            ,
            uint256 _srcAmount,
            uint256 _destAmount,
            uint256 _deadline,
            bool _isActive,
            ,,,
        ) = limitOrder.getOrder(orderHash);
        
        assertEq(_maker, maker);
        assertEq(_srcAmount, _sourceAmount);
        assertEq(_destAmount, _destinationAmount);
        assertEq(_deadline, block.timestamp + _duration);
        assertTrue(_isActive);
    }
    
    function testMultipleOrders() public {
        uint256 numOrders = 3;
        bytes32[] memory orderHashes = new bytes32[](numOrders);
        
        // Give maker enough WETH
        vm.deal(maker, numOrders * sourceAmount);
        vm.prank(maker);
        weth.deposit{value: numOrders * sourceAmount}();
        
        vm.startPrank(maker);
        weth.approve(address(limitOrder), numOrders * sourceAmount);
        
        // Create multiple orders
        for (uint256 i = 0; i < numOrders; i++) {
            ILimitOrderProtocol.DutchAuctionConfig memory config = auctionConfig;
            config.auctionStartTime = block.timestamp + (i * 10 minutes);
            config.auctionEndTime = config.auctionStartTime + 1 hours;
            
            orderHashes[i] = limitOrder.createCrossChainOrder(
                sourceAmount,
                destinationAmount + (i * 100 * 1e6), // Different destination amounts
                config
            );
        }
        
        vm.stopPrank();
        
        // Verify all orders were created
        for (uint256 i = 0; i < numOrders; i++) {
            (
                address _maker,
                ,
                uint256 _sourceAmount,
                uint256 _destinationAmount,
                ,
                bool _isActive,
                ,,,
            ) = limitOrder.getOrder(orderHashes[i]);
            
            assertEq(_maker, maker);
            assertEq(_sourceAmount, sourceAmount);
            assertEq(_destinationAmount, destinationAmount + (i * 100 * 1e6));
            assertTrue(_isActive);
        }
    }
}