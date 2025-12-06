// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundPool {

    struct ReserveInfo {
        uint128 lentOut;
        uint128 balance;
        uint128 totalCollateralAmount;
    }

    event Touch(address indexed thisToken, address indexed thisReceiver, uint256 indexed thisAmount);

    function deposite(
        bool ifOpenAave,
        uint128 amountIn
    ) external;

    function touch(
        bool ifEnd,
        bool ifOpenAave,
        address receiver,
        uint128 amountOut
    ) external;

    function allot(bool ifOpenAave) external;

}