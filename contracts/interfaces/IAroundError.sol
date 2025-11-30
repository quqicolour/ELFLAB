// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IAroundError {

    error AlreadyInitialize();
    error InvalidState();
    error InvalidToken();
    error ZeroAmount();
    error InvalidOutput();
    error InsufficientBalance();
    error MarketAlreadyEnd();
}