// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILimitOrderProtocol} from "./ILimitOrderProtocol.sol";

/**
 * @title IDutchAuction
 * @dev Interface for Dutch auction mechanism in 1inch Fusion+
 */
interface IDutchAuction {
    struct AuctionData {
        bytes32 orderHash;
        uint256 startTime;
        uint256 endTime;
        uint256 startRate;
        uint256 endRate;
        uint256 decreaseRate;
        bool isActive;
    }

    // Events
    event AuctionInitialized(
        bytes32 indexed orderHash,
        uint256 startTime,
        uint256 endTime,
        uint256 startRate,
        uint256 endRate,
        uint256 decreaseRate
    );

    event AuctionCancelled(bytes32 indexed orderHash);

    // Errors
    error OnlyLimitOrderProtocol();
    error AuctionAlreadyExists();
    error AuctionNotFound();
    error AuctionNotActive();
    error AuctionAlreadyCancelled();
    error InvalidAuctionTimes();
    error InvalidRates();
    error InvalidRateProgression();

    // Core functions
    function initializeAuction(
        bytes32 orderHash,
        ILimitOrderProtocol.DutchAuctionConfig calldata config
    ) external;

    function cancelAuction(bytes32 orderHash) external;

    function calculateCurrentRate(bytes32 orderHash) external view returns (uint256);

    function calculateRateAtTime(
        bytes32 orderHash,
        uint256 timestamp
    ) external view returns (uint256);

    function isProfitableForResolver(
        bytes32 orderHash,
        uint256 resolverCost
    ) external view returns (bool);

    // View functions
    function getAuction(bytes32 orderHash) external view returns (
        bytes32 orderHashReturn,
        uint256 startTime,
        uint256 endTime,
        uint256 startRate,
        uint256 endRate,
        uint256 decreaseRate,
        bool isActive
    );

    function getRemainingTime(bytes32 orderHash) external view returns (uint256);
    function getElapsedTime(bytes32 orderHash) external view returns (uint256);
    function isAuctionActive(bytes32 orderHash) external view returns (bool);
    function hasAuctionStarted(bytes32 orderHash) external view returns (bool);
    function hasAuctionEnded(bytes32 orderHash) external view returns (bool);

    function getRateProgression(bytes32 orderHash, uint256 steps) external view returns (
        uint256[] memory timestamps,
        uint256[] memory rates
    );
}