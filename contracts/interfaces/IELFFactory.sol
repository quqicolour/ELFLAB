// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0<0.8.20;

interface IELFFactory {

    struct PoolInfo{
        uint16 token0FeePercent;
        uint16 token1FeePercent;
        uint16 luckyPoolFeePercent;
        address feeReceiver;
        address luckyPool;
        bool stableSwap;
        bool isActive;
    }

    // =================================Event==========================================
    event PairCreated(address indexed token0, address indexed token1, address pair);

    // =================================Wirte==========================================
    function setManager(address _manager) external;
    function setFeeReceiver(address _feeReceiver) external;
    function setPairFee(address pair, uint16 fee) external;

    function createPair(address tokenA, address tokenB) external returns (address pair);

    // =================================Read==========================================
    function feeReceiver() external view returns (address);
    function poolInfo(address) external view returns (PoolInfo memory);
    function getPair(address, address) external view returns (address);
    function indexPair(uint256 index) external view returns (address _thisPair);
    function allPairsLength() external view returns (uint256);
    function pairCodeHash() external view returns (bytes32 _pairCodeHash);

}