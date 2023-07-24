// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IPriceFeedsAggregator {
    /// @return lastUpdatedAt The latest timestamp the price was updated
    /// @return answer The answer for the priceFeeds
    // Example for ETH-INR priceFeeds, it will return the amount of INR in 1 ETH
    function latestRoundData() external view returns (uint256 lastUpdatedAt, uint256 answer);

    /// @return decimal Returns the decimal for the answer param of latestRoundData
    function decimals() external view returns (uint256 decimal);
}