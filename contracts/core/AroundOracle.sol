// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

contract AroundOracle {
    
    struct OraclePriceInfo{
        uint64 updateTime; 
        uint128 price;
    }

    struct OracleRandomNumberInfo{
        uint64 updateTime;
        uint128 randomNumber;
    }

    struct OracleJudgeInfo {
        bool judge;
        uint64 updateTime;
    }
}