// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IAroundMarket {

    enum Result{Pending, Yes, No}

    event SetFeeInfo(uint256 indexed thisId);

    /*********************************Struct****************************************** */

    struct FeeInfo {
        uint16 officialFee;
        uint16 luckyFee;
        uint16 oracleFee;
        uint16 insuranceFee;
        uint16 liquidityFee;
        uint16 totalFee;
    }

    struct TokenInfo {
        bool valid;
        uint128 guaranteeAmount;
    }

    struct QuestInfo {
        string quest;
        string resultData;
    }

    struct MarketInfo{
        Result result;
        uint64 startTime;
        uint64 endTime;
        address collateral;
        address creator;
        QuestInfo questInfo;
    }

    struct LiqudityInfo {
        uint128 virtualLiquidity;
        uint128 tradeCollateralAmount;
        uint128 lpCollateralAmount;
        uint128 totalFee;
        uint256 totalLp;
        uint256 yesAmount;
        uint256 noAmount;
    }

    struct UserPosition {
        uint256 yesBalance;
        uint256 noBalance;
        uint256 lp;
        uint128 collateralAmount;
    }
}