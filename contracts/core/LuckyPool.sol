// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;


contract LuckyPool {
    
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
}