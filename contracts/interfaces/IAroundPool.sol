// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IAroundPool {

    struct ReserveInfo {
        uint128 lentOut;
        uint128 marketCollateralAmount;
        uint128 marketTotalCollateralAmount;
        uint128 feeAmount;
    }

    event Touch(address indexed thisToken, address indexed thisReceiver, uint256 indexed thisAmount);

    function deposite(
        uint128 amountIn,
        uint128 feeIn
    ) external returns (bool state);

    function touch(
        bool ifEnd,
        address receiver, 
        uint256 amount
    ) external returns (bool state);

}