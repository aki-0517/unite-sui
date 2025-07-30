// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICrossChainOrder} from "../interfaces/ICrossChainOrder.sol";
import {ILimitOrderProtocol} from "../interfaces/ILimitOrderProtocol.sol";
import {IEthereumEscrow} from "../interfaces/IEthereumEscrow.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {IResolverNetwork} from "../interfaces/IResolverNetwork.sol";
import {HashLock} from "../utils/HashLock.sol";
import {TimeLock} from "../utils/TimeLock.sol";

/**
 * @title CrossChainOrder
 * @dev Integrates Limit Order Protocol with HTLC escrow for cross-chain atomic swaps
 * Combines 1inch Fusion+ limit orders with secure cross-chain execution
 */
contract CrossChainOrder is ReentrancyGuard, ICrossChainOrder {
    using SafeERC20 for IERC20;

    // State variables
    mapping(bytes32 => CrossChainOrderData) public crossChainOrders;
    mapping(bytes32 => bytes32) public orderToEscrow; // orderHash => escrowId
    mapping(bytes32 => bytes32) public escrowToOrder; // escrowId => orderHash

    // Contract dependencies
    ILimitOrderProtocol public immutable limitOrderProtocol;
    IEthereumEscrow public immutable escrowContract;
    IDutchAuction public immutable dutchAuction;
    IResolverNetwork public immutable resolverNetwork;
    IERC20 public immutable weth;

    constructor(
        address _limitOrderProtocol,
        address _escrowContract,
        address _dutchAuction,
        address _resolverNetwork,
        address _weth
    ) {
        limitOrderProtocol = ILimitOrderProtocol(_limitOrderProtocol);
        escrowContract = IEthereumEscrow(_escrowContract);
        dutchAuction = IDutchAuction(_dutchAuction);
        resolverNetwork = IResolverNetwork(_resolverNetwork);
        weth = IERC20(_weth);
    }

    /**
     * @dev Creates a cross-chain order with integrated HTLC escrow
     */
    function createCrossChainOrderWithEscrow(
        uint256 sourceAmount,
        uint256 destinationAmount,
        ILimitOrderProtocol.DutchAuctionConfig calldata auctionConfig,
        bytes32 hashLock,
        uint256 timeLock,
        string calldata suiOrderHash
    ) external nonReentrant returns (bytes32 orderHash, bytes32 escrowId) {
        // Check WETH allowance from user
        if (weth.allowance(msg.sender, address(this)) < sourceAmount * 2) {
            revert InsufficientAllowance();
        }
        
        // Transfer WETH from user to this contract
        weth.safeTransferFrom(msg.sender, address(this), sourceAmount * 2);
        
        // Approve LimitOrderProtocol to spend WETH
        weth.safeApprove(address(limitOrderProtocol), sourceAmount);
        
        // Create the limit order
        orderHash = limitOrderProtocol.createCrossChainOrder(
            sourceAmount,
            destinationAmount,
            auctionConfig
        );

        // Approve escrow contract to spend WETH
        weth.safeApprove(address(escrowContract), sourceAmount);
        
        // Create the HTLC escrow
        escrowId = escrowContract.createEscrow(
            hashLock,
            timeLock,
            payable(address(0)), // Open to any resolver
            suiOrderHash,
            sourceAmount
        );

        // Create cross-chain order data
        crossChainOrders[orderHash] = CrossChainOrderData({
            orderHash: orderHash,
            escrowId: escrowId,
            maker: msg.sender,
            sourceAmount: sourceAmount,
            destinationAmount: destinationAmount,
            hashLock: hashLock,
            timeLock: timeLock,
            suiOrderHash: suiOrderHash,
            status: CrossChainOrderStatus.Active,
            createdAt: block.timestamp,
            completedAt: 0
        });

        // Link order and escrow
        orderToEscrow[orderHash] = escrowId;
        escrowToOrder[escrowId] = orderHash;

        emit CrossChainOrderCreated(
            orderHash,
            escrowId,
            msg.sender,
            sourceAmount,
            destinationAmount,
            hashLock,
            timeLock,
            suiOrderHash
        );
    }

    /**
     * @dev Fills a cross-chain order using the secret
     */
    function fillCrossChainOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external nonReentrant {
        CrossChainOrderData storage order = crossChainOrders[orderHash];
        
        if (order.orderHash == bytes32(0)) revert OrderNotFound();
        if (order.status != CrossChainOrderStatus.Active) revert OrderNotActive();
        if (TimeLock.isExpired(order.timeLock)) revert OrderExpired();

        // Verify secret matches hash lock
        if (!HashLock.verifySecret(secret, order.hashLock)) revert InvalidSecret();

        // Check if resolver is authorized
        if (!resolverNetwork.isAuthorizedResolver(msg.sender)) revert UnauthorizedResolver();

        bytes32 escrowId = orderToEscrow[orderHash];
        if (escrowId == bytes32(0)) revert EscrowNotFound();

        // Get current auction rate to determine fill amount
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        if (currentRate == 0) revert AuctionNotStarted();

        // Calculate fill amount based on current rate
        uint256 fillAmount = (order.sourceAmount * currentRate) / 1e18;
        
        // Fill the escrow with the secret
        escrowContract.fillEscrow(escrowId, fillAmount, secret);

        // Update order status
        order.status = CrossChainOrderStatus.Completed;
        order.completedAt = block.timestamp;

        emit CrossChainOrderFilled(
            orderHash,
            escrowId,
            msg.sender,
            fillAmount,
            secret,
            currentRate
        );
    }

    /**
     * @dev Completes a cross-chain order by revealing the full secret
     */
    function completeCrossChainOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external nonReentrant {
        CrossChainOrderData storage order = crossChainOrders[orderHash];
        
        if (order.orderHash == bytes32(0)) revert OrderNotFound();
        if (order.status != CrossChainOrderStatus.Active) revert OrderNotActive();
        if (TimeLock.isExpired(order.timeLock)) revert OrderExpired();

        // Verify secret matches hash lock
        if (!HashLock.verifySecret(secret, order.hashLock)) revert InvalidSecret();

        // Check if resolver is authorized
        if (!resolverNetwork.isAuthorizedResolver(msg.sender)) revert UnauthorizedResolver();

        bytes32 escrowId = orderToEscrow[orderHash];
        if (escrowId == bytes32(0)) revert EscrowNotFound();

        // Complete the escrow
        escrowContract.completeEscrow(escrowId, secret);

        // Update order status
        order.status = CrossChainOrderStatus.Completed;
        order.completedAt = block.timestamp;

        emit CrossChainOrderCompleted(
            orderHash,
            escrowId,
            msg.sender,
            secret
        );
    }

    /**
     * @dev Cancels a cross-chain order and refunds the maker
     */
    function cancelCrossChainOrder(bytes32 orderHash) external nonReentrant {
        CrossChainOrderData storage order = crossChainOrders[orderHash];
        
        if (order.orderHash == bytes32(0)) revert OrderNotFound();
        if (msg.sender != order.maker) revert OnlyMaker();
        if (order.status != CrossChainOrderStatus.Active) revert OrderNotActive();

        bytes32 escrowId = orderToEscrow[orderHash];
        
        // Try to cancel the limit order first
        try limitOrderProtocol.cancelOrder(orderHash) {} catch {}

        // Refund the escrow if expired
        if (TimeLock.isExpired(order.timeLock)) {
            escrowContract.refundEscrow(escrowId);
        }

        // Update order status
        order.status = CrossChainOrderStatus.Cancelled;

        emit CrossChainOrderCancelled(orderHash, escrowId, order.maker);
    }

    /**
     * @dev Gets cross-chain order information
     */
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
    ) {
        CrossChainOrderData memory order = crossChainOrders[orderHash];
        return (
            order.orderHash,
            order.escrowId,
            order.maker,
            order.sourceAmount,
            order.destinationAmount,
            order.hashLock,
            order.timeLock,
            order.suiOrderHash,
            order.status,
            order.createdAt,
            order.completedAt
        );
    }

    /**
     * @dev Gets escrow ID for an order
     */
    function getEscrowForOrder(bytes32 orderHash) external view returns (bytes32) {
        return orderToEscrow[orderHash];
    }

    /**
     * @dev Gets order hash for an escrow
     */
    function getOrderForEscrow(bytes32 escrowId) external view returns (bytes32) {
        return escrowToOrder[escrowId];
    }

    /**
     * @dev Checks if a cross-chain order can be filled
     */
    function canFillCrossChainOrder(bytes32 orderHash, address resolver) external view returns (bool) {
        CrossChainOrderData memory order = crossChainOrders[orderHash];
        
        return order.orderHash != bytes32(0) &&
               order.status == CrossChainOrderStatus.Active &&
               !TimeLock.isExpired(order.timeLock) &&
               resolverNetwork.isAuthorizedResolver(resolver) &&
               dutchAuction.calculateCurrentRate(orderHash) > 0;
    }

    /**
     * @dev Gets current auction rate for a cross-chain order
     */
    function getCurrentRate(bytes32 orderHash) external view returns (uint256) {
        if (crossChainOrders[orderHash].orderHash == bytes32(0)) return 0;
        return dutchAuction.calculateCurrentRate(orderHash);
    }

    /**
     * @dev Checks if order is expired
     */
    function isOrderExpired(bytes32 orderHash) external view returns (bool) {
        CrossChainOrderData memory order = crossChainOrders[orderHash];
        return TimeLock.isExpired(order.timeLock);
    }

    /**
     * @dev Gets order status
     */
    function getOrderStatus(bytes32 orderHash) external view returns (CrossChainOrderStatus) {
        return crossChainOrders[orderHash].status;
    }

    /**
     * @dev Emergency function to handle stuck orders
     */
    function emergencyRefund(bytes32 orderHash) external nonReentrant {
        CrossChainOrderData storage order = crossChainOrders[orderHash];
        
        if (order.orderHash == bytes32(0)) revert OrderNotFound();
        if (msg.sender != order.maker) revert OnlyMaker();
        if (order.status != CrossChainOrderStatus.Active) revert OrderNotActive();
        if (!TimeLock.isExpired(order.timeLock)) revert OrderNotExpired();

        bytes32 escrowId = orderToEscrow[orderHash];
        
        // Emergency refund from escrow
        escrowContract.refundEscrow(escrowId);
        
        // Update status
        order.status = CrossChainOrderStatus.Refunded;

        emit CrossChainOrderRefunded(orderHash, escrowId, order.maker);
    }
}