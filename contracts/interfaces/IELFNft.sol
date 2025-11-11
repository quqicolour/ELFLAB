// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

interface IELFNft {

  function valid(address user) external view returns (bool state);

}