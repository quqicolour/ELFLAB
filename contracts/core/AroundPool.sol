// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAroundPool} from "../interfaces/IAroundPool.sol";
import {IAroundPoolFactory} from "../interfaces/IAroundPoolFactory.sol";

import {IPool} from "../interfaces/aave/IPool.sol";
import {IAaveProtocolDataProvider} from "../interfaces/aave/IAaveProtocolDataProvider.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AroundPool is IAroundPool {

    using SafeERC20 for IERC20;

    uint64 private MinimumProfit = 10000;
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
        bool ifOpenAave,
        uint128 amountIn
    ) external onlyCaller{
        //Trade amount + liquidityFee
        reserveInfo.totalCollateralAmount += amountIn;
        reserveInfo.balance = uint128(_getTokenBalance());
        address pool = _getAaveInfo().pool;
        if(ifOpenAave) {
            reserveInfo.lentOut += reserveInfo.balance;
            IERC20(token).approve(pool, reserveInfo.balance);
            IPool(pool).deposit(token, reserveInfo.balance, address(this), _getAaveInfo().referralCode);
        }
    }

    function touch(
        bool ifEnd,
        bool ifOpenAave,
        address receiver,
        uint128 amountOut
    ) external onlyCaller {
        address pool = _getAaveInfo().pool;
        reserveInfo.totalCollateralAmount -= amountOut;
        if(ifOpenAave) {
            address aToken = _getAaveInfo().aToken;
            uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
            if(aTokenBalance > 0){
                IERC20(aToken).approve(pool, type(uint256).max);
                IPool(pool).withdraw(token, type(uint256).max, address(this));
                IERC20(aToken).approve(pool, 0);
            }
        }
        IERC20(token).safeTransfer(receiver, amountOut);
        uint256 tokenBalance = _getTokenBalance();
        if(ifEnd == false && ifOpenAave) {
            IERC20(token).approve(pool, tokenBalance);
            IPool(pool).deposit(token, tokenBalance, address(this), _getAaveInfo().referralCode);
        }
        reserveInfo.balance = uint128(_getTokenBalance());
        emit Touch(token, receiver, amountOut);
    }

    function allot(bool ifOpenAave) external onlyCaller {
        address pool = _getAaveInfo().pool;
        if(ifOpenAave) {
            address aToken = _getAaveInfo().aToken;
            uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
            if(aTokenBalance > 0){
                IERC20(aToken).approve(pool, type(uint256).max);
                IPool(pool).withdraw(token, type(uint256).max, address(this));
                IERC20(aToken).approve(pool, 0);
            }
        }
        reserveInfo.balance = uint128(_getTokenBalance());
        if(reserveInfo.balance > reserveInfo.totalCollateralAmount) {
            reserveInfo.lentOut = 0;
            //Transfer to AroundFactory and carry out redistribution.
            if(reserveInfo.balance > reserveInfo.totalCollateralAmount + MinimumProfit) {
                uint256 earn = reserveInfo.balance - reserveInfo.totalCollateralAmount - MinimumProfit;
                IERC20(token).safeTransfer(aroundPoolFactory, earn);
            }
        } else {
            reserveInfo.lentOut -= reserveInfo.balance;
        }
    }

    function _checkCaller() private view {
        require(msg.sender == aroundMarket);
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