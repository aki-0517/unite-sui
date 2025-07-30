// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILimitOrderProtocol
 * @dev Interface for 1inch Fusion+ Limit Order Protocol
 */
interface ILimitOrderProtocol {
    struct DutchAuctionConfig {
        uint256 auctionStartTime;
        uint256 auctionEndTime;
        uint256 startRate;
        uint256 endRate;
        uint256 decreaseRate;
    }

    struct LimitOrder {
        address maker;
        address taker;
        uint256 sourceAmount;
        uint256 destinationAmount;
        uint256 deadline;
        bytes32 orderHash;
        bool isActive;
        DutchAuctionConfig auctionConfig;
        uint256 filledAmount;
        bytes32 escrowId;
        uint256 createdAt;
    }

    // Events
    event OrderCreated(
        bytes32 indexed orderHash,
        address indexed maker,
        uint256 sourceAmount,
        uint256 destinationAmount,
        uint256 auctionStartTime,
        uint256 auctionEndTime
    );

    event OrderPartiallyFilled(
        bytes32 indexed orderHash,
        address indexed resolver,
        uint256 fillAmount,
        uint256 totalFilled,
        uint256 currentRate
    );

    event OrderCompleted(
        bytes32 indexed orderHash,
        address indexed resolver,
        uint256 totalFilled,
        uint256 finalRate
    );

    event OrderCancelled(
        bytes32 indexed orderHash,
        address indexed maker,
        uint256 refundAmount
    );

    event EscrowCreated(
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        bytes32 hashLock,
        uint256 timeLock,
        uint256 amount
    );

    // Errors
    error InvalidSourceAmount();
    error InvalidDestinationAmount();
    error InvalidAuctionTimes();
    error AuctionTooShort();
    error AuctionTooLong();
    error InvalidRates();
    error InsufficientAllowance();
    error OrderAlreadyExists();
    error OrderNotFound();
    error OrderNotActive();
    error OrderExpired();
    error OrderAlreadyCancelled();
    error OnlyMaker();
    error UnauthorizedResolver();
    error AuctionNotStarted();
    error InvalidFillAmount();
    error EscrowAlreadyExists();

    // Core functions
    function createCrossChainOrder(
        uint256 sourceAmount,
        uint256 destinationAmount,
        DutchAuctionConfig calldata auctionConfig
    ) external returns (bytes32 orderHash);

    function createEscrowForOrder(
        bytes32 orderHash,
        bytes32 hashLock,
        uint256 timeLock
    ) external returns (bytes32 escrowId);

    function fillLimitOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external;

    function cancelOrder(bytes32 orderHash) external;

    // View functions
    function getOrder(bytes32 orderHash) external view returns (
        address maker,
        address taker,
        uint256 sourceAmount,
        uint256 destinationAmount,
        uint256 deadline,
        bool isActive,
        DutchAuctionConfig memory auctionConfig,
        uint256 filledAmount,
        bytes32 escrowId,
        uint256 createdAt
    );

    function getCurrentRate(bytes32 orderHash) external view returns (uint256);
    function canFillOrder(bytes32 orderHash, address resolver) external view returns (bool);
    function getRemainingAmount(bytes32 orderHash) external view returns (uint256);
}