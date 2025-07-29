// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IEthereumEscrow} from "../interfaces/IEthereumEscrow.sol";
import {HashLock} from "../utils/HashLock.sol";
import {TimeLock} from "../utils/TimeLock.sol";

/**
 * @title EthereumEscrow
 * @dev Cross-chain escrow contract for Ethereum side of atomic swaps
 * Uses Hash-Time Lock Contract (HTLC) pattern for secure atomic swaps
 */
contract EthereumEscrow is ReentrancyGuard, IEthereumEscrow {
    using SafeERC20 for IERC20;
    
    // WETH contract address
    IERC20 public immutable weth;
    
    // Structs
    struct Escrow {
        address payable maker;
        address payable taker; // Optional: can be address(0) for open fills
        uint256 totalAmount;
        uint256 remainingAmount;
        bytes32 hashLock;
        uint256 timeLock;
        bool completed;
        bool refunded;
        uint256 createdAt;
        string suiOrderHash;
        bytes32 secret; // Revealed secret stored after completion
        bool isWeth; // New field to track if this is a WETH escrow
    }

    // State variables
    mapping(bytes32 => Escrow) public escrows;
    mapping(bytes32 => bool) public usedSecrets;
    
    // Constructor
    constructor(address _weth) {
        weth = IERC20(_weth);
    }
    
    // Events and errors are inherited from IEthereumEscrow interface

    /**
     * @dev Creates a new escrow with Hash-Time Lock
     * @param hashLock Hash of the secret (SHA3-256)
     * @param timeLock Unix timestamp when the escrow expires
     * @param taker Address that can claim the escrow
     * @param suiOrderHash Reference to the corresponding Sui order
     * @return escrowId Unique identifier for the escrow
     */
    function createEscrow(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash
    ) external payable nonReentrant returns (bytes32 escrowId) {
        if (msg.value == 0) revert InvalidAmount();
        if (!TimeLock.isValidTimeLock(timeLock)) revert InvalidTimeLock();
        // taker can be address(0) to allow any resolver to fill
        
        // Generate unique escrow ID
        escrowId = keccak256(
            abi.encodePacked(
                msg.sender,
                taker,
                msg.value,
                hashLock,
                timeLock,
                block.timestamp,
                block.number
            )
        );
        
        if (escrows[escrowId].maker != address(0)) revert EscrowAlreadyExists();
        
        escrows[escrowId] = Escrow({
            maker: payable(msg.sender),
            taker: taker,
            totalAmount: msg.value,
            remainingAmount: msg.value,
            hashLock: hashLock,
            timeLock: timeLock,
            completed: false,
            refunded: false,
            createdAt: block.timestamp,
            suiOrderHash: suiOrderHash,
            secret: bytes32(0),
            isWeth: false // ETH escrow
        });
        
        emit EscrowCreated(
            escrowId,
            msg.sender,
            taker,
            msg.value,
            hashLock,
            timeLock,
            suiOrderHash
        );
    }

    /**
     * @dev Creates a new escrow with WETH instead of ETH
     * @param hashLock Hash of the secret (SHA3-256)
     * @param timeLock Unix timestamp when the escrow expires
     * @param taker Address that can claim the escrow
     * @param suiOrderHash Reference to the corresponding Sui order
     * @param wethAmount Amount of WETH to escrow
     * @return escrowId Unique identifier for the escrow
     */
    function createEscrowWithWeth(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash,
        uint256 wethAmount
    ) external nonReentrant returns (bytes32 escrowId) {
        if (wethAmount == 0) revert InvalidWethAmount();
        if (!TimeLock.isValidTimeLock(timeLock)) revert InvalidTimeLock();
        
        // Check WETH allowance
        if (weth.allowance(msg.sender, address(this)) < wethAmount) {
            revert InsufficientWethAllowance();
        }
        
        // Generate unique escrow ID
        escrowId = keccak256(
            abi.encodePacked(
                msg.sender,
                taker,
                wethAmount,
                hashLock,
                timeLock,
                block.timestamp,
                block.number
            )
        );
        
        if (escrows[escrowId].maker != address(0)) revert EscrowAlreadyExists();
        
        // Transfer WETH to contract
        weth.safeTransferFrom(msg.sender, address(this), wethAmount);
        
        escrows[escrowId] = Escrow({
            maker: payable(msg.sender),
            taker: taker,
            totalAmount: wethAmount,
            remainingAmount: wethAmount,
            hashLock: hashLock,
            timeLock: timeLock,
            completed: false,
            refunded: false,
            createdAt: block.timestamp,
            suiOrderHash: suiOrderHash,
            secret: bytes32(0),
            isWeth: true // WETH escrow
        });
        
        emit EscrowCreatedWithWeth(
            escrowId,
            msg.sender,
            taker,
            wethAmount,
            hashLock,
            timeLock,
            suiOrderHash,
            true
        );
    }

    /**
     * @dev Fills the escrow partially with a specific amount
     * @param escrowId The escrow identifier
     * @param amount The amount to fill (must be <= remainingAmount)
     * @param secret The secret that matches the hash lock
     */
    function fillEscrow(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (escrow.taker != address(0) && msg.sender != escrow.taker) revert OnlyTaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (TimeLock.isExpired(escrow.timeLock)) revert EscrowExpired();
        if (amount == 0) revert InvalidFillAmount();
        if (amount > escrow.remainingAmount) revert InsufficientRemainingAmount();
        
        // Verify the secret matches the hash lock
        if (!HashLock.verifySecret(secret, escrow.hashLock)) revert InvalidSecret();
        
        // Check secret usage
        if (escrow.secret == bytes32(0)) {
            // First fill - check if secret was used in other escrows
            if (usedSecrets[secret]) revert SecretAlreadyUsed();
            escrow.secret = secret;
            usedSecrets[secret] = true;
        } else {
            // Subsequent fills - must use same secret as first fill
            if (escrow.secret != secret) revert InvalidSecret();
        }
        
        // Update remaining amount
        escrow.remainingAmount -= amount;
        
        // Check if this completes the escrow
        bool isCompleted = escrow.remainingAmount == 0;
        if (isCompleted) {
            escrow.completed = true;
        }
        
        // Transfer funds to resolver
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        if (isCompleted) {
            emit EscrowCompleted(escrowId, msg.sender, secret, escrow.suiOrderHash);
        } else {
            emit EscrowPartiallyFilled(
                escrowId, 
                msg.sender, 
                amount, 
                escrow.remainingAmount, 
                secret, 
                escrow.suiOrderHash
            );
        }
    }

    /**
     * @dev Fills the WETH escrow partially with a specific amount
     * @param escrowId The escrow identifier
     * @param amount The amount to fill (must be <= remainingAmount)
     * @param secret The secret that matches the hash lock
     */
    function fillEscrowWithWeth(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (!escrow.isWeth) revert InvalidWethAmount(); // Only WETH escrows
        if (escrow.taker != address(0) && msg.sender != escrow.taker) revert OnlyTaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (TimeLock.isExpired(escrow.timeLock)) revert EscrowExpired();
        if (amount == 0) revert InvalidFillAmount();
        if (amount > escrow.remainingAmount) revert InsufficientRemainingAmount();
        
        // Verify the secret matches the hash lock
        if (!HashLock.verifySecret(secret, escrow.hashLock)) revert InvalidSecret();
        
        // Check secret usage
        if (escrow.secret == bytes32(0)) {
            // First fill - check if secret was used in other escrows
            if (usedSecrets[secret]) revert SecretAlreadyUsed();
            escrow.secret = secret;
            usedSecrets[secret] = true;
        } else {
            // Subsequent fills - must use same secret as first fill
            if (escrow.secret != secret) revert InvalidSecret();
        }
        
        // Update remaining amount
        escrow.remainingAmount -= amount;
        
        // Check if this completes the escrow
        bool isCompleted = escrow.remainingAmount == 0;
        if (isCompleted) {
            escrow.completed = true;
        }
        
        // Transfer WETH to resolver
        weth.safeTransfer(msg.sender, amount);
        
        if (isCompleted) {
            emit EscrowCompleted(escrowId, msg.sender, secret, escrow.suiOrderHash);
        } else {
            emit EscrowPartiallyFilled(
                escrowId, 
                msg.sender, 
                amount, 
                escrow.remainingAmount, 
                secret, 
                escrow.suiOrderHash
            );
        }
    }

    /**
     * @dev Completes the escrow by revealing the secret (fills remaining amount)
     * @param escrowId The escrow identifier
     * @param secret The secret that matches the hash lock
     */
    function completeEscrow(
        bytes32 escrowId,
        bytes32 secret
    ) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (escrow.taker != address(0) && msg.sender != escrow.taker) revert OnlyTaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (TimeLock.isExpired(escrow.timeLock)) revert EscrowExpired();
        
        // Verify the secret matches the hash lock
        if (!HashLock.verifySecret(secret, escrow.hashLock)) revert InvalidSecret();
        
        // Check secret usage
        if (escrow.secret == bytes32(0)) {
            // First fill - check if secret was used in other escrows
            if (usedSecrets[secret]) revert SecretAlreadyUsed();
            escrow.secret = secret;
            usedSecrets[secret] = true;
        } else {
            // Must use same secret as previous partial fills
            if (escrow.secret != secret) revert InvalidSecret();
        }
        
        // Complete with remaining amount
        uint256 amount = escrow.remainingAmount;
        
        // Mark as completed and store the secret
        escrow.completed = true;
        escrow.remainingAmount = 0;
        
        // Transfer funds to resolver
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        emit EscrowCompleted(escrowId, msg.sender, secret, escrow.suiOrderHash);
    }

    /**
     * @dev Refunds the escrow after timeout
     * @param escrowId The escrow identifier
     */
    function refundEscrow(bytes32 escrowId) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        
        if (escrow.maker == address(0)) revert EscrowNotFound();
        if (msg.sender != escrow.maker) revert OnlyMaker();
        if (escrow.completed) revert EscrowAlreadyCompleted();
        if (escrow.refunded) revert EscrowAlreadyRefunded();
        if (!TimeLock.isExpired(escrow.timeLock)) revert EscrowNotExpired();
        
        // Mark as refunded
        escrow.refunded = true;
        uint256 amount = escrow.remainingAmount;
        escrow.remainingAmount = 0;
        
        if (escrow.isWeth) {
            // WETH refund
            weth.safeTransfer(escrow.maker, amount);
        } else {
            // ETH refund
            (bool success, ) = escrow.maker.call{value: amount}("");
            if (!success) revert TransferFailed();
        }
        
        emit EscrowRefunded(escrowId, escrow.maker, amount, escrow.suiOrderHash);
    }

    /**
     * @dev Verifies if a secret matches the hash lock
     * @param secret The secret to verify
     * @param hashLock The hash lock to verify against
     * @return bool True if the secret is valid
     */
    function verifySecret(
        bytes32 secret,
        bytes32 hashLock
    ) external pure returns (bool) {
        return HashLock.verifySecret(secret, hashLock);
    }

    /**
     * @dev Creates a hash lock from a secret
     * @param secret The secret to hash
     * @return bytes32 The resulting hash lock
     */
    function createHashLock(bytes32 secret) external pure returns (bytes32) {
        return HashLock.createHashLock(secret);
    }

    /**
     * @dev Gets escrow information
     * @param escrowId The escrow identifier
     * @return maker The maker address
     * @return taker The taker address
     * @return totalAmount The total escrow amount
     * @return remainingAmount The remaining amount to be filled
     * @return hashLock The hash lock
     * @return timeLock The time lock
     * @return completed Whether the escrow is completed
     * @return refunded Whether the escrow is refunded
     * @return createdAt The creation timestamp
     * @return suiOrderHash The Sui order hash
     */
    function getEscrow(bytes32 escrowId) external view returns (
        address maker,
        address taker,
        uint256 totalAmount,
        uint256 remainingAmount,
        bytes32 hashLock,
        uint256 timeLock,
        bool completed,
        bool refunded,
        uint256 createdAt,
        string memory suiOrderHash
    ) {
        Escrow memory escrow = escrows[escrowId];
        return (
            escrow.maker,
            escrow.taker,
            escrow.totalAmount,
            escrow.remainingAmount,
            escrow.hashLock,
            escrow.timeLock,
            escrow.completed,
            escrow.refunded,
            escrow.createdAt,
            escrow.suiOrderHash
        );
    }

    /**
     * @dev Gets escrow information with WETH support
     * @param escrowId The escrow identifier
     */
    function getEscrowWithWethInfo(bytes32 escrowId) external view returns (
        address maker,
        address taker,
        uint256 totalAmount,
        uint256 remainingAmount,
        bytes32 hashLock,
        uint256 timeLock,
        bool completed,
        bool refunded,
        uint256 createdAt,
        string memory suiOrderHash,
        bool isWeth
    ) {
        Escrow memory escrow = escrows[escrowId];
        return (
            escrow.maker,
            escrow.taker,
            escrow.totalAmount,
            escrow.remainingAmount,
            escrow.hashLock,
            escrow.timeLock,
            escrow.completed,
            escrow.refunded,
            escrow.createdAt,
            escrow.suiOrderHash,
            escrow.isWeth
        );
    }

    /**
     * @dev Gets the remaining amount to be filled for an escrow
     * @param escrowId The escrow identifier
     * @return uint256 The remaining amount
     */
    function getRemainingAmount(bytes32 escrowId) external view returns (uint256) {
        return escrows[escrowId].remainingAmount;
    }

    /**
     * @dev Checks if an escrow is expired
     * @param escrowId The escrow identifier
     * @return bool True if expired
     */
    function isExpired(bytes32 escrowId) external view returns (bool) {
        return TimeLock.isExpired(escrows[escrowId].timeLock);
    }

    /**
     * @dev Checks if an escrow can be completed
     * @param escrowId The escrow identifier
     * @return bool True if can be completed
     */
    function canComplete(bytes32 escrowId) external view returns (bool) {
        Escrow memory escrow = escrows[escrowId];
        return !escrow.completed && 
               !escrow.refunded && 
               !TimeLock.isExpired(escrow.timeLock);
    }

    /**
     * @dev Gets the revealed secret from a completed escrow
     * @param escrowId The escrow identifier
     * @return bytes32 The revealed secret
     */
    function getSecret(bytes32 escrowId) external view returns (bytes32) {
        return escrows[escrowId].secret;
    }

    /**
     * @dev Emergency function to check contract balance
     * @return uint256 Contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}