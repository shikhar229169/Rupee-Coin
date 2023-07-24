// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract MockPriceFeedsAggregator {
    uint256 public decimals;
    uint256 public latestAnswer;
    uint256 public latestTimestamp;

    constructor(uint256 _decimals, uint256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(uint256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
    }

    function updateRoundData(uint256 _answer, uint256 _timestamp) public {
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint256 lastUpdatedAt, uint256 answer)
    {
        return (
            latestTimestamp,
            latestAnswer
        );
    }
}