// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IInsurancePool {
    
    event Repair(address indexed thisReceiver, uint256 indexed thisAmount);

    function repair(address receiver, uint256 amount) external;

}