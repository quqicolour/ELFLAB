// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {AroundMath} from "../libraries/AroundMath.sol";
import {AroundLibrary} from "../libraries/AroundLibrary.sol";
import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {IAroundPool} from "../interfaces/IAroundPool.sol";
import {IInsurancePool} from "../interfaces/IInsurancePool.sol";
import {IAroundPoolFactory} from "../interfaces/IAroundPoolFactory.sol";
import {IAroundError} from "../interfaces/IAroundError.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AroundMarket is IAroundMarket, IAroundError {

    using SafeERC20 for IERC20;

    uint32 private constant RATE = 100_000;
    uint256 public constant Min_Lucky_Volume = 1000;
    uint16 public DefaultOfficialFee = 150;
    uint16 public DefaultLiquidityFee = 150;
    uint16 public DefaultOracleFee = 100;
    uint16 public DefaultLuckyFee = 100;
    uint16 public DefaultInsuranceFee = 100;
    uint16 public DefaultTotalFee = 600;
    uint32 public DefaultVirtualLiquidity = 100_000;

    uint256 public marketId;

    address public oracle;
    address public elfiNFT;
    address public feeReceiver;
    address public aroundPoolFactory;
    bool public isInitialize;
    bool public openAave;

    mapping(uint256 => MarketInfo) private marketInfo;
    mapping(uint256 => LiqudityInfo) private liqudityInfo;
    mapping(address => mapping(uint256 => UserPosition)) private userPosition;

    mapping(uint256 => mapping(uint64 => address)) public raffleTicketToUser;

    mapping(address => TokenInfo) public tokenInfo;
    mapping(uint256 => FeeInfo) public feeInfo;

    function initialize(address _aroundPoolFactory) external {
        if(isInitialize) {
            revert AlreadyInitialize();
        }
        aroundPoolFactory = _aroundPoolFactory;
        isInitialize = true;
    }

    function changeDefaultVirtualLiquidity(uint32 newDefaultVirtualLiquidity) external {
        DefaultVirtualLiquidity = newDefaultVirtualLiquidity;
    }

    function setOpenAave(bool state) external {
        openAave = state;
    }

    function setFeeInfo(
        uint16 newOfficialFee,
        uint16 newLuckyFee,
        uint16 newOracleFee,
        uint16 newInsuranceFee,
        uint16 newLiquidityFee
    ) external {
        DefaultOfficialFee =  newOfficialFee;
        DefaultLuckyFee = newLuckyFee;
        DefaultOracleFee = newOracleFee;
        DefaultInsuranceFee = newInsuranceFee;
        DefaultLiquidityFee = newLiquidityFee;
        DefaultTotalFee = DefaultOfficialFee + DefaultLuckyFee + 
        DefaultOracleFee + DefaultInsuranceFee + DefaultLiquidityFee;
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
        AroundLibrary.CreateMarketParams calldata params
    ) external {
        uint8 decimals = _getDecimals(params.collateral);
        uint64 currentTime = uint64(block.timestamp);
        uint64 endTime = currentTime + params.period;
        require(decimals > 0);
        if(tokenInfo[params.collateral].valid == false) {
            revert InvalidToken();
        }
        //create fee
        if(tokenInfo[params.collateral].guaranteeAmount > 0){
            IERC20(params.collateral).safeTransferFrom(
                msg.sender, 
                feeReceiver, 
                100 * 10 ** decimals
            );
        }

        {
            uint256 actualVirtualAmount = AroundLibrary._getGuardedAmount(
                decimals,
                params.expectVirtualLiquidity,
                DefaultVirtualLiquidity
            );
            QuestInfo memory newQuestInfo = QuestInfo({
                quest: params.quest,
                resultData: ""
            });
            MarketState memory newMarketState = MarketState({
                ifOpenAave: openAave,
                locked: false,
                valid: true
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
                marketState: newMarketState,
                startTime: currentTime,
                endTime: endTime,
                totalRaffleTicket: 0,
                collateral: params.collateral,
                creator: msg.sender,
                questInfo: newQuestInfo
            });
            liqudityInfo[marketId].virtualLiquidity = uint128(actualVirtualAmount);
        }
        marketId++;
    }

    function buy(Result bet, uint128 amount, uint256 thisMarketId) external {
        if(amount == 0){
            revert ZeroAmount();
        }
        //TODO
        // if(block.timestamp >= getMarketInfo(thisMarketId).endTime) {
        //     revert MarketAlreadyEnd();
        // }

        // Transfer fund
        {
            uint128 oracleFee = amount * feeInfo[thisMarketId].oracleFee / RATE;
            uint128 officialFee = amount * feeInfo[thisMarketId].officialFee / RATE;
            uint128 insuranceFee = amount * feeInfo[thisMarketId].insuranceFee / RATE;
            uint128 luckyFee = amount * feeInfo[thisMarketId].luckyFee / RATE;
            uint128 liquidityFee = amount * feeInfo[thisMarketId].liquidityFee / RATE;
            uint128 remainAmount = amount - oracleFee - officialFee - insuranceFee - luckyFee - liquidityFee;
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
                remainAmount + luckyFee + liquidityFee
            );
            IAroundPool(_getPoolInfo(thisMarketId).aroundPool).deposite(
                remainAmount, 
                luckyFee,
                liquidityFee
            );
        }
        uint8 decimals = _getDecimals(getMarketInfo(thisMarketId).collateral);
        require(decimals > 0);
        uint128 netInput;
        // Calculate the net input (minus handling fees)
        (netInput, ) = AroundMath._calculateNetInput(feeInfo[thisMarketId].totalFee, amount);
        
        // Calculate the output quantity and handling fee
        (uint256 output, uint128 fee) = AroundMath._calculateBuyOutput(
            bet,
            feeInfo[thisMarketId].totalFee,
            amount,
            getLiqudityInfo(thisMarketId).virtualLiquidity,
            getLiqudityInfo(thisMarketId).tradeCollateralAmount + getLiqudityInfo(thisMarketId).lpCollateralAmount,
            getLiqudityInfo(thisMarketId).yesAmount,
            getLiqudityInfo(thisMarketId).noAmount
        );
        
        if(output == 0) {
            revert InvalidOutput();
        }
        
        // Update the liqudity and user balance
        userPosition[msg.sender][thisMarketId].volume += amount;
        if (bet == IAroundMarket.Result.Yes) {
            liqudityInfo[thisMarketId].yesAmount += output;
            userPosition[msg.sender][thisMarketId].yesBalance += output;
        } else {
            liqudityInfo[thisMarketId].noAmount += output;
            userPosition[msg.sender][thisMarketId].noBalance += output;
        }
        
        //Update liqudity
        liqudityInfo[thisMarketId].tradeCollateralAmount += netInput;
        liqudityInfo[thisMarketId].totalFee += fee;

        //Check raffle ticket
        if(getUserPosition(msg.sender, thisMarketId).volume >= Min_Lucky_Volume * 10 ** decimals) {
            marketInfo[thisMarketId].totalRaffleTicket++;
            if(userPosition[msg.sender][thisMarketId].raffleTicketNumber == 0){
                uint64 number = getMarketInfo(thisMarketId).totalRaffleTicket;
                raffleTicketToUser[thisMarketId][number] = msg.sender;
                userPosition[msg.sender][thisMarketId].raffleTicketNumber = getMarketInfo(thisMarketId).totalRaffleTicket;
            }
        }
    }

    function sell(Result bet, uint256 amount, uint256 thisMarketId) external {
        if(amount == 0){
            revert ZeroAmount();
        }
        uint8 decimals = _getDecimals(getMarketInfo(thisMarketId).collateral);
        require(decimals > 0);

        //TODO
        // if(block.timestamp >= getMarketInfo(thisMarketId).endTime) {
        //     revert MarketAlreadyEnd();
        // }
        
        // Calculate the output quantity and handling fee
        (uint256 output, uint128 fee) = AroundMath._calculateSellOutput(
            bet,
            feeInfo[thisMarketId].totalFee,
            getLiqudityInfo(thisMarketId).virtualLiquidity,
            getLiqudityInfo(thisMarketId).tradeCollateralAmount + getLiqudityInfo(thisMarketId).lpCollateralAmount,
            amount,
            getLiqudityInfo(thisMarketId).yesAmount,
            getLiqudityInfo(thisMarketId).noAmount
        );
        userPosition[msg.sender][thisMarketId].volume += (output + fee);
        
        if(getLiqudityInfo(thisMarketId).tradeCollateralAmount < output + fee) {
            revert InvalidOutput();
        }

        // update the user's position and liqudityInfo 
        if (bet == IAroundMarket.Result.Yes) {
            if(getUserPosition(msg.sender, thisMarketId).yesBalance < amount) {
                revert InsufficientBalance();
            }
            userPosition[msg.sender][thisMarketId].yesBalance -= amount;
            liqudityInfo[thisMarketId].yesAmount -= amount;
        } else {
            if(getUserPosition(msg.sender, thisMarketId).noBalance < amount) {
                revert InsufficientBalance();
            }
            userPosition[msg.sender][thisMarketId].noBalance -= amount;
            liqudityInfo[thisMarketId].noAmount -= amount;
        }
        
        //update
        liqudityInfo[thisMarketId].tradeCollateralAmount -= uint128(output + fee);
        liqudityInfo[thisMarketId].totalFee += fee;
        uint128 officialFee;
        uint128 oracleFee;

        if(fee > 0) {
            officialFee = fee * feeInfo[thisMarketId].officialFee / feeInfo[thisMarketId].totalFee;
            oracleFee = fee * feeInfo[thisMarketId].oracleFee / feeInfo[thisMarketId].totalFee;
            //transfer to official
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransfer(feeReceiver, officialFee);
            //transfer to oracle
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransfer(oracle, oracleFee);
        }

        //Touch aroundPool
        IAroundPool(_getPoolInfo(thisMarketId).aroundPool).touch(
            false,
            address(this),
            output + fee - officialFee - oracleFee
        );
        //transfer to user
        IERC20(getMarketInfo(thisMarketId).collateral).safeTransfer(msg.sender, output);

        //Check raffle ticket
        if(getUserPosition(msg.sender, thisMarketId).volume >= Min_Lucky_Volume * 10 ** decimals) {
            marketInfo[thisMarketId].totalRaffleTicket++;
            userPosition[msg.sender][thisMarketId].raffleTicketNumber = getMarketInfo(thisMarketId).totalRaffleTicket;
        }
    }

    function addLiquidity(uint128 amount, uint256 thisMarketId) external {
        require(block.timestamp + 1 hours < getMarketInfo(thisMarketId).endTime, "Add liquidity is closed.");
        if(amount == 0){
            revert ZeroAmount();
        }
        
        //Transfer to aroundPool
        IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(
            msg.sender, 
            _getPoolInfo(thisMarketId).aroundPool, 
            amount
        );
        IAroundPool(_getPoolInfo(thisMarketId).aroundPool).deposite(
            amount, 
            0,
            0
        );
        
        // Get yes and no share
        (uint256 yesShare, uint256 noShare) = AroundMath._calculateLiquidityShares(
            amount,
            getLiqudityInfo(thisMarketId).totalLp,
            getLiqudityInfo(thisMarketId).yesAmount,
            getLiqudityInfo(thisMarketId).noAmount
        );

        uint256 lpAmount = AroundMath._calculateSharesToMint(
            amount,
            getLiqudityInfo(thisMarketId).tradeCollateralAmount + getLiqudityInfo(thisMarketId).lpCollateralAmount,
            getLiqudityInfo(thisMarketId).totalLp
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
        require(block.timestamp + 1 hours < getMarketInfo(thisMarketId).endTime, "Market removeLiquidity is over.");
        require(lpShare > 0 && getUserPosition(msg.sender, thisMarketId).lp >= lpShare, "Invalid liquidity share");
        
        // Calculate the due share of collateral tokens and transaction fees
        (uint128 collateralAmount, uint128 liquidityFeeShare) = AroundMath._calculateLiquidityWithdrawal(
            getLiqudityInfo(thisMarketId).liquidityFeeAmount,
            getUserPosition(msg.sender, thisMarketId).collateralAmount,
            lpShare,
            getUserPosition(msg.sender, thisMarketId).lp,
            getLiqudityInfo(thisMarketId).totalLp
        );
        require(collateralAmount + liquidityFeeShare > 0, "No collateral to withdraw");
        
        // Calculate the number of YES and NO tokens that should be reduced
        (uint256 yesReduction, uint256 noReduction) = AroundMath._calculateLiquidityShares(
            lpShare,
            getLiqudityInfo(thisMarketId).totalLp,
            getLiqudityInfo(thisMarketId).yesAmount,
            getLiqudityInfo(thisMarketId).noAmount
        );
        
        // Update the liquidity status
        liqudityInfo[thisMarketId].yesAmount -= yesReduction;
        liqudityInfo[thisMarketId].noAmount -= noReduction;
        liqudityInfo[thisMarketId].lpCollateralAmount -= collateralAmount;
        liqudityInfo[thisMarketId].totalLp -= lpShare;
        
        // Update the balance of handling fee
        if (liquidityFeeShare > 0) {
            liqudityInfo[thisMarketId].totalFee -= liquidityFeeShare;
        }
        
        // Update the user's position
        userPosition[msg.sender][thisMarketId].lp -= lpShare;
        userPosition[msg.sender][thisMarketId].collateralAmount -= collateralAmount;

        //Touch aroundPool
        IAroundPool(_getPoolInfo(thisMarketId).aroundPool).touch(
            false,
            msg.sender,
            collateralAmount + liquidityFeeShare
        );
    }

    // TODO  allocates fees and withdraws all funds from aave to AroundPool
    function touchOracle(uint256 thisMarketId) external {

    }

    function redeemWinnings(uint256 thisMarketId) external returns (uint256 winnings) {
        require(block.timestamp > getMarketInfo(thisMarketId).endTime + 2 hours, "The review has not been completed.");
        // UserPosition memory position = userPosition[msg.sender][thisMarketId];
        require(
            getUserPosition(msg.sender, thisMarketId).yesBalance > 0 || 
            getUserPosition(msg.sender, thisMarketId).noBalance > 0 || 
            getUserPosition(msg.sender, thisMarketId).lp > 0, "No position"
        );
        
        // Calculate the token earnings
        if (getMarketInfo(thisMarketId).result == Result.Yes) {  
            if (getUserPosition(msg.sender, thisMarketId).yesBalance > 0) {
                winnings = getUserPosition(msg.sender, thisMarketId).yesBalance * getLiqudityInfo(thisMarketId).tradeCollateralAmount / 
                getLiqudityInfo(thisMarketId).yesAmount;
            }
        } else if(getMarketInfo(thisMarketId).result == Result.No) {
            if (getUserPosition(msg.sender, thisMarketId).noBalance > 0) {
                winnings = getUserPosition(msg.sender, thisMarketId).noBalance * getLiqudityInfo(thisMarketId).tradeCollateralAmount / 
                getLiqudityInfo(thisMarketId).noAmount;
            }
        } else {
            revert InvalidState();
        }
        
        // Liquidity provider returns (redemption proportionally)
        if (getUserPosition(msg.sender, thisMarketId).lp > 0) {
            (uint128 liquidityValue, uint128 feeShare) = AroundMath._calculateLiquidityWithdrawal(
                getLiqudityInfo(thisMarketId).totalFee,
                getUserPosition(msg.sender, thisMarketId).collateralAmount,
                getUserPosition(msg.sender, thisMarketId).lp,
                getUserPosition(msg.sender, thisMarketId).lp,
                getLiqudityInfo(thisMarketId).totalLp
            );
            winnings += (liquidityValue + feeShare);
        }
        
        require(winnings > 0, "No winnings");

        //Touch aroundPool
        IAroundPool(_getPoolInfo(thisMarketId).aroundPool).touch(
            true,
            msg.sender,
            winnings
        );
        // clear
        delete userPosition[msg.sender][thisMarketId];
    }

    function _getPoolInfo(uint256 thisMarketId) private view returns (IAroundPoolFactory.PoolInfo memory thisPoolInfo) {
        thisPoolInfo = IAroundPoolFactory(aroundPoolFactory).getPoolInfo(thisMarketId);
    }

    function _getDecimals(address token) private view returns (uint8 thisDecimals) {
        thisDecimals = IERC20Metadata(token).decimals();
    }

    function getUserPosition(address user, uint256 thisMarketId) public view returns (UserPosition memory thisUserPosition) {
        thisUserPosition = userPosition[user][thisMarketId];
    }

    function getMarketInfo(uint256 thisMarketId) public view returns (MarketInfo memory thisMarketInfo) {
        thisMarketInfo = marketInfo[thisMarketId];
    }

    function getLiqudityInfo(uint256 thisMarketId) public view returns (LiqudityInfo memory thisLiqudityInfo) {
        thisLiqudityInfo = liqudityInfo[thisMarketId];
    }

}