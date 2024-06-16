// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Sarvesh Agarwal(Github - sarvesh1327)
 * @notice This library is used to check chainlink oracle for stale data
 * If a price is stale, the function will revert and make DUSDEngine unusable
 * We want DUSDEngine to freeze if prices become stale
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIME_OUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIME_OUT) {
            revert OracleLib__StalePrice();
        }
        return ( roundId,  answer,  startedAt,  updatedAt,  answeredInRound);
    }
}
