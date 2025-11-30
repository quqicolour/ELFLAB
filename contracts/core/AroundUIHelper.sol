// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {AroundMath} from "../libraries/AroundMath.sol";
import {IAroundMarket} from "../interfaces/IAroundMarket.sol";

contract AroundUIHelper {

    address public aroundMarket;

    constructor(address _aroundMarket) {
        aroundMarket = _aroundMarket;
    }

    function getYesPrice(uint256 thisMarketId) public view returns (uint256) {
        return AroundMath._calculateYesPrice(
            _getMarketInfo(thisMarketId).result,
            _getLiqudityInfo(thisMarketId).virtualLiquidity,
            _getLiqudityInfo(thisMarketId).yesAmount,
            _getLiqudityInfo(thisMarketId).noAmount
        );
    }
    
    function getNoPrice(uint256 thisMarketId) public view returns (uint256) {
        return 1e18 - getYesPrice(thisMarketId);
    }
    
    // View liquidity value
    function getLiquidityValue(uint256 thisMarketId, address _user) public view returns (uint256 totalValue) {
        if (_getUserPosition(_user, thisMarketId).lp == 0) return 0;
        
        return AroundMath._calculateLiquidityValue(
            _getLiqudityInfo(thisMarketId).virtualLiquidity,
            _getLiqudityInfo(thisMarketId).totalFee,
            _getUserPosition(_user, thisMarketId).lp,
            _getLiqudityInfo(thisMarketId).totalLp,
            _getLiqudityInfo(thisMarketId).yesAmount,
            _getLiqudityInfo(thisMarketId).noAmount
        );
    }
    
    // Estimated removal of liquidity
    function estimateLiquidityRemoval(uint256 thisMarketId, uint256 lpShare) public view returns (
        uint256 collateralAmount, 
        uint256 feeShare,
        uint256 totalValue
    ) {
        require(lpShare <= _getUserPosition(msg.sender, thisMarketId).lp, "Insufficient total liquidity");
        
        (collateralAmount, feeShare) = AroundMath._calculateLiquidityWithdrawal(
            _getLiqudityInfo(thisMarketId).totalFee,
            _getUserPosition(msg.sender, thisMarketId).collateralAmount,
            lpShare,
            _getUserPosition(msg.sender, thisMarketId).lp,
            _getLiqudityInfo(thisMarketId).totalLp
        );
        
        totalValue = collateralAmount + feeShare;
    }

    function _getMarketInfo(uint256 thisMarketId) private view returns (IAroundMarket.MarketInfo memory newMarketInfo) {
        newMarketInfo = IAroundMarket(aroundMarket).getMarketInfo(thisMarketId);
    }

    function _getLiqudityInfo(uint256 thisMarketId) private view returns (IAroundMarket.LiqudityInfo memory newLiqudityInfo) {
        newLiqudityInfo = IAroundMarket(aroundMarket).getLiqudityInfo(thisMarketId);
    }

    function _getUserPosition(address user, uint256 thisMarketId) private view returns (IAroundMarket.UserPosition memory newMarketInfo) {
        newMarketInfo = IAroundMarket(aroundMarket).getUserPosition(user, thisMarketId);
    }
}