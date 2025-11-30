// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAroundPool} from "../interfaces/IAroundPool.sol";
import {IAroundPoolFactory} from "../interfaces/IAroundPoolFactory.sol";

import {IPool} from "../interfaces/aave/IPool.sol";
import {IAaveProtocolDataProvider} from "../interfaces/aave/IAaveProtocolDataProvider.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AroundPool is IAroundPool {

    using SafeERC20 for IERC20;

    address public aroundPoolFactory;
    address public aroundMarket;
    address public token;

    constructor(
        address thisAroundMarket,
        address thisToken
    ) { 
        aroundPoolFactory = msg.sender;
        aroundMarket = thisAroundMarket;
        token= thisToken;
    }

    modifier onlyCaller {
        _checkCaller();
        _;
    }

    ReserveInfo public reserveInfo;

    function deposite(
        uint128 amountIn,
        uint128 thisLuckyFee,
        uint128 thisLiquidityFee
    ) external onlyCaller returns (bool state) {
        reserveInfo.luckyFee += thisLuckyFee;
        reserveInfo.liquidityFee += thisLiquidityFee;
        reserveInfo.marketTotalCollateralAmount += amountIn;
        address pool = _getAaveInfo().pool;
        if(getAavePoolPaused() == false) {
            reserveInfo.lentOut += amountIn;
            IERC20(token).approve(pool, amountIn);
            IPool(pool).deposit(token, amountIn, address(this), _getAaveInfo().referralCode);
        }else {
            reserveInfo.marketCollateralAmount += amountIn;
        }
        state = true;
    }

    function touch(
        bool ifEnd,
        address receiver, 
        uint256 amount
    ) external onlyCaller returns (bool state) {
        bool aaveState = getAavePoolPaused();
        address pool = _getAaveInfo().pool;
        if(aaveState == false) {
            address aToken = _getAaveInfo().aToken;
            uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
            if(aTokenBalance > 0){
                IERC20(aToken).approve(pool, type(uint256).max);
                IPool(pool).withdraw(token, type(uint256).max, address(this));
                IERC20(aToken).approve(pool, 0);
            }
        }
        IERC20(token).safeTransfer(receiver, amount);
        uint256 tokenBalance = _getTokenBalance();
        if(ifEnd == false && aaveState == false) {
            IERC20(token).approve(pool, tokenBalance);
            IPool(pool).deposit(token, tokenBalance, address(this), _getAaveInfo().referralCode);
        }
        emit Touch(token, receiver, amount);
        state = true;
    }

    function _checkCaller() private view {
        require(msg.sender == aroundMarket, "Non caller");
    }

    function _getAaveInfo() private view returns (IAroundPoolFactory.AaveInfo memory thisAaveInfo) {
        thisAaveInfo = IAroundPoolFactory(aroundPoolFactory).getAaveInfo();
    }

    function _getTokenBalance() internal view returns (uint256 accountTokenBalance) {
        accountTokenBalance = IERC20(token).balanceOf(address(this));
    }

    function getAavePoolPaused() public view returns (bool isPaused) {
        isPaused = IAaveProtocolDataProvider(_getAaveInfo().aaveProtocolDataProvider).getPaused(token);
    }

}