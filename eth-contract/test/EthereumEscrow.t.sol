// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/core/EthereumEscrow.sol";
import "../src/interfaces/IEthereumEscrow.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

// Mock WETH contract for testing
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

contract EthereumEscrowTest is Test {
    EthereumEscrow public escrow;
    MockWETH public weth;
    
    address public maker = address(0x1);
    address public taker = address(0x2);
    address public other = address(0x3);
    address public resolver1 = address(0x4);
    address public resolver2 = address(0x5);
    
    bytes32 public secret = bytes32("mysecret");
    bytes32 public hashLock;
    uint256 public timeLock;
    uint256 public amount = 1 ether;
    string public suiOrderHash = "0x1234567890abcdef";
    
    bytes32 public escrowId;
    
    event EscrowCreated(
        bytes32 indexed escrowId,
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bytes32 hashLock,
        uint256 timeLock,
        string suiOrderHash,
        bool isWeth
    );
    
    event EscrowPartiallyFilled(
        bytes32 indexed escrowId,
        address indexed resolver,
        uint256 amount,
        uint256 remainingAmount,
        bytes32 secret,
        string suiOrderHash
    );
    
    event EscrowCompleted(
        bytes32 indexed escrowId,
        address indexed lastResolver,
        bytes32 secret,
        string suiOrderHash
    );
    
    event EscrowRefunded(
        bytes32 indexed escrowId,
        address indexed maker,
        uint256 amount,
        string suiOrderHash
    );

    function setUp() public {
        // Deploy mock WETH
        weth = new MockWETH();
        
        // Deploy escrow with WETH address
        escrow = new EthereumEscrow(address(weth));
        
        hashLock = escrow.createHashLock(secret);
        timeLock = block.timestamp + 1 hours;
        
        // Give test addresses some ETH and WETH
        vm.deal(maker, 20 ether);
        vm.deal(taker, 20 ether);
        vm.deal(other, 20 ether);
        vm.deal(resolver1, 20 ether);
        vm.deal(resolver2, 20 ether);
        
        // Convert ETH to WETH for test addresses
        vm.prank(maker);
        weth.deposit{value: 15 ether}();
        vm.prank(taker);
        weth.deposit{value: 15 ether}();
        vm.prank(resolver1);
        weth.deposit{value: 15 ether}();
        vm.prank(resolver2);
        weth.deposit{value: 15 ether}();
    }
    
    function testCreateEscrow() public {
        vm.startPrank(maker);
        
        // Approve WETH spending
        weth.approve(address(escrow), amount);
        
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        vm.stopPrank();
        
        // Verify escrow was created correctly
        (
            address _maker,
            address _taker,
            uint256 _totalAmount,
            uint256 _remainingAmount,
            bytes32 _hashLock,
            uint256 _timeLock,
            bool _completed,
            bool _refunded,
            uint256 _createdAt,
            string memory _suiOrderHash
        ) = escrow.getEscrow(escrowId);
        
        assertEq(_maker, maker);
        assertEq(_taker, taker);
        assertEq(_totalAmount, amount);
        assertEq(_remainingAmount, amount);
        assertEq(_hashLock, hashLock);
        assertEq(_timeLock, timeLock);
        assertFalse(_completed);
        assertFalse(_refunded);
        assertEq(_createdAt, block.timestamp);
        assertEq(_suiOrderHash, suiOrderHash);
    }
    
    function testCreateEscrowWithZeroAmount() public {
        vm.startPrank(maker);
        
        vm.expectRevert(IEthereumEscrow.InvalidWethAmount.selector);
        escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            0
        );
        
        vm.stopPrank();
    }
    
    function testCreateEscrowWithPastTimeLock() public {
        vm.startPrank(maker);
        
        uint256 pastTimeLock = block.timestamp - 1;
        
        vm.expectRevert(IEthereumEscrow.InvalidTimeLock.selector);
        escrow.createEscrow(
            hashLock,
            pastTimeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        vm.stopPrank();
    }
    
    function testCreateEscrowWithZeroTaker() public {
        vm.startPrank(maker);
        
        // Approve WETH spending
        weth.approve(address(escrow), amount);
        
        // Zero address taker is now allowed for open fills
        bytes32 openEscrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(address(0)),
            suiOrderHash,
            amount
        );
        
        // Verify escrow was created with zero taker
        (,address _taker,,,,,,,,) = escrow.getEscrow(openEscrowId);
        assertEq(_taker, address(0));
        
        vm.stopPrank();
    }
    
    function testCompleteEscrow() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Check initial taker WETH balance
        uint256 initialBalance = weth.balanceOf(taker);
        
        // Complete the escrow
        vm.startPrank(taker);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowCompleted(escrowId, taker, secret, suiOrderHash);
        
        escrow.completeEscrow(escrowId, secret);
        
        vm.stopPrank();
        
        // Verify taker received the WETH
        assertEq(weth.balanceOf(taker), initialBalance + amount);
        
        // Verify escrow is marked as completed
        (,,,,,, bool completed, bool refunded,,) = escrow.getEscrow(escrowId);
        assertTrue(completed);
        assertFalse(refunded);
        
        // Verify secret is stored
        assertEq(escrow.getSecret(escrowId), secret);
    }
    
    function testCompleteEscrowWithWrongSecret() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Try to complete with wrong secret
        vm.startPrank(taker);
        
        bytes32 wrongSecret = bytes32("wrongsecret");
        
        vm.expectRevert(IEthereumEscrow.InvalidSecret.selector);
        escrow.completeEscrow(escrowId, wrongSecret);
        
        vm.stopPrank();
    }
    
    function testCompleteEscrowByWrongTaker() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Try to complete by wrong person
        vm.startPrank(other);
        
        vm.expectRevert(IEthereumEscrow.OnlyTaker.selector);
        escrow.completeEscrow(escrowId, secret);
        
        vm.stopPrank();
    }
    
    function testCompleteEscrowAfterExpiry() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Try to complete after expiry
        vm.startPrank(taker);
        
        vm.expectRevert(IEthereumEscrow.EscrowExpired.selector);
        escrow.completeEscrow(escrowId, secret);
        
        vm.stopPrank();
    }
    
    function testCompleteEscrowTwice() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Complete the escrow once
        vm.prank(taker);
        escrow.completeEscrow(escrowId, secret);
        
        // Try to complete again
        vm.startPrank(taker);
        
        vm.expectRevert(IEthereumEscrow.EscrowAlreadyCompleted.selector);
        escrow.completeEscrow(escrowId, secret);
        
        vm.stopPrank();
    }
    
    function testRefundEscrow() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Check initial maker WETH balance
        uint256 initialBalance = weth.balanceOf(maker);
        
        // Refund the escrow
        vm.startPrank(maker);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowRefunded(escrowId, maker, amount, suiOrderHash);
        
        escrow.refundEscrow(escrowId);
        
        vm.stopPrank();
        
        // Verify maker received the refund
        assertEq(weth.balanceOf(maker), initialBalance + amount);
        
        // Verify escrow is marked as refunded
        (,,,,,, bool completed, bool refunded,,) = escrow.getEscrow(escrowId);
        assertFalse(completed);
        assertTrue(refunded);
    }
    
    function testRefundEscrowBeforeExpiry() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Try to refund before expiry
        vm.startPrank(maker);
        
        vm.expectRevert(IEthereumEscrow.EscrowNotExpired.selector);
        escrow.refundEscrow(escrowId);
        
        vm.stopPrank();
    }
    
    function testRefundEscrowByWrongMaker() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Try to refund by wrong person
        vm.startPrank(other);
        
        vm.expectRevert(IEthereumEscrow.OnlyMaker.selector);
        escrow.refundEscrow(escrowId);
        
        vm.stopPrank();
    }
    
    function testRefundCompletedEscrow() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Complete the escrow
        vm.prank(taker);
        escrow.completeEscrow(escrowId, secret);
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Try to refund completed escrow
        vm.startPrank(maker);
        
        vm.expectRevert(IEthereumEscrow.EscrowAlreadyCompleted.selector);
        escrow.refundEscrow(escrowId);
        
        vm.stopPrank();
    }
    
    function testVerifySecret() public {
        bytes32 testSecret = bytes32("testsecret");
        bytes32 testHashLock = escrow.createHashLock(testSecret);
        
        assertTrue(escrow.verifySecret(testSecret, testHashLock));
        assertFalse(escrow.verifySecret(bytes32("wrongsecret"), testHashLock));
    }
    
    function testCreateHashLock() public {
        bytes32 testSecret = bytes32("testsecret");
        bytes32 expectedHash = keccak256(abi.encodePacked(testSecret));
        
        assertEq(escrow.createHashLock(testSecret), expectedHash);
    }
    
    function testIsExpired() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Check before expiry
        assertFalse(escrow.isExpired(escrowId));
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Check after expiry
        assertTrue(escrow.isExpired(escrowId));
    }
    
    function testCanComplete() public {
        // First create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Check before expiry
        assertTrue(escrow.canComplete(escrowId));
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        // Check after expiry
        assertFalse(escrow.canComplete(escrowId));
        
        // Go back in time and complete
        vm.warp(timeLock - 1);
        vm.prank(taker);
        escrow.completeEscrow(escrowId, secret);
        
        // Check after completion
        assertFalse(escrow.canComplete(escrowId));
    }
    
    function testSecretReuse() public {
        // Create first escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        bytes32 escrowId1 = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Complete first escrow
        vm.prank(taker);
        escrow.completeEscrow(escrowId1, secret);
        
        // Create second escrow with same hash lock
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        bytes32 escrowId2 = escrow.createEscrow(
            hashLock,
            timeLock + 1 hours,
            payable(taker),
            "different_order",
            amount
        );
        
        // Try to complete second escrow with same secret
        vm.startPrank(taker);
        
        vm.expectRevert(IEthereumEscrow.SecretAlreadyUsed.selector);
        escrow.completeEscrow(escrowId2, secret);
        
        vm.stopPrank();
    }
    
    function testGetContractBalance() public {
        uint256 initialBalance = escrow.getContractBalance();
        assertEq(initialBalance, 0);
        
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Check contract balance increased (WETH balance)
        assertEq(weth.balanceOf(address(escrow)), amount);
        
        // Complete the escrow
        vm.prank(taker);
        escrow.completeEscrow(escrowId, secret);
        
        // Check contract balance decreased
        assertEq(weth.balanceOf(address(escrow)), 0);
    }
    
    function testNonExistentEscrow() public {
        bytes32 nonExistentId = keccak256("nonexistent");
        
        vm.expectRevert(IEthereumEscrow.EscrowNotFound.selector);
        escrow.completeEscrow(nonExistentId, secret);
        
        vm.expectRevert(IEthereumEscrow.EscrowNotFound.selector);
        escrow.refundEscrow(nonExistentId);
    }
    
    function testFuzzCreateEscrow(uint256 _amount, uint256 _timeLockOffset) public {
        // Bound the inputs to reasonable values
        _amount = bound(_amount, 1, 1000 ether);
        _timeLockOffset = bound(_timeLockOffset, 1, 365 days);
        
        uint256 futureTimeLock = block.timestamp + _timeLockOffset;
        
        vm.deal(maker, _amount + 1 ether);
        vm.prank(maker);
        weth.deposit{value: _amount + 1 ether}();
        
        vm.startPrank(maker);
        weth.approve(address(escrow), _amount);
        
        bytes32 fuzzEscrowId = escrow.createEscrow(
            hashLock,
            futureTimeLock,
            payable(taker),
            suiOrderHash,
            _amount
        );
        
        vm.stopPrank();
        
        (
            address _maker,
            address _taker,
            uint256 _totalAmount,
            uint256 _remainingAmount,
            bytes32 _hashLock,
            uint256 _timeLock,
            bool _completed,
            bool _refunded,
            uint256 _createdAt,
            string memory _suiOrderHash
        ) = escrow.getEscrow(fuzzEscrowId);
        
        assertEq(_maker, maker);
        assertEq(_taker, taker);
        assertEq(_totalAmount, _amount);
        assertEq(_remainingAmount, _amount);
        assertEq(_hashLock, hashLock);
        assertEq(_timeLock, futureTimeLock);
        assertFalse(_completed);
        assertFalse(_refunded);
    }

    // ========== PARTIAL FILLS TESTS ==========

    function testFillEscrowPartial() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        uint256 fillAmount = amount / 2; // Fill half
        uint256 initialBalance = weth.balanceOf(taker);
        
        // Fill partially
        vm.startPrank(taker);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowPartiallyFilled(escrowId, taker, fillAmount, amount - fillAmount, secret, suiOrderHash);
        
        escrow.fillEscrow(escrowId, fillAmount, secret);
        
        vm.stopPrank();
        
        // Verify partial fill
        assertEq(weth.balanceOf(taker), initialBalance + fillAmount);
        assertEq(escrow.getRemainingAmount(escrowId), amount - fillAmount);
        
        // Verify escrow is not completed yet
        (,,,,,, bool completed,,,) = escrow.getEscrow(escrowId);
        assertFalse(completed);
    }

    function testFillEscrowMultiplePartials() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), 9 ether);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            9 ether
        );
        
        uint256 initialBalance = weth.balanceOf(taker);
        
        // First partial fill (3 ETH)
        vm.prank(taker);
        escrow.fillEscrow(escrowId, 3 ether, secret);
        
        assertEq(weth.balanceOf(taker), initialBalance + 3 ether);
        assertEq(escrow.getRemainingAmount(escrowId), 6 ether);
        
        // Second partial fill (2 ETH)
        vm.prank(taker);
        escrow.fillEscrow(escrowId, 2 ether, secret);
        
        assertEq(weth.balanceOf(taker), initialBalance + 5 ether);
        assertEq(escrow.getRemainingAmount(escrowId), 4 ether);
        
        // Final fill (4 ETH) - should complete
        vm.startPrank(taker);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowCompleted(escrowId, taker, secret, suiOrderHash);
        
        escrow.fillEscrow(escrowId, 4 ether, secret);
        
        vm.stopPrank();
        
        // Verify completion
        assertEq(weth.balanceOf(taker), initialBalance + 9 ether);
        assertEq(escrow.getRemainingAmount(escrowId), 0);
        
        (,,,,,, bool completed,,,) = escrow.getEscrow(escrowId);
        assertTrue(completed);
    }

    function testFillEscrowByMultipleResolvers() public {
        // Create an open escrow (taker = address(0))
        vm.prank(maker);
        weth.approve(address(escrow), 6 ether);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(address(0)), // Open to any resolver
            suiOrderHash,
            6 ether
        );
        
        uint256 resolver1InitialBalance = weth.balanceOf(resolver1);
        uint256 resolver2InitialBalance = weth.balanceOf(resolver2);
        
        // Resolver1 fills 2 ETH
        vm.startPrank(resolver1);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowPartiallyFilled(escrowId, resolver1, 2 ether, 4 ether, secret, suiOrderHash);
        
        escrow.fillEscrow(escrowId, 2 ether, secret);
        
        vm.stopPrank();
        
        // Resolver2 fills 4 ETH (completes the escrow)
        vm.startPrank(resolver2);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowCompleted(escrowId, resolver2, secret, suiOrderHash);
        
        escrow.fillEscrow(escrowId, 4 ether, secret);
        
        vm.stopPrank();
        
        // Verify both resolvers received their portions
        assertEq(weth.balanceOf(resolver1), resolver1InitialBalance + 2 ether);
        assertEq(weth.balanceOf(resolver2), resolver2InitialBalance + 4 ether);
        assertEq(escrow.getRemainingAmount(escrowId), 0);
        
        (,,,,,, bool completed,,,) = escrow.getEscrow(escrowId);
        assertTrue(completed);
    }

    function testFillEscrowExceedsRemaining() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Try to fill more than remaining
        vm.startPrank(taker);
        
        vm.expectRevert(IEthereumEscrow.InsufficientRemainingAmount.selector);
        escrow.fillEscrow(escrowId, amount + 1, secret);
        
        vm.stopPrank();
    }

    function testFillEscrowZeroAmount() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        // Try to fill with zero amount
        vm.startPrank(taker);
        
        vm.expectRevert(IEthereumEscrow.InvalidFillAmount.selector);
        escrow.fillEscrow(escrowId, 0, secret);
        
        vm.stopPrank();
    }

    function testFillEscrowAlreadyCompleted() public {
        // Create and complete an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        vm.prank(taker);
        escrow.completeEscrow(escrowId, secret);
        
        // Try to fill again
        vm.startPrank(taker);
        
        vm.expectRevert(IEthereumEscrow.EscrowAlreadyCompleted.selector);
        escrow.fillEscrow(escrowId, 1, secret);
        
        vm.stopPrank();
    }

    function testCompleteEscrowCallsFillEscrow() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), amount);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        uint256 initialBalance = weth.balanceOf(taker);
        
        // Complete should fill the entire remaining amount
        vm.startPrank(taker);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowCompleted(escrowId, taker, secret, suiOrderHash);
        
        escrow.completeEscrow(escrowId, secret);
        
        vm.stopPrank();
        
        // Verify full amount was transferred
        assertEq(weth.balanceOf(taker), initialBalance + amount);
        assertEq(escrow.getRemainingAmount(escrowId), 0);
        
        (,,,,,, bool completed,,,) = escrow.getEscrow(escrowId);
        assertTrue(completed);
    }

    function testGetRemainingAmount() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), 10 ether);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            10 ether
        );
        
        // Initially should equal total amount
        assertEq(escrow.getRemainingAmount(escrowId), 10 ether);
        
        // After partial fill
        vm.prank(taker);
        escrow.fillEscrow(escrowId, 3 ether, secret);
        
        assertEq(escrow.getRemainingAmount(escrowId), 7 ether);
        
        // After completion
        vm.prank(taker);
        escrow.fillEscrow(escrowId, 7 ether, secret);
        
        assertEq(escrow.getRemainingAmount(escrowId), 0);
    }

    function testRefundPartiallyFilledEscrow() public {
        // Create an escrow
        vm.prank(maker);
        weth.approve(address(escrow), 10 ether);
        
        vm.prank(maker);
        escrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            10 ether
        );
        
        // Partially fill
        vm.prank(taker);
        escrow.fillEscrow(escrowId, 3 ether, secret);
        
        // Fast forward past expiry
        vm.warp(timeLock + 1);
        
        uint256 initialBalance = weth.balanceOf(maker);
        
        // Refund should return remaining amount
        vm.prank(maker);
        escrow.refundEscrow(escrowId);
        
        // Verify maker received only the remaining amount
        assertEq(weth.balanceOf(maker), initialBalance + 7 ether);
    }

    function testFuzzPartialFills(uint256 totalAmount, uint8 numFills) public {
        // Bound inputs
        totalAmount = bound(totalAmount, 10, 1000 ether);
        numFills = uint8(bound(numFills, 2, 10));
        
        vm.deal(maker, totalAmount);
        vm.prank(maker);
        weth.deposit{value: totalAmount}();
        
        // Create escrow
        vm.prank(maker);
        weth.approve(address(escrow), totalAmount);
        
        vm.prank(maker);
        bytes32 fuzzEscrowId = escrow.createEscrow(
            hashLock,
            timeLock,
            payable(address(0)), // Open fills
            suiOrderHash,
            totalAmount
        );
        
        uint256 fillAmount = totalAmount / numFills;
        uint256 remainingAfterFills = totalAmount - (fillAmount * numFills);
        
        // Make partial fills
        for (uint8 i = 0; i < numFills; i++) {
            address currentResolver = address(uint160(0x1000 + i));
            vm.deal(currentResolver, 1 ether);
            vm.prank(currentResolver);
            weth.deposit{value: 1 ether}();
            
            vm.prank(currentResolver);
            escrow.fillEscrow(fuzzEscrowId, fillAmount, secret);
            
            assertEq(escrow.getRemainingAmount(fuzzEscrowId), totalAmount - (fillAmount * (i + 1)));
        }
        
        // Complete with any remaining amount
        if (remainingAfterFills > 0) {
            vm.prank(resolver1);
            escrow.fillEscrow(fuzzEscrowId, remainingAfterFills, secret);
        }
        
        // Verify completion
        assertEq(escrow.getRemainingAmount(fuzzEscrowId), 0);
        (,,,,,, bool completed,,,) = escrow.getEscrow(fuzzEscrowId);
        assertTrue(completed);
    }

    function testInsufficientWethAllowance() public {
        vm.startPrank(maker);
        
        // Don't approve WETH
        vm.expectRevert(IEthereumEscrow.InsufficientWethAllowance.selector);
        escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            amount
        );
        
        vm.stopPrank();
    }

    function testInsufficientWethBalance() public {
        vm.startPrank(maker);
        
        // Approve more than balance
        weth.approve(address(escrow), 1000 ether);
        
        vm.expectRevert(); // Should revert due to insufficient balance
        escrow.createEscrow(
            hashLock,
            timeLock,
            payable(taker),
            suiOrderHash,
            1000 ether
        );
        
        vm.stopPrank();
    }
}