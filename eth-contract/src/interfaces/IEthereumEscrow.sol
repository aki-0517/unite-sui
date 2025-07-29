// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title IEthereumEscrow
 * @dev Interface for Ethereum escrow contract used in cross-chain atomic swaps
 */
interface IEthereumEscrow {
    // Events
    event EscrowCreated(
        bytes32 indexed escrowId,
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bytes32 hashLock,
        uint256 timeLock,
        string suiOrderHash
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
    
    event EscrowCreatedWithWeth(
        bytes32 indexed escrowId,
        address indexed maker,
        address indexed taker,
        uint256 amount,
        bytes32 hashLock,
        uint256 timeLock,
        string suiOrderHash,
        bool isWeth
    );
    
    event EscrowRefunded(
        bytes32 indexed escrowId,
        address indexed maker,
        uint256 amount,
        string suiOrderHash
    );

    // Custom errors
    error InvalidTimeLock();
    error InvalidAmount();
    error InvalidTaker();
    error EscrowAlreadyExists();
    error EscrowNotFound();
    error EscrowAlreadyCompleted();
    error EscrowAlreadyRefunded();
    error EscrowNotExpired();
    error EscrowExpired();
    error InvalidSecret();
    error OnlyMaker();
    error OnlyTaker();
    error InsufficientRemainingAmount();
    error InvalidFillAmount();
    error SecretAlreadyUsed();
    error TransferFailed();
    error InvalidWethAmount();
    error WethTransferFailed();
    error InsufficientWethAllowance();

    // Core functions
    function createEscrow(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash
    ) external payable returns (bytes32 escrowId);

    function fillEscrow(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external;
    
    function createEscrowWithWeth(
        bytes32 hashLock,
        uint256 timeLock,
        address payable taker,
        string calldata suiOrderHash,
        uint256 wethAmount
    ) external returns (bytes32 escrowId);

    function fillEscrowWithWeth(
        bytes32 escrowId,
        uint256 amount,
        bytes32 secret
    ) external;

    function completeEscrow(
        bytes32 escrowId,
        bytes32 secret
    ) external;

    function refundEscrow(bytes32 escrowId) external;

    // Utility functions
    function verifySecret(
        bytes32 secret,
        bytes32 hashLock
    ) external pure returns (bool);

    function createHashLock(bytes32 secret) external pure returns (bytes32);

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
    );

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
    );
    
    function getRemainingAmount(bytes32 escrowId) external view returns (uint256);

    function isExpired(bytes32 escrowId) external view returns (bool);
    function canComplete(bytes32 escrowId) external view returns (bool);
    function getSecret(bytes32 escrowId) external view returns (bytes32);
    function getContractBalance() external view returns (uint256);
}