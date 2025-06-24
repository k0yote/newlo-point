// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @notice Mock implementation of Chainlink's AggregatorV3Interface for testing
 * @dev This contract simulates Chainlink price feeds with configurable prices and timestamps
 */
contract MockV3Aggregator is AggregatorV3Interface {
    uint public constant override version = 4;

    uint8 public override decimals;
    string public override description;
    int public latestAnswer;
    uint public latestTimestamp;
    uint80 public latestRound;

    mapping(uint80 => int) public getAnswer;
    mapping(uint80 => uint) public getTimestamp;
    mapping(uint80 => uint) public getStartedAt;

    constructor(uint8 _decimals, int _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(int _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
    }

    function updateRoundData(uint80 _roundId, int _answer, uint _timestamp, uint _startedAt)
        public
    {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[_roundId] = _answer;
        getTimestamp[_roundId] = _timestamp;
        getStartedAt[_roundId] = _startedAt;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        return (
            _roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], _roundId
        );
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        return (latestRound, latestAnswer, latestTimestamp, latestTimestamp, latestRound);
    }
}
