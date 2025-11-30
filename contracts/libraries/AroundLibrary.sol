// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

library AroundLibrary {

    uint32 private constant Max_Virtual_Rate = 100_000_000;

    struct CreateMarketParams {
        uint32 period;
        uint128 expectVirtualLiquidity;
        address collateral;
        string quest;
    }

    function _getGuardedAmount(
        uint8 _thisDecimals, 
        uint128 _expectVirtualAmount,
        uint128 _currentVirtualAmount
    ) internal pure returns (uint256 _amountOut) {
        if (_expectVirtualAmount == _currentVirtualAmount) {
            _amountOut = 100 * 10 ** _thisDecimals;
        }else if(_expectVirtualAmount > _currentVirtualAmount && _expectVirtualAmount <= Max_Virtual_Rate) {
             _amountOut = 100 * (_expectVirtualAmount / _currentVirtualAmount + 1) * 10 ** _thisDecimals;
        }else {
            revert ("Invalid expect virtualAmount");
        }
    }

}