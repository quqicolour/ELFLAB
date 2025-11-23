// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IAroundMarket} from "../interfaces/IAroundMarket.sol";

library AroundMath {

    uint32 public constant FEE_DENOMINATOR = 100000;

    function _calculateNetInput(
        uint16 _feeRate, 
        uint128 _inputAmount
    ) internal pure returns (uint128 netInput, uint128 fee) {
        fee = (_inputAmount * _feeRate) / FEE_DENOMINATOR;
        netInput = _inputAmount - fee;
    }
    
    // Purchase yes or no (calculate the output including the cost)
    function _calculateOutput(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 _output, uint128 _fee) {
        if(_bet == IAroundMarket.Result.Yes) {
            (_output, _fee) = _calculateYesOutput(
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance,
                IAroundMarket.Result.Pending
            );
        } else if(_bet == IAroundMarket.Result.No) {
            // 购买NO代币：用抵押物换取NO
            (_output, _fee) = _calculateNoOutput(
                _feeRate,
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance,
                IAroundMarket.Result.Pending
            );
        } else {
            revert("Invalid bet");
        }
    }
    
    function _calculateYesOutput(
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance,
        IAroundMarket.Result _result
    ) internal pure returns (uint256 output, uint128 fee) {
        uint128 netInput;
        (netInput, fee) = _calculateNetInput(_feeRate, _inputAmount);
        
        uint256 _yesPrice = _calculateYesPrice(
            _yesAmount,
            _noAmount,
            _virtualLiquidity,
            _result
        );
        if(_yesPrice !=0 || _yesPrice != 1) {
            output = _inputAmount * 1e18 / _yesPrice;
        }
    }
    
    function _calculateNoOutput(
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint256 _collateralBalance,
        IAroundMarket.Result _result
    ) internal pure returns (uint256 output, uint128 fee) {
        uint128 netInput;
        (netInput, fee) = _calculateNetInput(_feeRate, _inputAmount);
        
        uint256 _noPrice = _calculateNoPrice(
            _yesAmount,
            _noAmount,
            _virtualLiquidity,
            _result
        );
        if(_noPrice !=0 || _noPrice != 1) {
            output = _inputAmount * 1e18 / _noPrice;
        }
        
    }
    
    function _calculateSellOutput(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint256 _sellAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 output, uint128 fee) {
        if(_bet == IAroundMarket.Result.Yes) {
            (output, fee) = _calculateYesSellOutput(
                _feeRate, 
                _sellAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance,
                IAroundMarket.Result.Pending
            );
        } else if(_bet == IAroundMarket.Result.No) {
            (output, fee) = _calculateNoSellOutput(
                _feeRate, 
                _sellAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance,
                IAroundMarket.Result.Pending
            );
        }
    }
    
    function _calculateYesSellOutput(
        uint16 _feeRate,
        uint256 _sellAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount, 
        uint256 _collateralBalance,
        IAroundMarket.Result _result
    ) internal pure returns (uint256 collateralOutput, uint128 fee) {
        uint256 _yesPrice = _calculateYesPrice(
            _yesAmount,
            _noAmount,
            _virtualLiquidity,
            _result
        );

        if(_yesPrice != 0) {
            collateralOutput = _sellAmount * _yesPrice / 1e18;
            if(collateralOutput > 1000) {
                fee = uint128((collateralOutput * _feeRate) / FEE_DENOMINATOR);
            }
        }
    }
    
    function _calculateNoSellOutput(
        uint16 _feeRate,
        uint256 _sellAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount, 
        uint256 _collateralBalance,
        IAroundMarket.Result _result
    ) internal pure returns (uint256 collateralOutput, uint128 fee) {
        uint256 _noPrice = _calculateNoPrice(
            _yesAmount,
            _noAmount,
            _virtualLiquidity,
            _result
        );

        if(_noPrice != 0) {
            collateralOutput = _sellAmount * _noPrice / 1e18;
            if(collateralOutput > 1000) {
                fee = uint128((collateralOutput * _feeRate) / FEE_DENOMINATOR);
            }
        }
    }
    
    function _calculateYesPrice(
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _virtualLiquidity,
        IAroundMarket.Result _result
    ) internal pure returns (uint256 price) {
        if(_result == IAroundMarket.Result.Yes) {
            price = 1e18;
        }else if(_result == IAroundMarket.Result.No) {
            price = 0;
        }else if(_result == IAroundMarket.Result.Pending){
            if (_yesAmount == 0 && _noAmount == 0) {
                return 0.5e18; 
            } else {
                price = (_yesAmount > 0) ? (_yesAmount  + _virtualLiquidity / 2) * 1e18  / (_yesAmount + _noAmount + _virtualLiquidity) : 0;
            }
        }
    }

    function _calculateNoPrice(
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _virtualLiquidity,
        IAroundMarket.Result _result
    ) internal pure returns (uint256) {
        return 1e18 - _calculateYesPrice(
            _yesAmount,
            _noAmount,
            _virtualLiquidity,
            _result
        );
    }
    
    // Calculate the purchase slippage (including costs)
    function _calculateBuySlippage(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 _slippage) {
        uint256 currentPrice;
        uint256 spotPrice;
        
        if (_bet == IAroundMarket.Result.Yes) {
            currentPrice = _calculateYesPrice(
                _yesAmount, 
                _noAmount,
                _virtualLiquidity,
                IAroundMarket.Result.Pending
            );
            (uint256 output, ) = _calculateYesOutput(
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance,
                IAroundMarket.Result.Pending
            );
            if (output > 0) {
                spotPrice = _calculateYesPrice(
                    _yesAmount + output, 
                    _noAmount,
                    _virtualLiquidity,
                    IAroundMarket.Result.Pending
                );
                if (spotPrice > currentPrice) {
                    _slippage = ((spotPrice - currentPrice) * 1e18) / currentPrice;
                }
            }
        } else {
            currentPrice = _calculateNoPrice(
                _yesAmount, 
                _noAmount,
                _virtualLiquidity,
                IAroundMarket.Result.Pending
            );
            (uint256 output, ) = _calculateNoOutput(
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance,
                IAroundMarket.Result.Pending
            );
            if (output > 0) {
                spotPrice = _calculateNoPrice(
                    _yesAmount, 
                    _noAmount + output,
                    _virtualLiquidity,
                    IAroundMarket.Result.Pending
                );
                if (spotPrice > currentPrice) {
                    _slippage = ((spotPrice - currentPrice) * 1e18) / currentPrice;
                }
            }
        }
    }
    
    // Calculate the selling slippage (including fees)
    function _calculateSellSlippage(
        IAroundMarket.Result _bet,
        uint16 _feeRate,
        uint256 _sellAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 _slippage) {
        uint256 currentPrice;
        uint256 spotPrice;
        
        if (_bet == IAroundMarket.Result.Yes) {
            currentPrice = _calculateYesPrice(
                _yesAmount, 
                _noAmount,
                _virtualLiquidity,
                IAroundMarket.Result.Pending
            );
            if (_sellAmount > 0) {
                spotPrice = _calculateYesPrice(
                    _yesAmount - _sellAmount, 
                    _noAmount,
                    _virtualLiquidity,
                    IAroundMarket.Result.Pending
                );
                if (currentPrice > spotPrice) {
                    _slippage = ((currentPrice - spotPrice) * 1e18) / currentPrice;
                }
            }
        } else {
            currentPrice = _calculateYesPrice(
                _yesAmount, 
                _noAmount,
                _virtualLiquidity,
                IAroundMarket.Result.Pending
            );
            if (_sellAmount > 0) {
                spotPrice = _calculateYesPrice(
                    _yesAmount, 
                    _noAmount - _sellAmount,
                    _virtualLiquidity,
                    IAroundMarket.Result.Pending
                );
                if (currentPrice > spotPrice) {
                    _slippage = ((currentPrice - spotPrice) * 1e18) / currentPrice;
                }
            }
        }
    }
    
    function _calculateSharesToMint(
        uint256 _inputCollateralAmount, 
        uint256 _totalLp, 
        uint256 _totalCollateral
    ) internal pure returns (uint256) {
        if (_totalLp == 0) {
            return _inputCollateralAmount;
        }
        return (_inputCollateralAmount * _totalLp) / _totalCollateral;
    }
    
    // 计算流动性提供者应得的份额
    function _calculateLiquidityShares(
        uint256 _inputCollateralAmount,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount
    ) internal pure returns (uint256 yesShare, uint256 noShare) {
        if (_totalLp == 0) {
            yesShare = _inputCollateralAmount;
            noShare = _inputCollateralAmount;
        }else {
            yesShare = (_inputCollateralAmount * _yesAmount) / _totalLp;
            noShare = (_inputCollateralAmount * _noAmount) / _totalLp;
        }
    }
    
    
    // Calculate the collateral tokens that should be obtained when removing liquidity
    function _calculateLiquidityWithdrawal(
        uint256 _lpShare,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint128 _feeAmount
    ) internal pure returns (uint128 collateralAmount, uint128 feeShare) {
        require(_totalLp > 0, "No liquidity provided");
        
        collateralAmount = uint128((_lpShare * (_yesAmount + _noAmount)) / _totalLp);
        
        feeShare = uint128(_lpShare * _feeAmount / _totalLp);
    }
    
    // Calculate the total value of liquidity providers
    function _calculateLiquidityValue(
        uint256 _lpShare,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint128 _feeAmount
    ) internal pure returns (uint256 totalValue) {
        if (_totalLp > 0) {
            totalValue = (_lpShare * (_yesAmount + _noAmount + _feeAmount)) / _totalLp;
        }
    }
}