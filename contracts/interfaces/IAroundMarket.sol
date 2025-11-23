// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IAroundMarket {

    enum Result{Pending, Yes, No}

    struct MarketInfo{
        Result result;
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
        uint256 yesBalance;
        uint256 noBalance;
        uint256 lp;
    }
}