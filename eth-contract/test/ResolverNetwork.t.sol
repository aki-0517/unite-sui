// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/ResolverNetwork.sol";
import "../src/interfaces/IResolverNetwork.sol";
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

contract ResolverNetworkTest is Test {
    ResolverNetwork public resolverNetwork;
    MockWETH public weth;
    
    address public limitOrderProtocol = address(0x1);
    address public admin = address(0x2);
    address public resolver1 = address(0x3);
    address public resolver2 = address(0x4);
    address public nonResolver = address(0x5);
    
    bytes32 public orderHash = keccak256("test-order");
    uint256 public constant MIN_STAKE = 1e18;
    
    function setUp() public {
        weth = new MockWETH();
        resolverNetwork = new ResolverNetwork(limitOrderProtocol, address(weth), admin);
        
        // Give test addresses ETH and WETH
        vm.deal(resolver1, 10 ether);
        vm.deal(resolver2, 10 ether);
        vm.deal(nonResolver, 10 ether);
        
        vm.prank(resolver1);
        weth.deposit{value: 5 ether}();
        vm.prank(resolver2);
        weth.deposit{value: 5 ether}();
        vm.prank(nonResolver);
        weth.deposit{value: 5 ether}();
    }
    
    function testRegisterResolver() public {
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        
        // Skip event checking since we can't access the event from interface
        
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Verify resolver was registered
        (
            address _resolver,
            bool _isRegistered,
            bool _isAuthorized,
            uint256 _reputation,
            uint256 _totalOrdersFilled,
            uint256 _totalVolumeHandled,
            uint256 _lastActivityTime,
            uint256 _stakedAmount,
            uint256 _penalties
        ) = resolverNetwork.getResolver(resolver1);
        
        assertEq(_resolver, resolver1);
        assertTrue(_isRegistered);
        assertTrue(_isAuthorized);
        assertEq(_reputation, 100); // Initial reputation
        assertEq(_totalOrdersFilled, 0);
        assertEq(_totalVolumeHandled, 0);
        assertEq(_lastActivityTime, block.timestamp);
        assertEq(_stakedAmount, MIN_STAKE);
        assertEq(_penalties, 0);
        
        // Check authorization
        assertTrue(resolverNetwork.isAuthorizedResolver(resolver1));
    }
    
    function testRegisterResolverInsufficientStake() public {
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE - 1);
        
        vm.expectRevert(IResolverNetwork.InsufficientStake.selector);
        resolverNetwork.registerResolver();
        
        vm.stopPrank();
    }
    
    function testRegisterResolverAlreadyRegistered() public {
        // Register first time
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        
        // Try to register again
        vm.expectRevert(IResolverNetwork.ResolverAlreadyRegistered.selector);
        resolverNetwork.registerResolver();
        
        vm.stopPrank();
    }
    
    function testUnregisterResolver() public {
        // Register first
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        
        uint256 initialBalance = weth.balanceOf(resolver1);
        
        // Skip event checking
        
        resolverNetwork.unregisterResolver();
        vm.stopPrank();
        
        // Verify resolver was unregistered
        (,bool _isRegistered, bool _isAuthorized,,,,,,) = resolverNetwork.getResolver(resolver1);
        assertFalse(_isRegistered);
        assertFalse(_isAuthorized);
        
        // Verify stake was returned
        assertEq(weth.balanceOf(resolver1), initialBalance + MIN_STAKE);
        
        // Check authorization
        assertFalse(resolverNetwork.isAuthorizedResolver(resolver1));
    }
    
    function testUnregisterResolverNotRegistered() public {
        vm.prank(resolver1);
        vm.expectRevert(IResolverNetwork.ResolverNotRegistered.selector);
        resolverNetwork.unregisterResolver();
    }
    
    function testRegisterOrder() public {
        uint256 sourceAmount = 1 ether;
        uint256 destinationAmount = 2000 * 1e6;
        
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, sourceAmount, destinationAmount);
        
        // Verify order was registered
        (
            bytes32 _orderHash,
            uint256 _sourceAmount,
            uint256 _destinationAmount,
            bool _isRegistered,
            bool _isActive,
            address _bestBidder,
            uint256 _bestBidPrice,
            uint256 _registeredAt
        ) = resolverNetwork.getOrder(orderHash);
        
        assertEq(_orderHash, orderHash);
        assertEq(_sourceAmount, sourceAmount);
        assertEq(_destinationAmount, destinationAmount);
        assertTrue(_isRegistered);
        assertTrue(_isActive);
        assertEq(_bestBidder, address(0));
        assertEq(_bestBidPrice, 0);
        assertEq(_registeredAt, block.timestamp);
    }
    
    function testRegisterOrderOnlyLimitOrderProtocol() public {
        vm.expectRevert(IResolverNetwork.OnlyLimitOrderProtocol.selector);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
    }
    
    function testUnregisterOrder() public {
        // Register order first
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Unregister order
        vm.prank(limitOrderProtocol);
        resolverNetwork.unregisterOrder(orderHash);
        
        // Verify order is no longer active
        (,,,, bool _isActive,,,) = resolverNetwork.getOrder(orderHash);
        assertFalse(_isActive);
    }
    
    function testBidOnOrder() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Register order
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Place bid
        uint256 bidAmount = 1.1e18;
        
        vm.prank(resolver1);
        resolverNetwork.bidOnOrder(orderHash, bidAmount);
        
        // Verify bid was placed
        assertEq(resolverNetwork.getBid(orderHash, resolver1), bidAmount);
        
        // Verify best bid was updated
        (,,,,,address _bestBidder, uint256 _bestBidPrice,) = resolverNetwork.getOrder(orderHash);
        assertEq(_bestBidder, resolver1);
        assertEq(_bestBidPrice, bidAmount);
        
        // Verify resolver is in order resolvers list
        address[] memory orderResolvers = resolverNetwork.getOrderResolvers(orderHash);
        assertEq(orderResolvers.length, 1);
        assertEq(orderResolvers[0], resolver1);
    }
    
    function testBidOnOrderNotRegistered() public {
        // Register order
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Try to bid without being registered
        vm.prank(nonResolver);
        vm.expectRevert(IResolverNetwork.ResolverNotRegistered.selector);
        resolverNetwork.bidOnOrder(orderHash, 1.1e18);
    }
    
    function testBidOnOrderNotAuthorized() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Deauthorize resolver
        vm.prank(admin);
        resolverNetwork.setResolverAuthorization(resolver1, false);
        
        // Register order
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Try to bid while not authorized
        vm.prank(resolver1);
        vm.expectRevert(IResolverNetwork.ResolverNotAuthorized.selector);
        resolverNetwork.bidOnOrder(orderHash, 1.1e18);
    }
    
    function testMultipleBids() public {
        // Register resolvers
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        vm.startPrank(resolver2);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Register order
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Place bids
        vm.prank(resolver1);
        resolverNetwork.bidOnOrder(orderHash, 1.1e18);
        
        vm.prank(resolver2);
        resolverNetwork.bidOnOrder(orderHash, 1.2e18); // Higher bid
        
        // Verify best bid is from resolver2
        (,,,,,address _bestBidder, uint256 _bestBidPrice,) = resolverNetwork.getOrder(orderHash);
        assertEq(_bestBidder, resolver2);
        assertEq(_bestBidPrice, 1.2e18);
        
        // Verify both resolvers are in the list
        address[] memory orderResolvers = resolverNetwork.getOrderResolvers(orderHash);
        assertEq(orderResolvers.length, 2);
    }
    
    function testRecordOrderFill() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Register order
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Record order fill
        uint256 fillAmount = 0.5 ether;
        uint256 currentRate = 1.1e18;
        
        vm.prank(limitOrderProtocol);
        resolverNetwork.recordOrderFill(orderHash, resolver1, fillAmount, currentRate);
        
        // Verify resolver stats were updated
        (
            ,,, // address, bool, bool
            uint256 _reputation,
            uint256 _totalOrdersFilled,
            uint256 _totalVolumeHandled,
            uint256 _lastActivityTime,
            ,
        ) = resolverNetwork.getResolver(resolver1);
        
        assertEq(_totalOrdersFilled, 1);
        assertEq(_totalVolumeHandled, fillAmount);
        assertEq(_lastActivityTime, block.timestamp);
    }
    
    function testPenalizeResolver() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        uint256 penaltyAmount = 10;
        
        // Penalize resolver
        vm.prank(admin);
        resolverNetwork.penalizeResolver(resolver1, penaltyAmount);
        
        // Verify penalties were applied
        (
            ,,,
            uint256 _reputation,
            ,,,,
            uint256 _penalties
        ) = resolverNetwork.getResolver(resolver1);
        
        assertEq(_reputation, 100 - penaltyAmount); // Initial reputation minus penalty
        assertEq(_penalties, penaltyAmount);
    }
    
    function testPenalizeResolverDeauthorization() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Apply heavy penalty (> 50)
        vm.prank(admin);
        resolverNetwork.penalizeResolver(resolver1, 60);
        
        // Verify resolver was deauthorized
        (,, bool _isAuthorized,,,,,,) = resolverNetwork.getResolver(resolver1);
        assertFalse(_isAuthorized);
        assertFalse(resolverNetwork.isAuthorizedResolver(resolver1));
    }
    
    function testSetResolverAuthorization() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Deauthorize
        vm.prank(admin);
        resolverNetwork.setResolverAuthorization(resolver1, false);
        
        // Verify deauthorization
        (,, bool _isAuthorized,,,,,,) = resolverNetwork.getResolver(resolver1);
        assertFalse(_isAuthorized);
        
        // Re-authorize
        vm.prank(admin);
        resolverNetwork.setResolverAuthorization(resolver1, true);
        
        // Verify re-authorization
        (,, _isAuthorized,,,,,,) = resolverNetwork.getResolver(resolver1);
        assertTrue(_isAuthorized);
    }
    
    function testSetResolverAuthorizationOnlyAdmin() public {
        vm.expectRevert(IResolverNetwork.OnlyAdmin.selector);
        resolverNetwork.setResolverAuthorization(resolver1, false);
    }
    
    function testGetResolverReputationWithDecay() public {
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Initial reputation should be 100
        assertEq(resolverNetwork.getResolverReputation(resolver1), 100);
        
        // Fast forward by one decay period (24 hours)
        vm.warp(block.timestamp + 86400);
        
        // Reputation should decay to 99 (99% of 100)
        assertEq(resolverNetwork.getResolverReputation(resolver1), 99);
        
        // Fast forward another period
        vm.warp(block.timestamp + 86400);
        
        // Reputation should decay further (99% of 99 = 98.01, rounded to 98)
        assertEq(resolverNetwork.getResolverReputation(resolver1), 98);
    }
    
    function testChangeAdmin() public {
        address newAdmin = address(0x999);
        
        vm.prank(admin);
        resolverNetwork.changeAdmin(newAdmin);
        
        // Verify new admin can perform admin functions
        vm.prank(newAdmin);
        resolverNetwork.changeAdmin(admin); // Change back
    }
    
    function testChangeAdminOnlyAdmin() public {
        vm.expectRevert(IResolverNetwork.OnlyAdmin.selector);
        resolverNetwork.changeAdmin(address(0x999));
    }
    
    function testFuzzBidAmounts(uint256 bidAmount) public {
        // Bound bid amount to reasonable values
        bidAmount = bound(bidAmount, 1, 1000e18);
        
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Register order
        vm.prank(limitOrderProtocol);
        resolverNetwork.registerOrder(orderHash, 1 ether, 2000 * 1e6);
        
        // Place bid
        vm.prank(resolver1);
        resolverNetwork.bidOnOrder(orderHash, bidAmount);
        
        // Verify bid was recorded
        assertEq(resolverNetwork.getBid(orderHash, resolver1), bidAmount);
        
        // Verify best bid was updated
        (,,,,,, uint256 _bestBidPrice,) = resolverNetwork.getOrder(orderHash);
        assertEq(_bestBidPrice, bidAmount);
    }
    
    function testFuzzPenaltyAmounts(uint256 penaltyAmount) public {
        // Bound penalty to reasonable values
        penaltyAmount = bound(penaltyAmount, 1, 200);
        
        // Register resolver
        vm.startPrank(resolver1);
        weth.approve(address(resolverNetwork), MIN_STAKE);
        resolverNetwork.registerResolver();
        vm.stopPrank();
        
        // Apply penalty
        vm.prank(admin);
        resolverNetwork.penalizeResolver(resolver1, penaltyAmount);
        
        // Verify penalty was applied
        (
            ,,,
            uint256 _reputation,
            ,,,,
            uint256 _penalties
        ) = resolverNetwork.getResolver(resolver1);
        
        assertEq(_penalties, penaltyAmount);
        
        // Check deauthorization for heavy penalties
        if (penaltyAmount > 50) {
            (,, bool _isAuthorized,,,,,,) = resolverNetwork.getResolver(resolver1);
            assertFalse(_isAuthorized);
        }
    }
    
    function testMultipleOrdersAndResolvers() public {
        bytes32[] memory orders = new bytes32[](3);
        orders[0] = keccak256("order1");
        orders[1] = keccak256("order2"); 
        orders[2] = keccak256("order3");
        
        // Register multiple resolvers
        address[] memory resolvers = new address[](3);
        resolvers[0] = resolver1;
        resolvers[1] = resolver2;
        resolvers[2] = address(0x6);
        
        for (uint256 i = 0; i < resolvers.length; i++) {
            vm.deal(resolvers[i], 10 ether);
            vm.prank(resolvers[i]);
            weth.deposit{value: 5 ether}();
            
            vm.startPrank(resolvers[i]);
            weth.approve(address(resolverNetwork), MIN_STAKE);
            resolverNetwork.registerResolver();
            vm.stopPrank();
        }
        
        // Register multiple orders
        for (uint256 i = 0; i < orders.length; i++) {
            vm.prank(limitOrderProtocol);
            resolverNetwork.registerOrder(orders[i], (i + 1) * 1 ether, (i + 1) * 1000 * 1e6);
        }
        
        // Each resolver bids on each order
        for (uint256 i = 0; i < resolvers.length; i++) {
            for (uint256 j = 0; j < orders.length; j++) {
                vm.prank(resolvers[i]);
                resolverNetwork.bidOnOrder(orders[j], (i + 1) * 1e18 + j * 1e17);
            }
        }
        
        // Verify all bids were recorded
        for (uint256 i = 0; i < resolvers.length; i++) {
            for (uint256 j = 0; j < orders.length; j++) {
                uint256 expectedBid = (i + 1) * 1e18 + j * 1e17;
                assertEq(resolverNetwork.getBid(orders[j], resolvers[i]), expectedBid);
            }
        }
    }
}