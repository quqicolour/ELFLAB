// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundMarket {

    enum Result{Pending, Yes, No}

    /*********************************Struct****************************************** */
    
    struct CreateMarketParams {
        uint32 period;
        uint128 expectVirtualLiquidity;
        string quest;
        uint256 thisMarketId;
    }

    struct FeeInfo {
        uint16 officialFee;
        uint16 luckyFee;
        uint16 oracleFee;
        uint16 creatorFee;
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

    struct MarketInfo{
        Result result;
        MarketState marketState;
        uint64 startTime;
        uint64 endTime;
        uint64 totalRaffleTicket;
        address collateral;
        address creator;
        string quest;
    }

    struct LiqudityInfo {
        uint128 virtualLiquidity;
        uint128 tradeCollateralAmount;
        uint128 lpCollateralAmount;
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

    /*********************************Event****************************************** */
    event CreateNewMarket(uint256 thisNewMarketId, address creator);
    event Buy(uint256 thisMarketId, address buyer, Result bet, uint256 value);
    event Sell(uint256 thisMarketId, address seller, Result bet, uint256 amount);
    event AddLiqudity(uint256 thisMarketId, address lpProvider, uint256 value);
    event RemoveLiqudity(uint256 thisMarketId, address lpProvider, uint256 lpAmount);
    event Release(uint256 thisMarketId, address user, uint256 value);

    function oracle() external view returns (address);

    function raffleTicketToUser(uint256, uint64) external view returns (address);

    function getUserPosition(address user, uint256 thisMarketId) external view returns (UserPosition memory thisUserPosition);

    function getMarketInfo(uint256 thisMarketId) external view returns (MarketInfo memory thisMarketInfo);

    function getLiqudityInfo(uint256 thisMarketId) external view returns (LiqudityInfo memory thisLiqudityInfo);
}