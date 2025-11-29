// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IDebtTokenBase{
    function approveDelegation(address delegatee, uint256 amount) external;

    function borrowAllowance(
    address fromUser,
    address toUser
  ) external view returns (uint256);
}