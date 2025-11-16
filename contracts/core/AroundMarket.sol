// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {AroundMath} from "../libraries/AroundMath.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AroundMarket is IAroundMarket {

    using SafeERC20 for IERC20;
    uint256 public marketId;

    address public oracle;

    mapping(address => bool) public validToken;

    mapping(uint256 => MarketInfo) public marketInfo;

    mapping(uint256 => LiqudityInfo) public liqudityInfo;

    mapping(address => mapping(uint256 => UserPosition)) public userPosition;


    function createMarket(
        uint16 _marketFee,
        uint32 _period,
        uint128 _virtualLiquidity,
        uint128 _collateralAmount,
        address _collateral,
        string calldata _quest
    ) external {
        uint64 _currentTime = uint64(block.timestamp);
        uint64 _endTime = _currentTime + _period;
        //TODO transfer to Collateral pool
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _collateralAmount);
        //TODO around
        marketInfo[marketId] = MarketInfo({
            result: Bet.Pending,
            marketFee: _marketFee,
            startTime: _currentTime,
            endTime: _endTime,
            collateral: _collateral,
            around: address(0),
            creator: msg.sender,
            quest: _quest,
            resultData: ""
        });
        liqudityInfo[marketId] = LiqudityInfo({
            virtualLiquidity: _virtualLiquidity,
            collateralAmount: _collateralAmount,
            totalLp: 0,
            totalFee: 0,
            yesAmount: 0,
            noAmount: 0
        });
        marketId++;
    }


    function buy(Bet bet, uint128 amount, uint256 thisMarketId) external {
        require(amount > 0, "Input amount must be positive");
        MarketInfo memory newMarketInfo = marketInfo[marketId];
        //Transfer fund to around
        IERC20(newMarketInfo.collateral).safeTransferFrom(msg.sender, newMarketInfo.around, amount);
        
        // 计算输出数量和手续费
        (uint256 output, uint128 fee) = AroundMath._calculateOutput(
            bet,
            newMarketInfo.marketFee,
            amount,
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].collateralAmount
        );
        
        require(output > 0, "Insufficient output");
        
        // 计算净输入（扣除手续费）
        (uint128 netInput, ) = AroundMath._calculateNetInput(newMarketInfo.marketFee, amount);
        
        // 更新市场状态
        if (bet == IAroundMarket.Bet.Yes) {
            liqudityInfo[thisMarketId].yesAmount -= output;
            liqudityInfo[thisMarketId].noAmount += netInput;
            userPosition[msg.sender][thisMarketId].yesBalance += output;
        } else {
            liqudityInfo[thisMarketId].noAmount -= output;
            liqudityInfo[thisMarketId].yesAmount += netInput;
            userPosition[msg.sender][thisMarketId].noBalance += output;
        }
        
        liqudityInfo[thisMarketId].totalLp += netInput;
        liqudityInfo[thisMarketId].totalFee += fee;
    }

    function sell(Bet bet, uint256 amount, uint256 thisMarketId) external {
        require(amount > 0, "Token amount must be positive");
        
        // 检查用户持仓
        if (bet == IAroundMarket.Bet.Yes) {
            require(userPosition[msg.sender][thisMarketId].yesBalance >= amount, "Insufficient YES tokens");
            userPosition[msg.sender][thisMarketId].yesBalance -= amount;
        } else {
            require(userPosition[msg.sender][thisMarketId].noBalance >= amount, "Insufficient NO tokens");
            userPosition[msg.sender][thisMarketId].noBalance -= amount;
        }
        
        // 计算输出数量和手续费
        (uint256 output, uint128 fee) = AroundMath._calculateSellOutput(
            bet,
            marketInfo[thisMarketId].marketFee,
            amount,
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].collateralAmount
        );
        
        require(output > 0, "Insufficient output");
        
        // 更新市场状态
        if (bet == IAroundMarket.Bet.Yes) {
            liqudityInfo[thisMarketId].yesAmount += amount;
            liqudityInfo[thisMarketId].noAmount -= output + fee;
        } else {
            liqudityInfo[thisMarketId].noAmount += amount;
            liqudityInfo[thisMarketId].yesAmount -= output + fee;
        }
        
        liqudityInfo[thisMarketId].totalLp -= (output + fee);
        liqudityInfo[thisMarketId].totalFee += fee;
        
        // 转移抵押代币给用户
        IERC20(marketInfo[thisMarketId].collateral).safeTransfer(msg.sender, output);
    }

    function addLiquidity(uint128 amount, uint256 thisMarketId) external {
        require(block.timestamp + 1 hours < marketInfo[thisMarketId].endTime, "Market preparation is over.");
        require(amount > 0, "Amount must be positive");
        
        IERC20(marketInfo[thisMarketId].collateral).safeTransferFrom(msg.sender, address(this), amount);
        
        // Get yes and no share
        (uint256 yesShare, uint256 noShare) = AroundMath._calculateLiquidityShares(
            amount,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
        
        // Update market state
        liqudityInfo[thisMarketId].yesAmount += yesShare;
        liqudityInfo[thisMarketId].noAmount += noShare;
        liqudityInfo[thisMarketId].collateralAmount += amount;
        liqudityInfo[thisMarketId].totalLp += amount;
        
        // Update user position
        userPosition[msg.sender][thisMarketId].lp += amount;
        userPosition[msg.sender][thisMarketId].yesBalance += yesShare;
        userPosition[msg.sender][thisMarketId].noBalance += noShare;
    }

    function removeLiquidity(uint256 thisMarketId, uint256 lpShare) external {
        require(block.timestamp + 1 hours < marketInfo[thisMarketId].endTime, "Market preparation is over.");
        require(lpShare > 0 && userPosition[msg.sender][thisMarketId].lp >= lpShare, "Invalid liquidity share");
        
        // 计算应得的抵押代币和手续费分成
        (uint128 collateralAmount, uint128 feeShare) = AroundMath._calculateLiquidityWithdrawal(
            lpShare,
            liqudityInfo[thisMarketId].collateralAmount,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].totalFee
        );
        
        require(collateralAmount > 0, "No collateral to withdraw");
        
        // 计算应减少的YES和NO代币数量
        (uint256 yesReduction, uint256 noReduction) = AroundMath._calculateLiquidityShares(
            lpShare,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
        
        // 更新流动性状态
        liqudityInfo[thisMarketId].yesAmount -= yesReduction;
        liqudityInfo[thisMarketId].noAmount -= noReduction;
        liqudityInfo[thisMarketId].collateralAmount -= collateralAmount;
        liqudityInfo[thisMarketId].totalLp -= lpShare;
        
        // 更新手续费余额
        if (feeShare > 0) {
            liqudityInfo[thisMarketId].totalFee -= feeShare;
        }
        
        // 更新用户持仓
        userPosition[msg.sender][thisMarketId].lp -= lpShare;
        
        // 转移抵押代币和手续费分成给用户
        IERC20(marketInfo[thisMarketId].collateral).safeTransfer(msg.sender, collateralAmount + feeShare);
    }

    function redeemWinnings(uint256 thisMarketId) external returns (uint256 winnings) {
        require(block.timestamp > marketInfo[thisMarketId].endTime + 1 hours, "The review has not been completed.");
        UserPosition memory position = userPosition[msg.sender][thisMarketId];
        require(position.yesBalance > 0 || position.noBalance > 0 || position.lp > 0, "No position");
        
        // 计算代币收益
        if (marketInfo[thisMarketId].result == Bet.Yes) { // YES获胜
            if (position.yesBalance > 0) {
                winnings = (position.yesBalance * liqudityInfo[thisMarketId].collateralAmount) / liqudityInfo[thisMarketId].yesAmount;
            }
        } else { // NO获胜
            if (position.noBalance > 0) {
                winnings = (position.noBalance * liqudityInfo[thisMarketId].collateralAmount) / liqudityInfo[thisMarketId].noAmount;
            }
        }
        
        // 流动性提供者收益（按比例赎回）
        if (position.lp > 0) {
            (uint256 liquidityValue, ) = AroundMath._calculateLiquidityWithdrawal(
                position.lp,
                liqudityInfo[thisMarketId].totalLp,
                liqudityInfo[thisMarketId].yesAmount,
                liqudityInfo[thisMarketId].noAmount,
                liqudityInfo[thisMarketId].totalFee
            );
            winnings += liquidityValue;
        }
        
        require(winnings > 0, "No winnings");
        IERC20(marketInfo[thisMarketId].collateral).safeTransfer(msg.sender, winnings);
        
        // 清空用户持仓
        delete userPosition[msg.sender][thisMarketId];
    }
    
    // 查看流动性价值
    function getLiquidityValue(uint256 thisMarketId, address _user) public view returns (uint256 totalValue) {
        UserPosition memory position = userPosition[_user][thisMarketId];
        if (position.lp == 0) return 0;
        
        return AroundMath._calculateLiquidityValue(
            position.lp,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].totalFee
        );
    }
    
    // 预估移除流动性
    function estimateLiquidityRemoval(uint256 thisMarketId, uint256 lpShare) public view returns (
        uint256 collateralAmount, 
        uint256 feeShare,
        uint256 totalValue
    ) {
        require(lpShare <= liqudityInfo[thisMarketId].totalLp, "Insufficient total liquidity");
        
        (collateralAmount, feeShare) = AroundMath._calculateLiquidityWithdrawal(
            lpShare,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].totalFee
        );
        
        totalValue = collateralAmount + feeShare;
    }
    
    // 其他查看函数保持不变...
    function getYesPrice(uint256 thisMarketId) public view returns (uint256) {
        return AroundMath._calculateYesPrice(
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].collateralAmount
        );
    }
    
    function getNoPrice(uint256 thisMarketId) public view returns (uint256) {
        return 1e18 - getYesPrice(thisMarketId);
    }

}