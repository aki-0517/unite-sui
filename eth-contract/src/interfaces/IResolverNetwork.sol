// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IResolverNetwork
 * @dev Interface for resolver network in 1inch Fusion+
 */
interface IResolverNetwork {
    struct ResolverInfo {
        address resolver;
        bool isRegistered;
        bool isAuthorized;
        uint256 reputation;
        uint256 totalOrdersFilled;
        uint256 totalVolumeHandled;
        uint256 lastActivityTime;
        uint256 stakedAmount;
        uint256 penalties;
    }

    struct OrderInfo {
        bytes32 orderHash;
        uint256 sourceAmount;
        uint256 destinationAmount;
        bool isRegistered;
        bool isActive;
        address bestBidder;
        uint256 bestBidPrice;
        uint256 registeredAt;
    }

    // Events
    event ResolverRegistered(address indexed resolver, uint256 stakedAmount);
    event ResolverUnregistered(address indexed resolver, uint256 returnedStake);
    event ResolverPenalized(address indexed resolver, uint256 penaltyAmount);
    event ResolverAuthorizationChanged(address indexed resolver, bool authorized);
    
    event OrderRegistered(bytes32 indexed orderHash, uint256 sourceAmount, uint256 destinationAmount);
    event OrderUnregistered(bytes32 indexed orderHash);
    event BidPlaced(bytes32 indexed orderHash, address indexed resolver, uint256 bidAmount);
    event OrderFilled(bytes32 indexed orderHash, address indexed resolver, uint256 fillAmount, uint256 currentRate);
    
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    // Errors
    error OnlyLimitOrderProtocol();
    error OnlyAdmin();
    error ResolverAlreadyRegistered();
    error ResolverNotRegistered();
    error ResolverNotAuthorized();
    error InsufficientStake();
    error OrderAlreadyRegistered();
    error OrderNotRegistered();
    error OrderNotActive();
    error InvalidBidAmount();
    error InvalidAddress();

    // Core functions
    function registerResolver() external;
    function unregisterResolver() external;
    
    function registerOrder(
        bytes32 orderHash,
        uint256 sourceAmount,
        uint256 destinationAmount
    ) external;
    
    function unregisterOrder(bytes32 orderHash) external;
    
    function bidOnOrder(bytes32 orderHash, uint256 bidAmount) external;
    
    function recordOrderFill(
        bytes32 orderHash,
        address resolver,
        uint256 fillAmount,
        uint256 currentRate
    ) external;

    // View functions
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
    );

    function getOrder(bytes32 orderHash) external view returns (
        bytes32 orderHashReturn,
        uint256 sourceAmount,
        uint256 destinationAmount,
        bool isRegistered,
        bool isActive,
        address bestBidder,
        uint256 bestBidPrice,
        uint256 registeredAt
    );

    function getBid(bytes32 orderHash, address resolver) external view returns (uint256);
    function getOrderResolvers(bytes32 orderHash) external view returns (address[] memory);
    function isAuthorizedResolver(address resolver) external view returns (bool);
    function getResolverReputation(address resolver) external view returns (uint256);

    // Admin functions
    function penalizeResolver(address resolver, uint256 penaltyAmount) external;
    function setResolverAuthorization(address resolver, bool authorized) external;
    function changeAdmin(address newAdmin) external;
    function emergencyPause() external;
}