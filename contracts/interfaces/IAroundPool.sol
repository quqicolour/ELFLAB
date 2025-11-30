// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundPool {

    struct ReserveInfo {
        uint128 lentOut;
        uint128 marketCollateralAmount;
        uint128 marketTotalCollateralAmount;
        uint128 luckyFee;
        uint128 liquidityFee;
    }

    event Touch(address indexed thisToken, address indexed thisReceiver, uint256 indexed thisAmount);

    function deposite(
        uint128 amountIn,
        uint128 thisLuckyFee,
        uint128 thisLiquidityFee
    ) external returns (bool state);

    function touch(
        bool ifEnd,
        address receiver, 
        uint256 amount
    ) external returns (bool state);

}