// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundError {

    error AlreadyInitialize();
    error NonMultiSig();
    error InvalidState();
    error InvalidToken();
    error ZeroAmount();
    error InvalidOutput();
    error InsufficientBalance();
    error LiquidityWayClosed();
    error InvalidLpShare();
    error MarketClosed();
    error NotWithdrawTime();
    error TouchOracleErr();
    error TouchAroundErr();
}