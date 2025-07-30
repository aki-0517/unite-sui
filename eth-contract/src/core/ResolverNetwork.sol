// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IResolverNetwork} from "../interfaces/IResolverNetwork.sol";

/**
 * @title ResolverNetwork
 * @dev Resolver network for 1inch Fusion+ automated order execution
 * Manages resolver authorization, bidding, and execution coordination
 */
contract ResolverNetwork is ReentrancyGuard, IResolverNetwork {
    using SafeERC20 for IERC20;

    // State variables
    mapping(address => ResolverInfo) public resolvers;
    mapping(bytes32 => OrderInfo) public orders;
    mapping(bytes32 => mapping(address => uint256)) public orderBids;
    mapping(bytes32 => address[]) public orderResolvers;
    mapping(address => uint256) public resolverStakes;

    // Configuration
    address public immutable limitOrderProtocol;
    IERC20 public immutable weth;
    uint256 public constant MIN_STAKE = 1e18; // 1 WETH minimum stake
    uint256 public constant REPUTATION_DECAY_RATE = 99; // 1% decay per period
    uint256 public constant REPUTATION_PERIOD = 86400; // 24 hours

    // Admin
    address public admin;

    modifier onlyLimitOrderProtocol() {
        if (msg.sender != limitOrderProtocol) revert OnlyLimitOrderProtocol();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    constructor(address _limitOrderProtocol, address _weth, address _admin) {
        limitOrderProtocol = _limitOrderProtocol;
        weth = IERC20(_weth);
        admin = _admin;
    }

    /**
     * @dev Registers a resolver with initial stake
     */
    function registerResolver() external nonReentrant {
        if (resolvers[msg.sender].isRegistered) revert ResolverAlreadyRegistered();
        
        // Check minimum stake
        uint256 allowance = weth.allowance(msg.sender, address(this));
        if (allowance < MIN_STAKE) revert InsufficientStake();

        // Transfer stake
        weth.safeTransferFrom(msg.sender, address(this), MIN_STAKE);
        resolverStakes[msg.sender] = MIN_STAKE;

        resolvers[msg.sender] = ResolverInfo({
            resolver: msg.sender,
            isRegistered: true,
            isAuthorized: true,
            reputation: 100, // Start with neutral reputation
            totalOrdersFilled: 0,
            totalVolumeHandled: 0,
            lastActivityTime: block.timestamp,
            stakedAmount: MIN_STAKE,
            penalties: 0
        });

        emit ResolverRegistered(msg.sender, MIN_STAKE);
    }

    /**
     * @dev Unregisters a resolver and returns their stake
     */
    function unregisterResolver() external nonReentrant {
        ResolverInfo storage resolver = resolvers[msg.sender];
        
        if (!resolver.isRegistered) revert ResolverNotRegistered();
        
        uint256 stakeToReturn = resolverStakes[msg.sender];
        
        // Mark as unregistered
        resolver.isRegistered = false;
        resolver.isAuthorized = false;
        resolverStakes[msg.sender] = 0;

        // Return stake
        if (stakeToReturn > 0) {
            weth.safeTransfer(msg.sender, stakeToReturn);
        }

        emit ResolverUnregistered(msg.sender, stakeToReturn);
    }

    /**
     * @dev Registers an order for resolver network
     */
    function registerOrder(
        bytes32 orderHash,
        uint256 sourceAmount,
        uint256 destinationAmount
    ) external onlyLimitOrderProtocol {
        if (orders[orderHash].isRegistered) revert OrderAlreadyRegistered();

        orders[orderHash] = OrderInfo({
            orderHash: orderHash,
            sourceAmount: sourceAmount,
            destinationAmount: destinationAmount,
            isRegistered: true,
            isActive: true,
            bestBidder: address(0),
            bestBidPrice: 0,
            registeredAt: block.timestamp
        });

        emit OrderRegistered(orderHash, sourceAmount, destinationAmount);
    }

    /**
     * @dev Unregisters an order from resolver network
     */
    function unregisterOrder(bytes32 orderHash) external onlyLimitOrderProtocol {
        OrderInfo storage order = orders[orderHash];
        
        if (!order.isRegistered) revert OrderNotRegistered();
        
        order.isActive = false;

        emit OrderUnregistered(orderHash);
    }

    /**
     * @dev Places a bid on an order
     */
    function bidOnOrder(bytes32 orderHash, uint256 bidAmount) external nonReentrant {
        ResolverInfo storage resolver = resolvers[msg.sender];
        OrderInfo storage order = orders[orderHash];

        if (!resolver.isRegistered) revert ResolverNotRegistered();
        if (!resolver.isAuthorized) revert ResolverNotAuthorized();
        if (!order.isRegistered) revert OrderNotRegistered();
        if (!order.isActive) revert OrderNotActive();
        if (bidAmount == 0) revert InvalidBidAmount();

        // Update bid
        orderBids[orderHash][msg.sender] = bidAmount;

        // Track resolver for this order
        bool alreadyTracked = false;
        address[] storage resolverList = orderResolvers[orderHash];
        for (uint256 i = 0; i < resolverList.length; i++) {
            if (resolverList[i] == msg.sender) {
                alreadyTracked = true;
                break;
            }
        }
        if (!alreadyTracked) {
            resolverList.push(msg.sender);
        }

        // Update best bid if this is better
        if (bidAmount > order.bestBidPrice) {
            order.bestBidder = msg.sender;
            order.bestBidPrice = bidAmount;
        }

        emit BidPlaced(orderHash, msg.sender, bidAmount);
    }

    /**
     * @dev Records order fill execution
     */
    function recordOrderFill(
        bytes32 orderHash,
        address resolver,
        uint256 fillAmount,
        uint256 currentRate
    ) external onlyLimitOrderProtocol {
        ResolverInfo storage resolverInfo = resolvers[resolver];
        OrderInfo storage order = orders[orderHash];

        if (!resolverInfo.isRegistered) revert ResolverNotRegistered();
        if (!order.isRegistered) revert OrderNotRegistered();

        // Update resolver stats
        resolverInfo.totalOrdersFilled += 1;
        resolverInfo.totalVolumeHandled += fillAmount;
        resolverInfo.lastActivityTime = block.timestamp;

        // Update reputation based on performance
        _updateResolverReputation(resolver, true);

        emit OrderFilled(orderHash, resolver, fillAmount, currentRate);
    }

    /**
     * @dev Penalizes a resolver for bad behavior
     */
    function penalizeResolver(address resolver, uint256 penaltyAmount) external onlyAdmin {
        ResolverInfo storage resolverInfo = resolvers[resolver];
        
        if (!resolverInfo.isRegistered) revert ResolverNotRegistered();

        resolverInfo.penalties += penaltyAmount;
        resolverInfo.reputation = resolverInfo.reputation > penaltyAmount ? 
            resolverInfo.reputation - penaltyAmount : 0;

        // Deauthorize if too many penalties
        if (resolverInfo.penalties > 50) {
            resolverInfo.isAuthorized = false;
        }

        emit ResolverPenalized(resolver, penaltyAmount);
    }

    /**
     * @dev Gets resolver information
     */
    function getResolver(address resolver) external view returns (
        address resolverAddress,
        bool isRegistered,
        bool isAuthorized,
        uint256 reputation,
        uint256 totalOrdersFilled,
        uint256 totalVolumeHandled,
        uint256 lastActivityTime,
        uint256 stakedAmount,
        uint256 penalties
    ) {
        ResolverInfo memory info = resolvers[resolver];
        return (
            info.resolver,
            info.isRegistered,
            info.isAuthorized,
            info.reputation,
            info.totalOrdersFilled,
            info.totalVolumeHandled,
            info.lastActivityTime,
            info.stakedAmount,
            info.penalties
        );
    }

    /**
     * @dev Gets order information
     */
    function getOrder(bytes32 orderHash) external view returns (
        bytes32 orderHashReturn,
        uint256 sourceAmount,
        uint256 destinationAmount,
        bool isRegistered,
        bool isActive,
        address bestBidder,
        uint256 bestBidPrice,
        uint256 registeredAt
    ) {
        OrderInfo memory order = orders[orderHash];
        return (
            order.orderHash,
            order.sourceAmount,
            order.destinationAmount,
            order.isRegistered,
            order.isActive,
            order.bestBidder,
            order.bestBidPrice,
            order.registeredAt
        );
    }

    /**
     * @dev Gets bid amount for a resolver on an order
     */
    function getBid(bytes32 orderHash, address resolver) external view returns (uint256) {
        return orderBids[orderHash][resolver];
    }

    /**
     * @dev Gets all resolvers bidding on an order
     */
    function getOrderResolvers(bytes32 orderHash) external view returns (address[] memory) {
        return orderResolvers[orderHash];
    }

    /**
     * @dev Checks if a resolver is authorized
     */
    function isAuthorizedResolver(address resolver) external view returns (bool) {
        return resolvers[resolver].isRegistered && resolvers[resolver].isAuthorized;
    }

    /**
     * @dev Gets resolver reputation with decay applied
     */
    function getResolverReputation(address resolver) external view returns (uint256) {
        ResolverInfo memory info = resolvers[resolver];
        
        if (!info.isRegistered) return 0;
        
        // Apply reputation decay based on inactivity
        uint256 timeSinceActivity = block.timestamp - info.lastActivityTime;
        uint256 periods = timeSinceActivity / REPUTATION_PERIOD;
        
        if (periods == 0) return info.reputation;
        
        uint256 decayedReputation = info.reputation;
        for (uint256 i = 0; i < periods && decayedReputation > 0; i++) {
            decayedReputation = (decayedReputation * REPUTATION_DECAY_RATE) / 100;
        }
        
        return decayedReputation;
    }

    /**
     * @dev Internal function to update resolver reputation
     */
    function _updateResolverReputation(address resolver, bool positive) internal {
        ResolverInfo storage info = resolvers[resolver];
        
        if (positive) {
            // Increase reputation for successful fills
            info.reputation = info.reputation < 200 ? info.reputation + 1 : 200;
        } else {
            // Decrease reputation for failures
            info.reputation = info.reputation > 1 ? info.reputation - 1 : 0;
        }
    }

    /**
     * @dev Allows admin to authorize/deauthorize resolvers
     */
    function setResolverAuthorization(address resolver, bool authorized) external onlyAdmin {
        ResolverInfo storage info = resolvers[resolver];
        
        if (!info.isRegistered) revert ResolverNotRegistered();
        
        info.isAuthorized = authorized;
        
        emit ResolverAuthorizationChanged(resolver, authorized);
    }

    /**
     * @dev Changes admin address
     */
    function changeAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert InvalidAddress();
        
        address oldAdmin = admin;
        admin = newAdmin;
        
        emit AdminChanged(oldAdmin, newAdmin);
    }

    /**
     * @dev Emergency function to pause resolver activity
     */
    function emergencyPause() external onlyAdmin {
        // Implementation would depend on specific pause mechanisms needed
        // This is a placeholder for emergency functionality
    }
}