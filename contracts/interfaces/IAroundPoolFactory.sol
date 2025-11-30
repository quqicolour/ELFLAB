// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundPoolFactory {

    struct PoolInfo {
        address collateral;
        address aroundPool;
        address luckyPool;
        address insurancePool;
    }

    struct AaveInfo {
        bool isClosedAave;
        uint16 referralCode;
        address pool;
        address aToken;
        address aaveProtocolDataProvider;
    }

    function getPoolInfo(uint256 thisMarketId) external view returns (PoolInfo memory thisPoolInfo);

    function getAaveInfo() external view returns (AaveInfo memory thisAaveInfo);

}