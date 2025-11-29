// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAaveProtocolDataProvider {

    function getPaused(address asset) external view returns (bool isPaused);

    function getUserReserveData(address asset, address user) external view returns (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        uint256 principalStableDebt,
        uint256 scaledVariableDebt,
        uint256 stableBorrowRate,
        uint256 liquidityRate,
        uint40 stableRateLastUpdated,
        bool usageAsCollateralEnabled
    );

}