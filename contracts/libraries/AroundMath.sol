// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAroundMarket} from "../interfaces/IAroundMarket.sol";

library AroundMath {

    uint32 private constant FEE_DENOMINATOR = 100_000;
    uint256 private constant ONERATE = 1 ether;
    function _calculateNetInput(
        uint16 _feeRate, 
        uint128 _inputAmount
    ) internal pure returns (uint128 netInput, uint128 fee) {
        fee = (_inputAmount * _feeRate) / FEE_DENOMINATOR;
        netInput = _inputAmount - fee;
    }
    
    // Purchase yes or no (calculate the output including the cost)
    function _calculateBuyOutput(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 _output, uint128 _fee) {
        if(_bet == IAroundMarket.Result.Yes) {
            (_output, _fee) = _calculateBuyYesOutput(
                IAroundMarket.Result.Pending,
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _collateralBalance,
                _yesAmount, 
                _noAmount
            );
        } else if(_bet == IAroundMarket.Result.No) {
            (_output, _fee) = _calculateBuyNoOutput(
                IAroundMarket.Result.Pending,
                _feeRate,
                _inputAmount, 
                _virtualLiquidity, 
                _collateralBalance,
                _yesAmount, 
                _noAmount
            );
        } else {
            revert("Invalid bet");
        }
    }
    
    function _calculateBuyYesOutput(
        IAroundMarket.Result _result,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 output, uint128 fee) {
        uint128 netInput;
        (netInput, fee) = _calculateNetInput(_feeRate, _inputAmount);

        uint256 _yesPrice = _calculateYesPrice(
            _result,
            _virtualLiquidity,
            _yesAmount,
            _noAmount
        );
        //TODO type(uint128) < 10 ** 39 
        // AP1 + BP2 = L
        // A = (L - BP2) / P1
        if(_yesPrice != 0) {
            if(_yesPrice == ONERATE){
                output = netInput;
            }else {
                uint256 l = _collateralBalance + netInput + _virtualLiquidity;
                uint256 n = _noAmount + _virtualLiquidity;
                uint256 totalYesAmount = (ONERATE * l - n * (ONERATE - _yesPrice)) / _yesPrice;
                output = totalYesAmount - _yesAmount - _virtualLiquidity;
            }
        }
    }
    
    function _calculateBuyNoOutput(
        IAroundMarket.Result _result,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _yesAmount,
        uint256 _noAmount
    ) internal pure returns (uint256 output, uint128 fee) {
        uint128 netInput;
        (netInput, fee) = _calculateNetInput(_feeRate, _inputAmount);
        
        uint256 _noPrice = _calculateNoPrice(
            _result,
            _virtualLiquidity,
            _yesAmount,
            _noAmount
        );
        // AP1 + BP2 = L
        // B = (L - AP1) / P2
        if(_noPrice != 0) {
            if(_noPrice == ONERATE){
                output = netInput;
            }else{
                uint256 l = _collateralBalance + netInput + _virtualLiquidity;
                uint256 y = _yesAmount + _virtualLiquidity;
                uint256 totalNoAmount = (ONERATE * l - y * (ONERATE - _noPrice)) / _noPrice;
                output = totalNoAmount - _noAmount - _virtualLiquidity;
            }
        }
    }
    
    function _calculateSellOutput(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _sellAmount,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 output, uint128 fee) {
        if(_bet == IAroundMarket.Result.Yes) {
            (output, fee) = _calculateYesSellOutput(
                IAroundMarket.Result.Pending,
                _feeRate,
                _virtualLiquidity,
                _collateralBalance,
                _sellAmount,
                _yesAmount, 
                _noAmount
            );
        } else if(_bet == IAroundMarket.Result.No) {
            (output, fee) = _calculateNoSellOutput(
                IAroundMarket.Result.Pending,
                _feeRate, 
                _virtualLiquidity, 
                _collateralBalance,
                _sellAmount,
                _yesAmount, 
                _noAmount
            );
        }
    }
    
    function _calculateYesSellOutput(
        IAroundMarket.Result _result,
        uint16 _feeRate,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _sellAmount,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 collateralOutput, uint128 fee) {
        // AP1 + BP2 = L
        uint256 _yesPrice = _calculateYesPrice(
            _result,
            _virtualLiquidity,
            _yesAmount,
            _noAmount
        );
        if(_yesPrice != 0) {
            uint256 y = _yesAmount + _virtualLiquidity - _sellAmount;
            uint256 n = _noAmount + _virtualLiquidity;
            uint256 remainLiquidity = (y * _yesPrice + n * (ONERATE - _yesPrice)) / ONERATE;
            uint256 totalOutput = _collateralBalance + _virtualLiquidity - remainLiquidity;
            if(totalOutput > 1000) {
                fee = uint128((totalOutput * _feeRate) / FEE_DENOMINATOR);
            }
            collateralOutput = totalOutput - fee;
        }
    }
    
    function _calculateNoSellOutput(
        IAroundMarket.Result _result,
        uint16 _feeRate,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _sellAmount,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 collateralOutput, uint128 fee) {
        uint256 _noPrice = _calculateNoPrice(
            _result,
            _virtualLiquidity,
            _yesAmount,
            _noAmount
        );

        if(_noPrice != 0) {
            uint256 y = _yesAmount + _virtualLiquidity;
            uint256 n = _noAmount + _virtualLiquidity - _sellAmount;
            uint256 remainLiquidity = (y * (ONERATE - _noPrice) + n * _noPrice) / ONERATE;
            uint256 totalOutput = _collateralBalance + _virtualLiquidity - remainLiquidity;
            if(totalOutput > 1000) {
                fee = uint128((totalOutput * _feeRate) / FEE_DENOMINATOR);
            }
            collateralOutput = totalOutput - fee;
        }
    }
    
    function _calculateYesPrice(
        IAroundMarket.Result _result,
        uint128 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 price) {
        if(_result == IAroundMarket.Result.Yes) {
            price = ONERATE;
        }else if(_result == IAroundMarket.Result.No) {
            price = 0;
        }else if(_result == IAroundMarket.Result.Pending){
            if (_yesAmount == 0 && _noAmount == 0) {
                return ONERATE / 2; 
            } else {
                price = _yesAmount > 0 ? 
                (_yesAmount + _virtualLiquidity) * ONERATE  / (_yesAmount + _noAmount + 2 * _virtualLiquidity) : 0;
            }
        }
    }

    function _calculateNoPrice(
        IAroundMarket.Result _result,
        uint128 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256) {
        return ONERATE - _calculateYesPrice(
            _result,
            _virtualLiquidity,
            _yesAmount,
            _noAmount
        );
    }
    
    // Calculate the purchase slippage (including costs)
    function _calculateBuySlippage(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint128 _virtualLiquidity,
        uint128 _collateralBalance,
        uint256 _yesAmount, 
        uint256 _noAmount
    ) internal pure returns (uint256 _slippage) {
        uint256 currentPrice;
        uint256 spotPrice;
        
        if (_bet == IAroundMarket.Result.Yes) {
            currentPrice = _calculateYesPrice(
                IAroundMarket.Result.Pending,
                _virtualLiquidity,
                _yesAmount, 
                _noAmount
            );
            (uint256 output, ) = _calculateBuyYesOutput(
                IAroundMarket.Result.Pending,
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _collateralBalance,
                _yesAmount, 
                _noAmount
            );
            if (output > 0) {
                spotPrice = _calculateYesPrice(
                    IAroundMarket.Result.Pending,
                    _virtualLiquidity,
                    _yesAmount + output, 
                    _noAmount
                );
                if (spotPrice > currentPrice) {
                    _slippage = ((spotPrice - currentPrice) * ONERATE) / currentPrice;
                }
            }
        } else {
            currentPrice = _calculateNoPrice(
                IAroundMarket.Result.Pending,
                _virtualLiquidity,
                _yesAmount, 
                _noAmount
            );
            (uint256 output, ) = _calculateBuyNoOutput(
                IAroundMarket.Result.Pending,
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _collateralBalance,
                _yesAmount, 
                _noAmount
            );
            if (output > 0) {
                spotPrice = _calculateNoPrice(
                    IAroundMarket.Result.Pending,
                    _virtualLiquidity,
                    _yesAmount, 
                    _noAmount + output
                );
                if (spotPrice > currentPrice) {
                    _slippage = ((spotPrice - currentPrice) * ONERATE) / currentPrice;
                }
            }
        }
    }
    
    // Calculate the selling slippage (including fees)
    function _calculateSellSlippage(
        IAroundMarket.Result _bet,
        uint128 _virtualLiquidity,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint256 _sellAmount
    ) internal pure returns (uint256 _slippage) {
        uint256 currentPrice;
        uint256 spotPrice;
        
        if (_bet == IAroundMarket.Result.Yes) {
            currentPrice = _calculateYesPrice(
                IAroundMarket.Result.Pending,
                _virtualLiquidity,
                _yesAmount, 
                _noAmount
            );
            if (_sellAmount > 0) {
                spotPrice = _calculateYesPrice(
                    IAroundMarket.Result.Pending,
                    _virtualLiquidity,
                    _yesAmount - _sellAmount, 
                    _noAmount
                );
                if (currentPrice > spotPrice) {
                    _slippage = ((currentPrice - spotPrice) * ONERATE) / currentPrice;
                }
            }
        } else {
            currentPrice = _calculateYesPrice(
                IAroundMarket.Result.Pending,
                _virtualLiquidity,
                _yesAmount, 
                _noAmount
            );
            if (_sellAmount > 0) {
                spotPrice = _calculateYesPrice(
                    IAroundMarket.Result.Pending,
                    _virtualLiquidity,
                    _yesAmount, 
                    _noAmount - _sellAmount
                );
                if (currentPrice > spotPrice) {
                    _slippage = ((currentPrice - spotPrice) * ONERATE) / currentPrice;
                }
            }
        }
    }
    
    function _calculateSharesToMint(
        uint128 _inputCollateralAmount, 
        uint128 _totalCollateral,
        uint256 _totalLp
    ) internal pure returns (uint256) {
        if (_totalLp == 0) {
            return _inputCollateralAmount;
        }
        return (_inputCollateralAmount * _totalLp) / _totalCollateral;
    }
    
    function _calculateLiquidityShares(
        uint128 _inputAmount,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount
    ) internal pure returns (uint256 yesShare, uint256 noShare) {
        if (_totalLp == 0) {
            yesShare = _inputAmount;
            noShare = _inputAmount;
        }else {
            yesShare = (_inputAmount * _yesAmount) / _totalLp;
            noShare = (_inputAmount * _noAmount) / _totalLp;
        }
    }
    
    // Calculate the collateral tokens that should be obtained when removing liquidity
    function _calculateLiquidityWithdrawal(
        uint128 _feeAmount,
        uint128 _lpCollateral,
        uint256 _lpShare,
        uint256 _userTotalLp,
        uint256 _totalLp
    ) internal pure returns (uint128 collateralAmount, uint128 feeShare) {
        require(_totalLp > 0, "No liquidity provided");
        collateralAmount = uint128(_lpShare * _lpCollateral / _userTotalLp);
        feeShare = uint128(_lpShare * _feeAmount / _totalLp);
    }
    
    // Calculate the total value of liquidity providers
    function _calculateLiquidityValue(
        uint128 _virtualLiquidity,
        uint128 _feeAmount,
        uint256 _lpShare,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount
    ) internal pure returns (uint256 totalValue) {
        uint256 currentPrice = _calculateYesPrice(
                IAroundMarket.Result.Pending,
                _virtualLiquidity,
                _yesAmount, 
                _noAmount
        );
        if (_totalLp > 0) {
            totalValue = ((_yesAmount * currentPrice + (ONERATE - currentPrice) * _noAmount) / ONERATE 
            + _feeAmount) * _lpShare / _totalLp;
        }
    }
}