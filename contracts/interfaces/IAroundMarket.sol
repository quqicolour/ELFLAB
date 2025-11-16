// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IAroundMarket {

    enum Bet{Pending, Yes, No}

    struct MarketInfo{
        Bet result;
        uint16 marketFee;
        uint64 startTime;
        uint64 endTime;
        address collateral;
        address around;
        address creator;
        string quest;
        string resultData;
    }

    struct LiqudityInfo {
        uint128 virtualLiquidity;
        uint128 collateralAmount;
        uint128 totalFee;
        uint256 totalLp;
        uint256 yesAmount;
        uint256 noAmount;
    }

    struct UserPosition {
        uint256 yesTokens;
        uint256 noTokens;
        uint256 lp;
    }
}