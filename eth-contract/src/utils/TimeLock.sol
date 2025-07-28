// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TimeLock
 * @dev Utility library for time lock functionality
 */
library TimeLock {
    /**
     * @dev Checks if the time lock has expired
     * @param timeLock The time lock timestamp
     * @return bool True if expired
     */
    function isExpired(uint256 timeLock) internal view returns (bool) {
        return block.timestamp > timeLock;
    }

    /**
     * @dev Checks if the time lock is valid (future time)
     * @param timeLock The time lock timestamp
     * @return bool True if valid
     */
    function isValidTimeLock(uint256 timeLock) internal view returns (bool) {
        return timeLock > block.timestamp;
    }

    /**
     * @dev Gets the remaining time until expiration
     * @param timeLock The time lock timestamp
     * @return uint256 Remaining time in seconds (0 if expired)
     */
    function getRemainingTime(uint256 timeLock) internal view returns (uint256) {
        if (block.timestamp >= timeLock) {
            return 0;
        }
        return timeLock - block.timestamp;
    }

    /**
     * @dev Creates a time lock for a specific duration from now
     * @param duration Duration in seconds
     * @return uint256 The time lock timestamp
     */
    function createTimeLock(uint256 duration) internal view returns (uint256) {
        return block.timestamp + duration;
    }

    /**
     * @dev Standard time lock duration (1 hour)
     * @return uint256 Duration in seconds
     */
    function standardDuration() internal pure returns (uint256) {
        return 3600; // 1 hour
    }
}