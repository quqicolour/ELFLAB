// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IInsurancePool} from "../interfaces/IInsurancePool.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract InsurancePool is IInsurancePool {

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

    function repair(address receiver, uint256 amount) external {
        require(msg.sender == aroundMarket, "Non aroundMarket");
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 amountOut = balance >= amount ? amount : balance;
        if(amountOut > 0) {
            IERC20(token).safeTransfer(receiver, amountOut);
        }
        emit Repair(receiver, amount);
    }


}