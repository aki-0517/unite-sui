// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/CrossChainOrder.sol";
import "../src/core/LimitOrderProtocol.sol";
import "../src/core/DutchAuction.sol";
import "../src/core/ResolverNetwork.sol";
import "../src/core/EthereumEscrow.sol";
import "../src/interfaces/ICrossChainOrder.sol";
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

contract CrossChainOrderTest is Test {
    CrossChainOrder public crossChainOrder;
    LimitOrderProtocol public limitOrder;
    DutchAuction public dutchAuction;
    ResolverNetwork public resolverNetwork;
    EthereumEscrow public escrow;
    MockWETH public weth;
    
    address public admin = address(0x1);
    address public maker = address(0x2);
    address public resolver1 = address(0x3);
    
    uint256 public sourceAmount = 1 ether;
    uint256 public destinationAmount = 2000 * 1e6;
    bytes32 public secret = bytes32("secret");
    bytes32 public hashLock;
    uint256 public timeLock;
    string public suiOrderHash = "0x1234567890abcdef";
    
    ILimitOrderProtocol.DutchAuctionConfig public auctionConfig;
    
    function setUp() public {
        // Deploy WETH
        weth = new MockWETH();
        
        // Deploy contracts in correct order
        escrow = new EthereumEscrow(address(weth));
        
        // Calculate the future addresses (this is just an approximation)
        uint256 nonce = vm.getNonce(address(this));
        address futureAuction = vm.computeCreateAddress(address(this), nonce + 1);
        address futureResolver = vm.computeCreateAddress(address(this), nonce + 2);
        
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
        
        crossChainOrder = new CrossChainOrder(
            address(limitOrder),
            address(escrow),
            address(dutchAuction),
            address(resolverNetwork),
            address(weth)
        );
        
        // Setup auction config
        auctionConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + 1 hours,
            startRate: 1.2e18,
            endRate: 1.0e18,
            decreaseRate: 0
        });
        
        hashLock = keccak256(abi.encodePacked(secret));
        timeLock = block.timestamp + 2 hours;
        
        // Give test addresses ETH and WETH
        vm.deal(maker, 10 ether);
        vm.deal(resolver1, 10 ether);
        
        vm.prank(maker);
        weth.deposit{value: 5 ether}();
        vm.prank(resolver1);
        weth.deposit{value: 5 ether}();
        
        // Register resolver
        vm.prank(resolver1);
        weth.approve(address(resolverNetwork), 1e18);
        vm.prank(resolver1);
        resolverNetwork.registerResolver();
    }
    
    function testCreateCrossChainOrderWithEscrow() public {
        vm.startPrank(maker);
        
        // Approve CrossChainOrder contract to spend WETH (needs 2x sourceAmount)
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        // Note: We can't predict the exact orderHash and escrowId, so we skip the event check
        
        (bytes32 orderHash, bytes32 escrowId) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Verify cross-chain order was created
        (
            bytes32 _orderHash,
            bytes32 _escrowId,
            address _maker,
            uint256 _sourceAmount,
            uint256 _destinationAmount,
            bytes32 _hashLock,
            uint256 _timeLock,
            string memory _suiOrderHash,
            ICrossChainOrder.CrossChainOrderStatus _status,
            uint256 _createdAt,
            uint256 _completedAt
        ) = crossChainOrder.getCrossChainOrder(orderHash);
        
        assertEq(_orderHash, orderHash);
        assertEq(_escrowId, escrowId);
        assertEq(_maker, maker);
        assertEq(_sourceAmount, sourceAmount);
        assertEq(_destinationAmount, destinationAmount);
        assertEq(_hashLock, hashLock);
        assertEq(_timeLock, timeLock);
        assertEq(_suiOrderHash, suiOrderHash);
        assertEq(uint256(_status), uint256(ICrossChainOrder.CrossChainOrderStatus.Active));
        assertEq(_createdAt, block.timestamp);
        assertEq(_completedAt, 0);
        
        // Verify mappings
        assertEq(crossChainOrder.getEscrowForOrder(orderHash), escrowId);
        assertEq(crossChainOrder.getOrderForEscrow(escrowId), orderHash);
    }
    
    function testFillCrossChainOrder() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash, bytes32 escrowId) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Fill cross-chain order
        uint256 initialBalance = weth.balanceOf(resolver1);
        
        vm.prank(resolver1);
        crossChainOrder.fillCrossChainOrder(orderHash, secret);
        
        // Verify resolver received tokens
        assertTrue(weth.balanceOf(resolver1) > initialBalance);
        
        // Verify order status
        ICrossChainOrder.CrossChainOrderStatus status = crossChainOrder.getOrderStatus(orderHash);
        assertEq(uint256(status), uint256(ICrossChainOrder.CrossChainOrderStatus.Completed));
    }
    
    function testCompleteCrossChainOrder() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash, bytes32 escrowId) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Complete cross-chain order
        uint256 initialBalance = weth.balanceOf(resolver1);
        
        vm.prank(resolver1);
        crossChainOrder.completeCrossChainOrder(orderHash, secret);
        
        // Verify resolver received tokens
        assertEq(weth.balanceOf(resolver1), initialBalance + sourceAmount);
        
        // Verify order status
        ICrossChainOrder.CrossChainOrderStatus status = crossChainOrder.getOrderStatus(orderHash);
        assertEq(uint256(status), uint256(ICrossChainOrder.CrossChainOrderStatus.Completed));
    }
    
    function testFillCrossChainOrderInvalidSecret() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Try to fill with wrong secret
        bytes32 wrongSecret = bytes32("wrongsecret");
        
        vm.prank(resolver1);
        vm.expectRevert(ICrossChainOrder.InvalidSecret.selector);
        crossChainOrder.fillCrossChainOrder(orderHash, wrongSecret);
    }
    
    function testFillCrossChainOrderUnauthorizedResolver() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Try to fill with unauthorized resolver
        address unauthorizedResolver = address(0x999);
        
        vm.prank(unauthorizedResolver);
        vm.expectRevert(ICrossChainOrder.UnauthorizedResolver.selector);
        crossChainOrder.fillCrossChainOrder(orderHash, secret);
    }
    
    function testCancelCrossChainOrder() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash, bytes32 escrowId) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        crossChainOrder.cancelCrossChainOrder(orderHash);
        
        vm.stopPrank();
        
        // Verify order status
        ICrossChainOrder.CrossChainOrderStatus status = crossChainOrder.getOrderStatus(orderHash);
        assertEq(uint256(status), uint256(ICrossChainOrder.CrossChainOrderStatus.Cancelled));
    }
    
    function testCancelCrossChainOrderOnlyMaker() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Try to cancel from non-maker
        vm.prank(resolver1);
        vm.expectRevert(ICrossChainOrder.OnlyMaker.selector);
        crossChainOrder.cancelCrossChainOrder(orderHash);
    }
    
    function testEmergencyRefund() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash, bytes32 escrowId) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        // Fast forward past time lock
        vm.warp(timeLock + 1);
        
        uint256 initialBalance = weth.balanceOf(maker);
        
        crossChainOrder.emergencyRefund(orderHash);
        
        vm.stopPrank();
        
        // Verify refund
        assertEq(weth.balanceOf(maker), initialBalance + sourceAmount);
        
        // Verify order status
        ICrossChainOrder.CrossChainOrderStatus status = crossChainOrder.getOrderStatus(orderHash);
        assertEq(uint256(status), uint256(ICrossChainOrder.CrossChainOrderStatus.Refunded));
    }
    
    function testEmergencyRefundNotExpired() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        // Try emergency refund before expiry
        vm.expectRevert(ICrossChainOrder.OrderNotExpired.selector);
        crossChainOrder.emergencyRefund(orderHash);
        
        vm.stopPrank();
    }
    
    function testCanFillCrossChainOrder() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Check authorized resolver can fill
        assertTrue(crossChainOrder.canFillCrossChainOrder(orderHash, resolver1));
        
        // Check unauthorized resolver cannot fill
        assertFalse(crossChainOrder.canFillCrossChainOrder(orderHash, address(0x999)));
    }
    
    function testGetCurrentRate() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Check initial rate
        uint256 currentRate = crossChainOrder.getCurrentRate(orderHash);
        assertEq(currentRate, auctionConfig.startRate);
        
        // Fast forward and check decreased rate
        vm.warp(block.timestamp + 30 minutes);
        uint256 newRate = crossChainOrder.getCurrentRate(orderHash);
        assertTrue(newRate < auctionConfig.startRate);
        assertTrue(newRate > auctionConfig.endRate);
    }
    
    function testIsOrderExpired() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Check not expired initially
        assertFalse(crossChainOrder.isOrderExpired(orderHash));
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        assertTrue(crossChainOrder.isOrderExpired(orderHash));
    }
    
    function testFillExpiredOrder() public {
        // Create cross-chain order
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), sourceAmount * 2);
        
        (bytes32 orderHash,) = crossChainOrder.createCrossChainOrderWithEscrow(
            sourceAmount,
            destinationAmount,
            auctionConfig,
            hashLock,
            timeLock,
            suiOrderHash
        );
        
        vm.stopPrank();
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Try to fill expired order
        vm.prank(resolver1);
        vm.expectRevert(ICrossChainOrder.OrderExpired.selector);
        crossChainOrder.fillCrossChainOrder(orderHash, secret);
    }
    
    function testOrderNotFound() public {
        bytes32 nonexistentOrder = keccak256("nonexistent");
        
        vm.prank(resolver1);
        vm.expectRevert(ICrossChainOrder.OrderNotFound.selector);
        crossChainOrder.fillCrossChainOrder(nonexistentOrder, secret);
        
        vm.prank(maker);
        vm.expectRevert(ICrossChainOrder.OrderNotFound.selector);
        crossChainOrder.cancelCrossChainOrder(nonexistentOrder);
    }
    
    function testFuzzOrderParameters(
        uint256 _sourceAmount,
        uint256 _destinationAmount,
        uint256 _auctionDuration,
        uint256 _timeLockDuration
    ) public {
        // Bound inputs to reasonable values
        _sourceAmount = bound(_sourceAmount, 1e15, 100 ether); // 0.001 to 100 ETH
        _destinationAmount = bound(_destinationAmount, 1, 1e12);
        _auctionDuration = bound(_auctionDuration, 300, 86400); // 5 min to 24 hours
        _timeLockDuration = bound(_timeLockDuration, _auctionDuration + 300, 172800); // At least auction + 5 min, max 48 hours
        
        // Give maker enough WETH (needs 2x)
        vm.deal(maker, _sourceAmount * 2);
        vm.prank(maker);
        weth.deposit{value: _sourceAmount * 2}();
        
        ILimitOrderProtocol.DutchAuctionConfig memory fuzzConfig = ILimitOrderProtocol.DutchAuctionConfig({
            auctionStartTime: block.timestamp,
            auctionEndTime: block.timestamp + _auctionDuration,
            startRate: 1.2e18,
            endRate: 1.0e18,
            decreaseRate: 0
        });
        
        bytes32 fuzzHashLock = keccak256(abi.encodePacked("fuzzsecret"));
        uint256 fuzzTimeLock = block.timestamp + _timeLockDuration;
        
        vm.startPrank(maker);
        weth.approve(address(crossChainOrder), _sourceAmount * 2);
        
        (bytes32 orderHash, bytes32 escrowId) = crossChainOrder.createCrossChainOrderWithEscrow(
            _sourceAmount,
            _destinationAmount, 
            fuzzConfig,
            fuzzHashLock,
            fuzzTimeLock,
            "fuzz-order"
        );
        
        vm.stopPrank();
        
        // Verify order creation - split into smaller checks to avoid stack too deep
        {
            (bytes32 _orderHash, bytes32 _escrowId, address _maker,,,,,,,,) = crossChainOrder.getCrossChainOrder(orderHash);
            assertEq(_orderHash, orderHash);
            assertEq(_escrowId, escrowId);
            assertEq(_maker, maker);
        }
        
        {
            (,,, uint256 _srcAmount, uint256 _destAmount,,,,ICrossChainOrder.CrossChainOrderStatus _status,,) = crossChainOrder.getCrossChainOrder(orderHash);
            assertEq(_srcAmount, _sourceAmount);
            assertEq(_destAmount, _destinationAmount);
            assertEq(uint256(_status), uint256(ICrossChainOrder.CrossChainOrderStatus.Active));
        }
    }
    
    function testMultipleCrossChainOrders() public {
        uint256 numOrders = 3;
        bytes32[] memory orderHashes = new bytes32[](numOrders);
        bytes32[] memory escrowIds = new bytes32[](numOrders);
        
        // Give maker enough WETH (needs 2x per order)
        vm.deal(maker, numOrders * sourceAmount * 2);
        vm.prank(maker);
        weth.deposit{value: numOrders * sourceAmount * 2}();
        
        vm.startPrank(maker);
        
        // Approve total amount needed for all orders
        weth.approve(address(crossChainOrder), numOrders * sourceAmount * 2);
        
        // Create multiple cross-chain orders
        for (uint256 i = 0; i < numOrders; i++) {
            
            ILimitOrderProtocol.DutchAuctionConfig memory config = auctionConfig;
            config.auctionStartTime = block.timestamp + (i * 10 minutes);
            config.auctionEndTime = config.auctionStartTime + 1 hours;
            
            bytes32 orderHashLock = keccak256(abi.encodePacked("secret", i));
            uint256 orderTimeLock = block.timestamp + 2 hours + (i * 10 minutes);
            string memory orderSuiHash = string(abi.encodePacked("sui-order-", i));
            
            (orderHashes[i], escrowIds[i]) = crossChainOrder.createCrossChainOrderWithEscrow(
                sourceAmount,
                destinationAmount + (i * 100 * 1e6),
                config,
                orderHashLock,
                orderTimeLock,
                orderSuiHash
            );
        }
        
        vm.stopPrank();
        
        // Verify all orders were created correctly
        for (uint256 i = 0; i < numOrders; i++) {
            // Split verification to avoid stack too deep
            {
                (bytes32 _orderHash, bytes32 _escrowId, address _maker,,,,,,,,) = crossChainOrder.getCrossChainOrder(orderHashes[i]);
                assertEq(_orderHash, orderHashes[i]);
                assertEq(_escrowId, escrowIds[i]);
                assertEq(_maker, maker);
            }
            
            {
                (,,, uint256 _sourceAmount, uint256 _destinationAmount,,,,ICrossChainOrder.CrossChainOrderStatus _status,,) = crossChainOrder.getCrossChainOrder(orderHashes[i]);
                assertEq(_sourceAmount, sourceAmount);
                assertEq(_destinationAmount, destinationAmount + (i * 100 * 1e6));
                assertEq(uint256(_status), uint256(ICrossChainOrder.CrossChainOrderStatus.Active));
            }
            
            // Verify mappings
            assertEq(crossChainOrder.getEscrowForOrder(orderHashes[i]), escrowIds[i]);
            assertEq(crossChainOrder.getOrderForEscrow(escrowIds[i]), orderHashes[i]);
        }
    }
}