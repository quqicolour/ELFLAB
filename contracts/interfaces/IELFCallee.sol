// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IELFCallee {
    function elfV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}