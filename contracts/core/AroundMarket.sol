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
        if(_collateralAmount > 0){
            IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _collateralAmount);
        }
        //TODO around
        marketInfo[marketId] = MarketInfo({
            result: Result.Pending,
            marketFee: _marketFee,
            startTime: _currentTime,
            endTime: _endTime,
            collateral: _collateral,
            around: address(this),
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


    function buy(Result bet, uint128 amount, uint256 thisMarketId) external {
        require(amount > 0, "Input amount must be positive");
        MarketInfo memory newMarketInfo = marketInfo[thisMarketId];
        //Transfer fund to around
        IERC20(newMarketInfo.collateral).safeTransferFrom(msg.sender, newMarketInfo.around, amount);
        
        // Calculate the output quantity and handling fee
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
        
        // Calculate the net input (minus handling fees)
        (uint128 netInput, ) = AroundMath._calculateNetInput(newMarketInfo.marketFee, amount);
        
        // Update the market status
        if (bet == IAroundMarket.Result.Yes) {
            liqudityInfo[thisMarketId].yesAmount += output;
            userPosition[msg.sender][thisMarketId].yesBalance += output;
        } else {
            liqudityInfo[thisMarketId].noAmount += output;
            userPosition[msg.sender][thisMarketId].noBalance += output;
        }
        
        liqudityInfo[thisMarketId].collateralAmount += netInput;
        liqudityInfo[thisMarketId].totalFee += fee;
    }

    function sell(Result bet, uint256 amount, uint256 thisMarketId) external {
        require(amount > 0, "Token amount must be positive");
        
        // Check the user's position
        if (bet == IAroundMarket.Result.Yes) {
            require(userPosition[msg.sender][thisMarketId].yesBalance >= amount, "Insufficient YES tokens");
            userPosition[msg.sender][thisMarketId].yesBalance -= amount;
        } else {
            require(userPosition[msg.sender][thisMarketId].noBalance >= amount, "Insufficient NO tokens");
            userPosition[msg.sender][thisMarketId].noBalance -= amount;
        }
        
        // Calculate the output quantity and handling fee
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
        
        // Update the market status
        if (bet == IAroundMarket.Result.Yes) {
            liqudityInfo[thisMarketId].yesAmount -= amount;
        } else {
            liqudityInfo[thisMarketId].noAmount -= amount;
        }
        
        liqudityInfo[thisMarketId].collateralAmount -= uint128(output + fee);
        liqudityInfo[thisMarketId].totalFee += fee;
        
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

        uint256 lpAmount = AroundMath._calculateSharesToMint(
            amount,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].collateralAmount
        );
        
        // Update market state
        liqudityInfo[thisMarketId].yesAmount += yesShare;
        liqudityInfo[thisMarketId].noAmount += noShare;
        liqudityInfo[thisMarketId].collateralAmount += amount;
        liqudityInfo[thisMarketId].totalLp += lpAmount;
        
        // Update user position
        userPosition[msg.sender][thisMarketId].lp += lpAmount;
        userPosition[msg.sender][thisMarketId].yesBalance += yesShare;
        userPosition[msg.sender][thisMarketId].noBalance += noShare;
    }

    function removeLiquidity(uint256 thisMarketId, uint256 lpShare) external {
        require(block.timestamp + 1 hours < marketInfo[thisMarketId].endTime, "Market preparation is over.");
        require(lpShare > 0 && userPosition[msg.sender][thisMarketId].lp >= lpShare, "Invalid liquidity share");
        
        // Calculate the due share of collateral tokens and transaction fees
        (uint128 collateralAmount, uint128 feeShare) = AroundMath._calculateLiquidityWithdrawal(
            lpShare,
            liqudityInfo[thisMarketId].collateralAmount,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].totalFee
        );
        
        require(collateralAmount > 0, "No collateral to withdraw");
        
        // Calculate the number of YES and NO tokens that should be reduced
        (uint256 yesReduction, uint256 noReduction) = AroundMath._calculateLiquidityShares(
            lpShare,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
        
        // Update the liquidity status
        liqudityInfo[thisMarketId].yesAmount -= yesReduction;
        liqudityInfo[thisMarketId].noAmount -= noReduction;
        liqudityInfo[thisMarketId].collateralAmount -= collateralAmount;
        liqudityInfo[thisMarketId].totalLp -= lpShare;
        
        // Update the balance of handling fee
        if (feeShare > 0) {
            liqudityInfo[thisMarketId].totalFee -= feeShare;
        }
        
        // Update the user's position
        userPosition[msg.sender][thisMarketId].lp -= lpShare;
        
        // Transfer the collateral tokens and share the transaction fees with the users
        IERC20(marketInfo[thisMarketId].collateral).safeTransfer(msg.sender, collateralAmount + feeShare);
    }

    function redeemWinnings(uint256 thisMarketId) external returns (uint256 winnings) {
        require(block.timestamp > marketInfo[thisMarketId].endTime + 1 hours, "The review has not been completed.");
        UserPosition memory position = userPosition[msg.sender][thisMarketId];
        require(position.yesBalance > 0 || position.noBalance > 0 || position.lp > 0, "No position");
        
        // Calculate the token earnings
        if (marketInfo[thisMarketId].result == Result.Yes) { 
            if (position.yesBalance > 0) {
                winnings = (position.yesBalance * liqudityInfo[thisMarketId].collateralAmount) / liqudityInfo[thisMarketId].yesAmount;
            }
        } else { // NO wins
            if (position.noBalance > 0) {
                winnings = (position.noBalance * liqudityInfo[thisMarketId].collateralAmount) / liqudityInfo[thisMarketId].noAmount;
            }
        }
        
        // Liquidity provider returns (redemption proportionally)
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
        
        // clear
        delete userPosition[msg.sender][thisMarketId];
    }
    
    // View liquidity value
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
    
    // Estimated removal of liquidity
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
    
    function getYesPrice(uint256 thisMarketId) public view returns (uint256) {
        return AroundMath._calculateYesPrice(
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount,
            liqudityInfo[thisMarketId].virtualLiquidity,
            marketInfo[thisMarketId].result
        );
    }
    
    function getNoPrice(uint256 thisMarketId) public view returns (uint256) {
        return 1e18 - getYesPrice(thisMarketId);
    }

}