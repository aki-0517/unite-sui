// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDutchAuction} from "../interfaces/IDutchAuction.sol";
import {ILimitOrderProtocol} from "../interfaces/ILimitOrderProtocol.sol";

/**
 * @title DutchAuction
 * @dev Dutch auction implementation for 1inch Fusion+ Limit Orders
 * Provides competitive price discovery through decreasing rate mechanism
 */
contract DutchAuction is IDutchAuction {
    // State variables
    mapping(bytes32 => AuctionData) public auctions;
    mapping(bytes32 => bool) public cancelledAuctions;

    // Only the LimitOrderProtocol can initialize auctions
    address public immutable limitOrderProtocol;

    constructor(address _limitOrderProtocol) {
        limitOrderProtocol = _limitOrderProtocol;
    }

    modifier onlyLimitOrderProtocol() {
        if (msg.sender != limitOrderProtocol) revert OnlyLimitOrderProtocol();
        _;
    }

    /**
     * @dev Initializes a Dutch auction for an order
     */
    function initializeAuction(
        bytes32 orderHash,
        ILimitOrderProtocol.DutchAuctionConfig calldata config
    ) external onlyLimitOrderProtocol {
        if (auctions[orderHash].startTime != 0) revert AuctionAlreadyExists();
        if (config.auctionStartTime >= config.auctionEndTime) revert InvalidAuctionTimes();
        if (config.startRate == 0 || config.endRate == 0) revert InvalidRates();
        if (config.startRate <= config.endRate) revert InvalidRateProgression();

        // Calculate decrease rate if not provided
        uint256 decreaseRate = config.decreaseRate;
        if (decreaseRate == 0) {
            uint256 duration = config.auctionEndTime - config.auctionStartTime;
            decreaseRate = (config.startRate - config.endRate) / duration;
        }

        auctions[orderHash] = AuctionData({
            orderHash: orderHash,
            startTime: config.auctionStartTime,
            endTime: config.auctionEndTime,
            startRate: config.startRate,
            endRate: config.endRate,
            decreaseRate: decreaseRate,
            isActive: true
        });

        emit AuctionInitialized(
            orderHash,
            config.auctionStartTime,
            config.auctionEndTime,
            config.startRate,
            config.endRate,
            decreaseRate
        );
    }

    /**
     * @dev Cancels an active auction
     */
    function cancelAuction(bytes32 orderHash) external onlyLimitOrderProtocol {
        AuctionData storage auction = auctions[orderHash];
        
        if (auction.startTime == 0) revert AuctionNotFound();
        if (!auction.isActive) revert AuctionNotActive();
        if (cancelledAuctions[orderHash]) revert AuctionAlreadyCancelled();

        auction.isActive = false;
        cancelledAuctions[orderHash] = true;

        emit AuctionCancelled(orderHash);
    }

    /**
     * @dev Calculates the current rate for a Dutch auction
     */
    function calculateCurrentRate(bytes32 orderHash) external view returns (uint256) {
        AuctionData memory auction = auctions[orderHash];
        
        if (auction.startTime == 0) return 0;
        if (!auction.isActive) return 0;
        if (cancelledAuctions[orderHash]) return 0;
        if (block.timestamp < auction.startTime) return 0;
        if (block.timestamp >= auction.endTime) return auction.endRate;

        // Linear decrease from startRate to endRate
        uint256 timeElapsed = block.timestamp - auction.startTime;
        uint256 totalDuration = auction.endTime - auction.startTime;
        
        if (timeElapsed >= totalDuration) {
            return auction.endRate;
        }

        // Calculate current rate using linear interpolation
        uint256 rateDecrease = ((auction.startRate - auction.endRate) * timeElapsed) / totalDuration;
        return auction.startRate - rateDecrease;
    }

    /**
     * @dev Calculates the current rate with a specific timestamp
     */
    function calculateRateAtTime(
        bytes32 orderHash,
        uint256 timestamp
    ) external view returns (uint256) {
        AuctionData memory auction = auctions[orderHash];
        
        if (auction.startTime == 0) return 0;
        if (!auction.isActive) return 0;
        if (cancelledAuctions[orderHash]) return 0;
        if (timestamp < auction.startTime) return 0;
        if (timestamp >= auction.endTime) return auction.endRate;

        // Linear decrease from startRate to endRate
        uint256 timeElapsed = timestamp - auction.startTime;
        uint256 totalDuration = auction.endTime - auction.startTime;
        
        if (timeElapsed >= totalDuration) {
            return auction.endRate;
        }

        // Calumate current rate using linear interpolation
        uint256 rateDecrease = ((auction.startRate - auction.endRate) * timeElapsed) / totalDuration;
        return auction.startRate - rateDecrease;
    }

    /**
     * @dev Checks if filling the order at current rate is profitable for resolver
     */
    function isProfitableForResolver(
        bytes32 orderHash,
        uint256 resolverCost
    ) external view returns (bool) {
        uint256 currentRate = this.calculateCurrentRate(orderHash);
        if (currentRate == 0) return false;

        // Simple profitability check: current rate should cover resolver costs plus minimum profit
        // This is a simplified version - in practice, more sophisticated calculations would be needed
        uint256 minProfitMargin = 1e16; // 1% minimum profit
        return currentRate >= resolverCost + minProfitMargin;
    }

    /**
     * @dev Gets auction information
     */
    function getAuction(bytes32 orderHash) external view returns (
        bytes32 orderHashReturn,
        uint256 startTime,
        uint256 endTime,
        uint256 startRate,
        uint256 endRate,
        uint256 decreaseRate,
        bool isActive
    ) {
        AuctionData memory auction = auctions[orderHash];
        return (
            auction.orderHash,
            auction.startTime,
            auction.endTime,
            auction.startRate,
            auction.endRate,
            auction.decreaseRate,
            auction.isActive
        );
    }

    /**
     * @dev Gets remaining time in auction
     */
    function getRemainingTime(bytes32 orderHash) external view returns (uint256) {
        AuctionData memory auction = auctions[orderHash];
        
        if (auction.startTime == 0) return 0;
        if (!auction.isActive) return 0;
        if (block.timestamp >= auction.endTime) return 0;
        if (block.timestamp < auction.startTime) return auction.endTime - auction.startTime;

        return auction.endTime - block.timestamp;
    }

    /**
     * @dev Gets elapsed time since auction start
     */
    function getElapsedTime(bytes32 orderHash) external view returns (uint256) {
        AuctionData memory auction = auctions[orderHash];
        
        if (auction.startTime == 0) return 0;
        if (block.timestamp < auction.startTime) return 0;

        return block.timestamp - auction.startTime;
    }

    /**
     * @dev Checks if auction is active and running
     */
    function isAuctionActive(bytes32 orderHash) external view returns (bool) {
        AuctionData memory auction = auctions[orderHash];
        
        return auction.startTime != 0 &&
               auction.isActive &&
               !cancelledAuctions[orderHash] &&
               block.timestamp >= auction.startTime &&
               block.timestamp < auction.endTime;
    }

    /**
     * @dev Checks if auction has started
     */
    function hasAuctionStarted(bytes32 orderHash) external view returns (bool) {
        AuctionData memory auction = auctions[orderHash];
        
        return auction.startTime != 0 &&
               auction.isActive &&
               !cancelledAuctions[orderHash] &&
               block.timestamp >= auction.startTime;
    }

    /**
     * @dev Checks if auction has ended
     */
    function hasAuctionEnded(bytes32 orderHash) external view returns (bool) {
        AuctionData memory auction = auctions[orderHash];
        
        return auction.startTime != 0 &&
               block.timestamp >= auction.endTime;
    }

    /**
     * @dev Gets the rate progression curve data
     */
    function getRateProgression(bytes32 orderHash, uint256 steps) external view returns (
        uint256[] memory timestamps,
        uint256[] memory rates
    ) {
        AuctionData memory auction = auctions[orderHash];
        
        if (auction.startTime == 0 || steps == 0) {
            return (new uint256[](0), new uint256[](0));
        }

        timestamps = new uint256[](steps);
        rates = new uint256[](steps);

        uint256 duration = auction.endTime - auction.startTime;
        uint256 stepSize = duration / steps;

        for (uint256 i = 0; i < steps; i++) {
            uint256 timestamp = auction.startTime + (i * stepSize);
            timestamps[i] = timestamp;
            rates[i] = this.calculateRateAtTime(orderHash, timestamp);
        }
    }
}