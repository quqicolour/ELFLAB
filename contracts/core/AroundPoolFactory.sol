// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "./AroundPool.sol";
import "./LuckyPool.sol";
import "./InsurancePool.sol";
import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {IAroundPoolFactory} from "../interfaces/IAroundPoolFactory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract AroundPoolFactory is Ownable, IAroundPoolFactory{

    address public aroundMarket;
    bool public isInitialize;
    uint256 public marketId;

    AaveInfo private aaveInfo;

    constructor(
        address thisPool,
        address thisAToken,
        address thisAaveProtocolDataProvider
    )Ownable(msg.sender){
        aaveInfo.pool = thisPool;
        aaveInfo.aToken = thisAToken;
        aaveInfo.aaveProtocolDataProvider = thisAaveProtocolDataProvider;
    }

    mapping(uint256 => PoolInfo) private poolInfo;

    function initialize(address _aroundMarket) external onlyOwner {
        require(isInitialize == false, "Already initialize");
        aroundMarket = _aroundMarket;
        isInitialize = true;
    }

    function setAaveInfo(
        bool state,
        uint16 newReferralCode,
        address thisPool,
        address thisAToken,
        address thisAaveProtocolDataProvider
    ) external {
        aaveInfo.isClosedAave = state;
        aaveInfo.pool = thisPool;
        aaveInfo.aToken = thisAToken;
        aaveInfo.aaveProtocolDataProvider = thisAaveProtocolDataProvider;
        aaveInfo.referralCode = newReferralCode;
    }

    function createPool(
        address collateral
    ) external {
        //AroundPool
        address newAroundPool = Create2.deploy(
            0, 
            keccak256(abi.encodePacked(marketId, msg.sender, block.chainid)), 
            abi.encodePacked(
                type(AroundPool).creationCode, 
                abi.encode(aroundMarket, collateral)
            )
        );
        //LuckyPool
        address newLuckyPool = Create2.deploy(
            0, 
            keccak256(abi.encodePacked(marketId, msg.sender, block.chainid)),
            abi.encodePacked(
                type(LuckyPool).creationCode, 
                abi.encode(aroundMarket)
            )
        );
        //InsurancePool
        address newInsurancePool = Create2.deploy(
            0, 
            keccak256(abi.encodePacked(marketId, msg.sender, block.chainid)), 
            abi.encodePacked(
                type(InsurancePool).creationCode, 
                abi.encode(aroundMarket, collateral)
            )
        );
        poolInfo[marketId].collateral = collateral;
        poolInfo[marketId].aroundPool = newAroundPool;
        poolInfo[marketId].luckyPool = newLuckyPool;
        poolInfo[marketId].insurancePool = newInsurancePool;
        marketId++;
    }

    function getPoolInfo(uint256 thisMarketId) external view returns (PoolInfo memory thisPoolInfo) {
        thisPoolInfo = poolInfo[thisMarketId];
    }

    function getAaveInfo() external view returns (AaveInfo memory thisAaveInfo) {
        thisAaveInfo = aaveInfo;
    }

}