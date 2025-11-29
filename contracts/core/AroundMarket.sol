// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {AroundMath} from "../libraries/AroundMath.sol";
import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {IAroundPool} from "../interfaces/IAroundPool.sol";
import {IInsurancePool} from "../interfaces/IInsurancePool.sol";
import {IAroundPoolFactory} from "../interfaces/IAroundPoolFactory.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AroundMarket is IAroundMarket {

    using SafeERC20 for IERC20;
    uint256 public marketId;

    address public oracle;
    address public elfiNFT;
    address public feeReceiver;
    address public aroundPoolFactory;
    bool public isInitialize;

    uint16 private constant DefaultOfficialFee = 150;
    uint16 private constant DefaultLiquidityFee = 150;
    uint16 private constant DefaultOracleFee = 100;
    uint16 private constant DefaultLuckyFee = 100;
    uint16 private constant DefaultInsuranceFee = 100;
    uint16 private constant DefaultTotalFee = 600;
    uint32 private constant RATE = 100_000;

    mapping(address => TokenInfo) public tokenInfo;

    mapping(uint256 => MarketInfo) private marketInfo;

    mapping(uint256 => LiqudityInfo) private liqudityInfo;

    mapping(address => mapping(uint256 => UserPosition)) public userPosition;

    mapping(uint256 => FeeInfo) public feeInfo;

    function initialize(address _aroundPoolFactory) external {
        require(isInitialize == false, "Already initialize");
        aroundPoolFactory = _aroundPoolFactory;
        isInitialize = true;
    }

    function setFeeInfo(
        uint16 newOfficialFee,
        uint16 newLuckyFee,
        uint16 newOracleFee,
        uint16 newInsuranceFee,
        uint16 newLiquidityFee,
        uint256 thisId
    ) external {
        feeInfo[thisId].officialFee =  newOfficialFee;
        feeInfo[thisId].luckyFee = newLuckyFee;
        feeInfo[thisId].oracleFee = newOracleFee;
        feeInfo[thisId].insuranceFee = newInsuranceFee;
        feeInfo[thisId].liquidityFee = newLiquidityFee;
        emit SetFeeInfo(thisId);
    }

    function batchAddTokenInfo(
        address[] calldata tokens, 
        bool[] calldata status,
        uint128[] calldata amounts
    ) external {
        unchecked {
            for(uint256 i; i<tokens.length; i++) {
                tokenInfo[tokens[i]] = TokenInfo({
                    valid: status[i],
                    guaranteeAmount: amounts[i]
                });
            }
        }
    }

    function createMarket(
        uint32 _period,
        uint128 _virtualLiquidity,
        address _collateral,
        string calldata _quest
    ) external {
        uint64 _currentTime = uint64(block.timestamp);
        uint64 _endTime = _currentTime + _period;
        uint128 guaranteeAmount = tokenInfo[_collateral].guaranteeAmount;
        require(tokenInfo[_collateral].valid, "Invalid token");
        //create fee
        if(guaranteeAmount > 0){
            IERC20(_collateral).safeTransferFrom(msg.sender, feeReceiver, 100 * 10 ** IERC20Metadata(_collateral).decimals());
        }

        QuestInfo memory newQuestInfo = QuestInfo({
            quest: _quest,
            resultData: ""
        });
        feeInfo[marketId] = FeeInfo({
            officialFee: DefaultOfficialFee,
            luckyFee: DefaultLiquidityFee,
            oracleFee: DefaultOracleFee,
            liquidityFee: DefaultLuckyFee,
            insuranceFee: DefaultInsuranceFee,
            totalFee: DefaultTotalFee
        });
        marketInfo[marketId] = MarketInfo({
            result: Result.Pending,
            startTime: _currentTime,
            endTime: _endTime,
            collateral: _collateral,
            creator: msg.sender,
            questInfo: newQuestInfo
        });
        liqudityInfo[marketId] = LiqudityInfo({
            virtualLiquidity: _virtualLiquidity,
            tradeCollateralAmount: 0,
            lpCollateralAmount: 0,
            totalLp: 0,
            totalFee: 0,
            yesAmount: 0,
            noAmount: 0
        });
        marketId++;
    }

    function buy(Result bet, uint128 amount, uint256 thisMarketId) external {
        require(amount > 0, "Input amount must be positive");
        // Transfer fund
        {
            uint128 oracleFee = amount * feeInfo[thisMarketId].oracleFee / RATE;
            uint128 officialFee = amount * feeInfo[thisMarketId].officialFee / RATE;
            uint128 insuranceFee = amount * feeInfo[thisMarketId].insuranceFee / RATE;
            uint128 luckyFee = amount * feeInfo[thisMarketId].luckyFee / RATE;
            uint128 remainAmount = amount - oracleFee - officialFee - insuranceFee - luckyFee;
            //Oracle fee
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(msg.sender, oracle, oracleFee);
            //Official fee
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(msg.sender, feeReceiver, officialFee);
            //Insurance fee
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(msg.sender, _getPoolInfo(thisMarketId).insurancePool, insuranceFee);
            //Transfer fund to around
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(
                msg.sender, 
                _getPoolInfo(thisMarketId).aroundPool, 
                remainAmount + luckyFee
            );
            IAroundPool(_getPoolInfo(thisMarketId).aroundPool).deposite(remainAmount, luckyFee);
        }

        // Calculate the net input (minus handling fees)
        (uint128 netInput, ) = AroundMath._calculateNetInput(feeInfo[thisMarketId].totalFee, amount);
        
        // Calculate the output quantity and handling fee
        (uint256 output, uint128 fee) = AroundMath._calculateBuyOutput(
            bet,
            feeInfo[thisMarketId].totalFee,
            amount,
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].tradeCollateralAmount + liqudityInfo[thisMarketId].lpCollateralAmount,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
        
        require(output > 0, "Insufficient output");
        
        // Update the market status
        if (bet == IAroundMarket.Result.Yes) {
            liqudityInfo[thisMarketId].yesAmount += output;
            userPosition[msg.sender][thisMarketId].yesBalance += output;
        } else {
            liqudityInfo[thisMarketId].noAmount += output;
            userPosition[msg.sender][thisMarketId].noBalance += output;
        }
        
        liqudityInfo[thisMarketId].tradeCollateralAmount += netInput;
        liqudityInfo[thisMarketId].totalFee += fee;
    }

    function sell(Result bet, uint256 amount, uint256 thisMarketId) external {
        require(amount > 0, "Token amount must be positive");
        
        // Calculate the output quantity and handling fee
        (uint256 output, uint128 fee) = AroundMath._calculateSellOutput(
            bet,
            feeInfo[thisMarketId].totalFee,
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].tradeCollateralAmount + liqudityInfo[thisMarketId].lpCollateralAmount,
            amount,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
        
        require(liqudityInfo[thisMarketId].tradeCollateralAmount >= output + fee, "Insufficient output");

        // update the user's position and liqudityInfo 
        if (bet == IAroundMarket.Result.Yes) {
            require(userPosition[msg.sender][thisMarketId].yesBalance >= amount, "Insufficient YES tokens");
            userPosition[msg.sender][thisMarketId].yesBalance -= amount;
            liqudityInfo[thisMarketId].yesAmount -= amount;
        } else {
            require(userPosition[msg.sender][thisMarketId].noBalance >= amount, "Insufficient NO tokens");
            userPosition[msg.sender][thisMarketId].noBalance -= amount;
            liqudityInfo[thisMarketId].noAmount -= amount;
        }
        
        //update
        liqudityInfo[thisMarketId].tradeCollateralAmount -= uint128(output + fee);
        liqudityInfo[thisMarketId].totalFee += fee;

        //TODO touch around pool
        
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
            liqudityInfo[thisMarketId].tradeCollateralAmount + liqudityInfo[thisMarketId].lpCollateralAmount,
            liqudityInfo[thisMarketId].totalLp
        );
        
        // Update market state
        liqudityInfo[thisMarketId].yesAmount += yesShare;
        liqudityInfo[thisMarketId].noAmount += noShare;
        liqudityInfo[thisMarketId].lpCollateralAmount += amount;
        liqudityInfo[thisMarketId].totalLp += lpAmount;
        
        // Update user position
        userPosition[msg.sender][thisMarketId].lp += lpAmount;
        userPosition[msg.sender][thisMarketId].collateralAmount += amount;
    }

    function removeLiquidity(uint256 thisMarketId, uint128 lpShare) external {
        require(block.timestamp + 1 hours < marketInfo[thisMarketId].endTime, "Market preparation is over.");
        require(lpShare > 0 && userPosition[msg.sender][thisMarketId].lp >= lpShare, "Invalid liquidity share");
        
        // Calculate the due share of collateral tokens and transaction fees
        (uint128 collateralAmount, uint128 feeShare) = AroundMath._calculateLiquidityWithdrawal(
            liqudityInfo[thisMarketId].totalFee,
            userPosition[msg.sender][thisMarketId].collateralAmount,
            lpShare,
            userPosition[msg.sender][thisMarketId].lp,
            liqudityInfo[thisMarketId].totalLp
        );
        require(collateralAmount + feeShare> 0, "No collateral to withdraw");
        
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
        liqudityInfo[thisMarketId].lpCollateralAmount -= collateralAmount;
        liqudityInfo[thisMarketId].totalLp -= lpShare;
        
        // Update the balance of handling fee
        if (feeShare > 0) {
            liqudityInfo[thisMarketId].totalFee -= feeShare;
        }
        
        // Update the user's position
        userPosition[msg.sender][thisMarketId].lp -= lpShare;
        userPosition[msg.sender][thisMarketId].collateralAmount -= collateralAmount;
        
        // Transfer the collateral tokens and share the transaction fees with the users
        IERC20(marketInfo[thisMarketId].collateral).safeTransfer(msg.sender, collateralAmount + feeShare);
    }

    // TODO  allocates fees and withdraws all funds from aave to AroundPool
    function touchOracle(uint256 thisMarketId) external {

    }

    function redeemWinnings(uint256 thisMarketId) external returns (uint256 winnings) {
        require(block.timestamp > marketInfo[thisMarketId].endTime + 1 hours, "The review has not been completed.");
        UserPosition memory position = userPosition[msg.sender][thisMarketId];
        require(position.yesBalance > 0 || position.noBalance > 0 || position.lp > 0, "No position");
        
        // Calculate the token earnings
        if (marketInfo[thisMarketId].result == Result.Yes) { 
            if (position.yesBalance > 0) {
                winnings = (position.yesBalance * liqudityInfo[thisMarketId].tradeCollateralAmount) / liqudityInfo[thisMarketId].yesAmount;
            }
        } else if(marketInfo[thisMarketId].result == Result.No) { // NO wins
            if (position.noBalance > 0) {
                winnings = (position.noBalance * liqudityInfo[thisMarketId].tradeCollateralAmount) / liqudityInfo[thisMarketId].noAmount;
            }
        } else {
            revert ("Invalid state");
        }
        
        // Liquidity provider returns (redemption proportionally)
        if (position.lp > 0) {
            (uint128 liquidityValue, uint128 feeShare) = AroundMath._calculateLiquidityWithdrawal(
                liqudityInfo[thisMarketId].totalFee,
                position.collateralAmount,
                position.lp,
                position.lp,
                liqudityInfo[thisMarketId].totalLp
            );
            winnings += (liquidityValue + feeShare);
        }
        
        require(winnings > 0, "No winnings");
        IERC20(marketInfo[thisMarketId].collateral).safeTransfer(msg.sender, winnings);
        
        // clear
        delete userPosition[msg.sender][thisMarketId];
    }

    function _getPoolInfo(uint256 thisMarketId) private view returns (IAroundPoolFactory.PoolInfo memory thisPoolInfo) {
        thisPoolInfo = IAroundPoolFactory(aroundPoolFactory).getPoolInfo(thisMarketId);
    }
    
    // View liquidity value
    function getLiquidityValue(uint256 thisMarketId, address _user) public view returns (uint256 totalValue) {
        UserPosition memory position = userPosition[_user][thisMarketId];
        if (position.lp == 0) return 0;
        
        return AroundMath._calculateLiquidityValue(
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].totalFee,
            position.lp,
            liqudityInfo[thisMarketId].totalLp,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
    }
    
    // Estimated removal of liquidity
    function estimateLiquidityRemoval(uint256 thisMarketId, uint256 lpShare) public view returns (
        uint256 collateralAmount, 
        uint256 feeShare,
        uint256 totalValue
    ) {
        require(lpShare <= userPosition[msg.sender][thisMarketId].lp, "Insufficient total liquidity");
        
        (collateralAmount, feeShare) = AroundMath._calculateLiquidityWithdrawal(
            liqudityInfo[thisMarketId].totalFee,
            userPosition[msg.sender][thisMarketId].collateralAmount,
            lpShare,
            userPosition[msg.sender][thisMarketId].lp,
            liqudityInfo[thisMarketId].totalLp
        );
        
        totalValue = collateralAmount + feeShare;
    }
    
    function getYesPrice(uint256 thisMarketId) public view returns (uint256) {
        return AroundMath._calculateYesPrice(
            marketInfo[thisMarketId].result,
            liqudityInfo[thisMarketId].virtualLiquidity,
            liqudityInfo[thisMarketId].yesAmount,
            liqudityInfo[thisMarketId].noAmount
        );
    }
    
    function getNoPrice(uint256 thisMarketId) public view returns (uint256) {
        return 1e18 - getYesPrice(thisMarketId);
    }

    function getMarketInfo(uint256 thisMarketId) public view returns (MarketInfo memory thisMarketInfo) {
        thisMarketInfo = marketInfo[thisMarketId];
    }

    function getLiqudityInfo(uint256 thisMarketId) public view returns (LiqudityInfo memory thisLiqudityInfo) {
        thisLiqudityInfo = liqudityInfo[thisMarketId];
    }

}