// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundMarket {

    enum Result{Pending, Yes, No}

    /*********************************Struct****************************************** */
    struct PackedBaseFees {
        uint16 officialFee;
        uint16 liquidityFee;
        uint16 oracleFee;
        uint16 luckyFee;
        uint16 insuranceFee;
        uint16 totalFee;
    }
    
    struct CreateMarketParams {
        uint32 period;
        uint128 expectVirtualLiquidity;
        address collateral;
        string quest;
    }

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

    struct MarketState {
        bool ifOpenAave;
        bool locked;
        bool valid;
    }

    struct QuestInfo {
        string quest;
        string resultData;
    }

    struct MarketInfo{
        Result result;
        MarketState marketState;
        uint64 startTime;
        uint64 endTime;
        uint64 totalRaffleTicket;
        address collateral;
        address creator;
        QuestInfo questInfo;
    }

    struct LiqudityInfo {
        uint128 virtualLiquidity;
        uint128 tradeCollateralAmount;
        uint128 lpCollateralAmount;
        uint128 totalFee;
        uint128 luckyFeeAmount;
        uint128 liquidityFeeAmount;
        uint256 totalLp;
        uint256 yesAmount;
        uint256 noAmount;
    }

    struct UserPosition {
        uint64 raffleTicketNumber;
        uint128 collateralAmount;
        uint256 yesBalance;
        uint256 noBalance;
        uint256 lp;
        uint256 volume;
    }

    function oracle() external view returns (address);

    function raffleTicketToUser(uint256, uint64) external view returns (address);

    function getUserPosition(address user, uint256 thisMarketId) external view returns (UserPosition memory thisUserPosition);

    function getMarketInfo(uint256 thisMarketId) external view returns (MarketInfo memory thisMarketInfo);

    function getLiqudityInfo(uint256 thisMarketId) external view returns (LiqudityInfo memory thisLiqudityInfo);
}