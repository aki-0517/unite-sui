// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILimitOrderProtocol} from "./ILimitOrderProtocol.sol";

/**
 * @title ICrossChainOrder
 * @dev Interface for cross-chain order integration with HTLC escrow
 */
interface ICrossChainOrder {
    enum CrossChainOrderStatus {
        Active,
        Completed,
        Cancelled,
        Refunded
    }

    struct CrossChainOrderData {
        bytes32 orderHash;
        bytes32 escrowId;
        address maker;
        uint256 sourceAmount;
        uint256 destinationAmount;
        bytes32 hashLock;
        uint256 timeLock;
        string suiOrderHash;
        CrossChainOrderStatus status;
        uint256 createdAt;
        uint256 completedAt;
    }

    // Events
    event CrossChainOrderCreated(
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address indexed maker,
        uint256 sourceAmount,
        uint256 destinationAmount,
        bytes32 hashLock,
        uint256 timeLock,
        string suiOrderHash
    );

    event CrossChainOrderFilled(
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address indexed resolver,
        uint256 fillAmount,
        bytes32 secret,
        uint256 currentRate
    );

    event CrossChainOrderCompleted(
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address indexed resolver,
        bytes32 secret
    );

    event CrossChainOrderCancelled(
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address indexed maker
    );

    event CrossChainOrderRefunded(
        bytes32 indexed orderHash,
        bytes32 indexed escrowId,
        address indexed maker
    );

    // Errors
    error OrderNotFound();
    error OrderNotActive();
    error OrderExpired();
    error OrderNotExpired();
    error InvalidSecret();
    error OnlyMaker();
    error UnauthorizedResolver();
    error EscrowNotFound();
    error AuctionNotStarted();
    error InsufficientAllowance();

    // Core functions
    function createCrossChainOrderWithEscrow(
        uint256 sourceAmount,
        uint256 destinationAmount,
        ILimitOrderProtocol.DutchAuctionConfig calldata auctionConfig,
        bytes32 hashLock,
        uint256 timeLock,
        string calldata suiOrderHash
    ) external returns (bytes32 orderHash, bytes32 escrowId);

    function fillCrossChainOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external;

    function completeCrossChainOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external;

    function cancelCrossChainOrder(bytes32 orderHash) external;

    function emergencyRefund(bytes32 orderHash) external;

    // View functions
    function getCrossChainOrder(bytes32 orderHash) external view returns (
        bytes32 orderHashReturn,
        bytes32 escrowId,
        address maker,
        uint256 sourceAmount,
        uint256 destinationAmount,
        bytes32 hashLock,
        uint256 timeLock,
        string memory suiOrderHash,
        CrossChainOrderStatus status,
        uint256 createdAt,
        uint256 completedAt
    );

    function getEscrowForOrder(bytes32 orderHash) external view returns (bytes32);
    function getOrderForEscrow(bytes32 escrowId) external view returns (bytes32);
    function canFillCrossChainOrder(bytes32 orderHash, address resolver) external view returns (bool);
    function getCurrentRate(bytes32 orderHash) external view returns (uint256);
    function isOrderExpired(bytes32 orderHash) external view returns (bool);
    function getOrderStatus(bytes32 orderHash) external view returns (CrossChainOrderStatus);
}