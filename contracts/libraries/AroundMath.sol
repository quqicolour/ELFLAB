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
    
    // 购买yes或者no（计算包含费用的输出）
    function _calculateOutput(
        IAroundMarket.Bet _bet,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 _output, uint128 _fee) {
        if(_bet == IAroundMarket.Bet.Yes) {
            // 购买YES代币：用抵押物换取YES
            (_output, _fee) = _calculateYesOutput(
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount, 
                _collateralBalance
            );
        } else if(_bet == IAroundMarket.Bet.No) {
            // 购买NO代币：用抵押物换取NO
            (_output, _fee) = _calculateNoOutput(
                _feeRate,
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount, 
                _collateralBalance
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
        uint256 _collateralBalance
    ) internal pure returns (uint256 output, uint128 fee) {
        // 计算净输入（扣除费用）
        (uint128 netInput, uint128 inputFee) = _calculateNetInput(_feeRate, _inputAmount);
        
        // 使用恒定乘积公式： (_yesAmount + virtual) * (collateralBalance + virtual) = k
        uint256 k = (_yesAmount + _virtualLiquidity) * (_collateralBalance + _virtualLiquidity);
        uint256 newCollateralBalance = _collateralBalance + netInput;
        
        // 计算新的YES代币数量：newYesAmount = k / (newCollateralBalance + virtual) - virtual
        uint256 newYesAmount = (k / (newCollateralBalance + _virtualLiquidity)) - _virtualLiquidity;
        
        // 输出量 = 原来的YES代币数量 - 新的YES代币数量
        if (_yesAmount > newYesAmount) {
            output = _yesAmount - newYesAmount;
            fee = inputFee;
        } else {
            output = 0;
            fee = 0;
        }
    }
    
    function _calculateNoOutput(
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 output, uint128 fee) {
        // 计算净输入（扣除费用）
        (uint128 netInput, uint128 inputFee) = _calculateNetInput(_feeRate, _inputAmount);
        
        // 使用恒定乘积公式： (noTokens + virtual) * (collateralBalance + virtual) = k
        uint256 k = (_noAmount + _virtualLiquidity) * (_collateralBalance + _virtualLiquidity);
        uint256 newCollateralBalance = _collateralBalance + netInput;
        
        // 计算新的NO代币数量：newNoAmount = k / (newCollateralBalance + virtual) - virtual
        uint256 newNoAmount = (k / (newCollateralBalance + _virtualLiquidity)) - _virtualLiquidity;
        
        // 输出量 = 原来的NO代币数量 - 新的NO代币数量
        if (_noAmount > newNoAmount) {
            output = _noAmount - newNoAmount;
            fee = inputFee;
        } else {
            output = 0;
            fee = 0;
        }
    }
    
    
    // 计算出售YES/NO代币的输出（获得抵押物）（反向操作）
    function _calculateSellOutput(
        IAroundMarket.Bet _bet,
        uint16 _feeRate,
        uint256 _sellAmount, // 要出售的代币数量
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 output, uint128 fee) {
        if(_bet == IAroundMarket.Bet.Yes) {
            // 出售YES代币：换取抵押物
            (output, fee) = _calculateYesSellOutput(
                _feeRate, 
                _sellAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
        } else if(_bet == IAroundMarket.Bet.No) {
            // 出售NO代币：换取抵押物
            (output, fee) = _calculateNoSellOutput(
                _feeRate, 
                _sellAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
        } else {
            revert("Invalid bet");
        }
    }
    
    function _calculateYesSellOutput(
        uint16 _feeRate,
        uint256 _sellAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 collateralOutput, uint128 fee) {
        // 出售YES代币：YES代币增加，抵押物减少
        uint256 k = (_yesAmount + _virtualLiquidity) * (_collateralBalance + _virtualLiquidity);
        uint256 newYesTokens = _yesAmount + _sellAmount;
        
        // 计算新的抵押物数量：newCollateral = k / (newYesTokens + virtual) - virtual
        uint256 newCollateralBalance = (k / (newYesTokens + _virtualLiquidity)) - _virtualLiquidity;
        
        // 输出量（抵押物）= 原来的抵押物数量 - 新的抵押物数量
        if (_collateralBalance > newCollateralBalance) {
            uint256 grossOutput = _collateralBalance - newCollateralBalance;
            // 计算出售费用（0.3%）
            fee = uint128((grossOutput * _feeRate) / FEE_DENOMINATOR);
            collateralOutput = grossOutput - fee;
        } else {
            collateralOutput = 0;
            fee = 0;
        }
    }
    
    function _calculateNoSellOutput(
        uint16 _feeRate,
        uint256 _tokenAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 collateralOutput, uint128 fee) {
        // 出售NO代币：NO代币增加，抵押物减少
        uint256 k = (_noAmount + _virtualLiquidity) * (_collateralBalance + _virtualLiquidity);
        uint256 newNoTokens = _noAmount + _tokenAmount;
        
        // 计算新的抵押物数量：newCollateral = k / (newNoTokens + virtual) - virtual
        uint256 newCollateralBalance = (k / (newNoTokens + _virtualLiquidity)) - _virtualLiquidity;
        
        // 输出量（抵押物）= 原来的抵押物数量 - 新的抵押物数量
        if (_collateralBalance > newCollateralBalance) {
            uint256 grossOutput = _collateralBalance - newCollateralBalance;
            // 计算出售费用（0.3%）
            fee = uint128((grossOutput * _feeRate) / FEE_DENOMINATOR);
            collateralOutput = grossOutput - fee;
        } else {
            collateralOutput = 0;
            fee = 0;
        }
    }
    
    // 计算当前价格（YES代币的概率）
    function _calculateYesPrice(
        uint256 _virtualLiquidity,
        uint256 _yesTokens, 
        uint256 _noTokens,
        uint256 _collateralBalance
    ) internal pure returns (uint256 price) {
        if (_yesTokens == 0 && _noTokens == 0) {
            return 0.5e18; // 50% 概率，使用18位小数
        }
        
        // 价格基于YES和NO代币的相对稀缺性
        uint256 totalValue = _collateralBalance + 2 * _virtualLiquidity;
        uint256 yesValue = (_yesTokens > 0) ? _collateralBalance * _noTokens / (_yesTokens + _noTokens) : 0;
        
        return (yesValue * 1e18) / totalValue;
    }
    
    // 计算购买滑点（包含费用）
    function _calculateBuySlippage(
        IAroundMarket.Bet _bet,
        uint16 _feeRate,
        uint128 _inputAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 _slippage) {
        uint256 spotPrice;
        uint256 effectivePrice;
        
        if (_bet == IAroundMarket.Bet.Yes) {
            spotPrice = _calculateYesPrice(
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount, 
                _collateralBalance
            );
            (uint256 output, ) = _calculateYesOutput(
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            if (output > 0) {
                // 有效价格包含费用
                effectivePrice = (_inputAmount * 1e18) / output;
                if (effectivePrice > spotPrice) {
                    _slippage = ((effectivePrice - spotPrice) * 1e18) / spotPrice;
                }
            }
        } else {
            spotPrice = 1e18 - _calculateYesPrice(
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            (uint256 output, ) = _calculateNoOutput(
                _feeRate, 
                _inputAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            if (output > 0) {
                effectivePrice = (_inputAmount * 1e18) / output;
                if (effectivePrice > spotPrice) {
                    _slippage = ((effectivePrice - spotPrice) * 1e18) / spotPrice;
                }
            }
        }
        
        return _slippage;
    }
    
    // 计算出售滑点（包含费用）
    function _calculateSellSlippage(
        IAroundMarket.Bet _bet,
        uint16 _feeRate,
        uint256 _sellAmount,
        uint256 _virtualLiquidity,
        uint256 _yesAmount, 
        uint256 _noAmount,
        uint256 _collateralBalance
    ) internal pure returns (uint256 _slippage) {
        uint256 spotPrice;
        uint256 effectivePrice;
        
        if (_bet == IAroundMarket.Bet.Yes) {
            spotPrice = _calculateYesPrice(
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            (uint256 output, ) = _calculateYesSellOutput(
                _feeRate, 
                _sellAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            if (output > 0 && _sellAmount > 0) {
                // 有效价格 = 代币数量 / 输出抵押物数量
                effectivePrice = (_sellAmount * 1e18) / output;
                if (spotPrice > effectivePrice) {
                    _slippage = ((spotPrice - effectivePrice) * 1e18) / spotPrice;
                }
            }
        } else {
            spotPrice = 1e18 - _calculateYesPrice(
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            (uint256 output, ) = _calculateNoSellOutput(
                _feeRate, 
                _sellAmount, 
                _virtualLiquidity, 
                _yesAmount, 
                _noAmount,
                _collateralBalance
            );
            if (output > 0 && _sellAmount > 0) {
                effectivePrice = (_sellAmount * 1e18) / output;
                if (spotPrice > effectivePrice) {
                    _slippage = ((spotPrice - effectivePrice) * 1e18) / spotPrice;
                }
            }
        }
        
        return _slippage;
    }
    

    // 计算流动性提供者应得的份额
    function _calculateLiquidityShares(
        uint256 _lpShare,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount
    ) internal pure returns (uint256 yesShare, uint256 noShare) {
        if (_totalLp == 0) {
            yesShare = _lpShare / 2;
            noShare = _lpShare / 2;
        }else {
            // 按比例分配YES和NO代币
            yesShare = (_lpShare * _yesAmount) / _totalLp;
            noShare = (_lpShare * _noAmount) / _totalLp;
        }
    }
    
    //TODO
    // 计算移除流动性时应得的抵押代币
    function _calculateLiquidityWithdrawal(
        uint256 _lpShare,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint128 _feeAmount
    ) internal pure returns (uint128 collateralAmount, uint128 feeShare) {
        require(_totalLp > 0, "No liquidity provided");
        
        // 计算流动性提供者占总流动性的比例
        uint256 shareRatio = (_lpShare * 1e18) / _totalLp;
        
        // 应得的抵押代币数量（按比例）
        collateralAmount = uint128((shareRatio * (_yesAmount + _noAmount)) / 1e18);
        
        // 应得的手续费分成
        feeShare = uint128((shareRatio * _feeAmount) / 1e18);
    }
    
    // 计算流动性提供者的总价值
    function _calculateLiquidityValue(
        uint256 _lpShare,
        uint256 _totalLp,
        uint256 _yesAmount,
        uint256 _noAmount,
        uint128 _feeAmount
    ) internal pure returns (uint256 totalValue) {
        if (_totalLp > 0) {
            uint256 shareRatio = (_lpShare * 1e18) / _totalLp;
            totalValue = (shareRatio * (_yesAmount + _noAmount + _feeAmount)) / 1e18;
        }
    }
}