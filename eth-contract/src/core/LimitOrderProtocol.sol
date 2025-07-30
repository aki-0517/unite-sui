// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ILimitOrderProtocol} from "../interfaces/ILimitOrderProtocol.sol";
import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {IResolverNetwork} from "../interfaces/IResolverNetwork.sol";
import {IEthereumEscrow} from "../interfaces/IEthereumEscrow.sol";
import {HashLock} from "../utils/HashLock.sol";
import {TimeLock} from "../utils/TimeLock.sol";

/**
 * @title LimitOrderProtocol
 * @dev 1inch Fusion+ Limit Order Protocol implementation
 * Integrates Dutch Auction and Resolver Network for competitive price discovery
 * Works with existing HTLC escrow system for cross-chain atomic swaps
 */
contract LimitOrderProtocol is ReentrancyGuard, ILimitOrderProtocol {
    using SafeERC20 for IERC20;

    // State variables
    mapping(bytes32 => LimitOrder) public orders;
    mapping(bytes32 => bool) public cancelledOrders;
    mapping(address => uint256) public nonces;

    // Contract dependencies
    IERC20 public immutable weth;
    IDutchAuction public dutchAuction;
    IResolverNetwork public resolverNetwork;
    IEthereumEscrow public escrowContract;

    // Constants
    uint256 public constant MIN_AUCTION_DURATION = 300; // 5 minutes
    uint256 public constant MAX_AUCTION_DURATION = 86400; // 24 hours
    uint256 public constant MIN_ORDER_AMOUNT = 1e15; // 0.001 WETH minimum

    constructor(
        address _weth,
        address _dutchAuction,
        address _resolverNetwork,
        address _escrowContract
    ) {
        weth = IERC20(_weth);
        dutchAuction = IDutchAuction(_dutchAuction);
        resolverNetwork = IResolverNetwork(_resolverNetwork);
        escrowContract = IEthereumEscrow(_escrowContract);
    }

    /**
     * @dev Creates a cross-chain limit order with Dutch auction
     */
    function createCrossChainOrder(
        uint256 sourceAmount,
        uint256 destinationAmount,
        DutchAuctionConfig calldata auctionConfig
    ) external nonReentrant returns (bytes32 orderHash) {
        if (sourceAmount < MIN_ORDER_AMOUNT) revert InvalidSourceAmount();
        if (destinationAmount == 0) revert InvalidDestinationAmount();
        if (auctionConfig.auctionEndTime <= auctionConfig.auctionStartTime) revert InvalidAuctionTimes();
        if (auctionConfig.auctionEndTime - auctionConfig.auctionStartTime < MIN_AUCTION_DURATION) revert AuctionTooShort();
        if (auctionConfig.auctionEndTime - auctionConfig.auctionStartTime > MAX_AUCTION_DURATION) revert AuctionTooLong();
        if (auctionConfig.startRate == 0 || auctionConfig.endRate == 0) revert InvalidRates();

        // Check WETH allowance
        if (weth.allowance(msg.sender, address(this)) < sourceAmount) {
            revert InsufficientAllowance();
        }

        // Generate order hash
        orderHash = keccak256(
            abi.encodePacked(
                msg.sender,
                sourceAmount,
                destinationAmount,
                auctionConfig.auctionStartTime,
                auctionConfig.auctionEndTime,
                auctionConfig.startRate,
                auctionConfig.endRate,
                nonces[msg.sender]++,
                block.timestamp,
                block.chainid
            )
        );

        if (orders[orderHash].maker != address(0)) revert OrderAlreadyExists();

        // Transfer WETH to contract
        weth.safeTransferFrom(msg.sender, address(this), sourceAmount);

        // Create order
        orders[orderHash] = LimitOrder({
            maker: msg.sender,
            taker: address(0), // Open to any resolver
            sourceAmount: sourceAmount,
            destinationAmount: destinationAmount,
            deadline: auctionConfig.auctionEndTime,
            orderHash: orderHash,
            isActive: true,
            auctionConfig: auctionConfig,
            filledAmount: 0,
            escrowId: bytes32(0),
            createdAt: block.timestamp
        });

        // Initialize Dutch auction
        dutchAuction.initializeAuction(orderHash, auctionConfig);

        // Register with resolver network
        resolverNetwork.registerOrder(orderHash, sourceAmount, destinationAmount);

        emit OrderCreated(
            orderHash,
            msg.sender,
            sourceAmount,
            destinationAmount,
            auctionConfig.auctionStartTime,
            auctionConfig.auctionEndTime
        );
    }

    /**
     * @dev Creates an escrow for a specific order
     */
    function createEscrowForOrder(
        bytes32 orderHash,
        bytes32 hashLock,
        uint256 timeLock
    ) external nonReentrant returns (bytes32 escrowId) {
        LimitOrder storage order = orders[orderHash];
        
        if (order.maker == address(0)) revert OrderNotFound();
        if (msg.sender != order.maker) revert OnlyMaker();
        if (!order.isActive) revert OrderNotActive();
        if (order.escrowId != bytes32(0)) revert EscrowAlreadyExists();
        if (block.timestamp > order.deadline) revert OrderExpired();

        // Approve escrow contract to spend WETH
        weth.safeApprove(address(escrowContract), order.sourceAmount);

        // Create escrow with remaining order amount
        uint256 escrowAmount = order.sourceAmount - order.filledAmount;
        escrowId = escrowContract.createEscrow(
            hashLock,
            timeLock,
            payable(address(0)), // Open to any resolver
            string(abi.encodePacked("order:", _bytes32ToString(orderHash))),
            escrowAmount
        );

        // Update order
        order.escrowId = escrowId;

        emit EscrowCreated(orderHash, escrowId, hashLock, timeLock, escrowAmount);
    }

    /**
     * @dev Fills a limit order (called by resolvers)
     */
    function fillLimitOrder(
        bytes32 orderHash,
        bytes32 secret
    ) external nonReentrant {
        LimitOrder storage order = orders[orderHash];
        
        if (order.maker == address(0)) revert OrderNotFound();
        if (!order.isActive) revert OrderNotActive();
        if (cancelledOrders[orderHash]) revert OrderAlreadyCancelled();
        if (block.timestamp > order.deadline) revert OrderExpired();

        // Check if resolver is authorized
        if (!resolverNetwork.isAuthorizedResolver(msg.sender)) revert UnauthorizedResolver();

        // Get current auction rate
        uint256 currentRate = dutchAuction.calculateCurrentRate(orderHash);
        if (currentRate == 0) revert AuctionNotStarted();

        // Calculate fill amount based on current rate
        uint256 fillAmount = (order.sourceAmount * currentRate) / 1e18;
        if (fillAmount > order.sourceAmount - order.filledAmount) {
            fillAmount = order.sourceAmount - order.filledAmount;
        }

        if (fillAmount == 0) revert InvalidFillAmount();

        // Update order
        order.filledAmount += fillAmount;
        bool isCompleted = order.filledAmount >= order.sourceAmount;

        if (isCompleted) {
            order.isActive = false;
        }

        // If escrow exists, use it for atomic swap
        if (order.escrowId != bytes32(0)) {
            // Fill escrow with secret
            escrowContract.fillEscrow(order.escrowId, fillAmount, secret);
        } else {
            // Direct transfer to resolver
            weth.safeTransfer(msg.sender, fillAmount);
        }

        // Update resolver network
        resolverNetwork.recordOrderFill(orderHash, msg.sender, fillAmount, currentRate);

        if (isCompleted) {
            emit OrderCompleted(orderHash, msg.sender, order.filledAmount, currentRate);
        } else {
            emit OrderPartiallyFilled(orderHash, msg.sender, fillAmount, order.filledAmount, currentRate);
        }
    }

    /**
     * @dev Cancels an active order
     */
    function cancelOrder(bytes32 orderHash) external nonReentrant {
        LimitOrder storage order = orders[orderHash];
        
        if (order.maker == address(0)) revert OrderNotFound();
        if (msg.sender != order.maker) revert OnlyMaker();
        if (!order.isActive) revert OrderNotActive();
        if (cancelledOrders[orderHash]) revert OrderAlreadyCancelled();

        // Mark as cancelled
        cancelledOrders[orderHash] = true;
        order.isActive = false;

        // Refund remaining amount
        uint256 refundAmount = order.sourceAmount - order.filledAmount;
        if (refundAmount > 0) {
            weth.safeTransfer(order.maker, refundAmount);
        }

        // Cancel auction if it exists
        try dutchAuction.cancelAuction(orderHash) {} catch {}

        // Unregister from resolver network
        resolverNetwork.unregisterOrder(orderHash);

        emit OrderCancelled(orderHash, order.maker, refundAmount);
    }

    /**
     * @dev Gets current order information
     */
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
    ) {
        LimitOrder memory order = orders[orderHash];
        return (
            order.maker,
            order.taker,
            order.sourceAmount,
            order.destinationAmount,
            order.deadline,
            order.isActive,
            order.auctionConfig,
            order.filledAmount,
            order.escrowId,
            order.createdAt
        );
    }

    /**
     * @dev Gets current auction rate for an order
     */
    function getCurrentRate(bytes32 orderHash) external view returns (uint256) {
        return dutchAuction.calculateCurrentRate(orderHash);
    }

    /**
     * @dev Checks if an order can be filled by a resolver
     */
    function canFillOrder(bytes32 orderHash, address resolver) external view returns (bool) {
        LimitOrder memory order = orders[orderHash];
        
        return order.maker != address(0) &&
               order.isActive &&
               !cancelledOrders[orderHash] &&
               block.timestamp <= order.deadline &&
               resolverNetwork.isAuthorizedResolver(resolver) &&
               dutchAuction.calculateCurrentRate(orderHash) > 0;
    }

    /**
     * @dev Gets remaining amount that can be filled
     */
    function getRemainingAmount(bytes32 orderHash) external view returns (uint256) {
        LimitOrder memory order = orders[orderHash];
        return order.sourceAmount - order.filledAmount;
    }

    /**
     * @dev Utility function to convert bytes32 to string
     */
    function _bytes32ToString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i*2] = alphabet[uint8(data[i] >> 4)];
            str[1+i*2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyWithdraw(address token, uint256 amount) external {
        // Only allow withdrawal of tokens not involved in active orders
        // This is a simplified version - in production, you'd want more sophisticated checks
        require(msg.sender == address(this), "Unauthorized");
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}