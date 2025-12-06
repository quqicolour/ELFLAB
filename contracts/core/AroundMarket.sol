// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {AroundMath} from "../libraries/AroundMath.sol";
import {AroundLibrary} from "../libraries/AroundLibrary.sol";
import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {IAroundPool} from "../interfaces/IAroundPool.sol";
import {IAroundPoolFactory} from "../interfaces/IAroundPoolFactory.sol";
import {IEchoOptimisticOracle} from "../interfaces/IEchoOptimisticOracle.sol";
import {IAroundError} from "../interfaces/IAroundError.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract AroundMarket is IAroundMarket, IAroundError {

    using SafeERC20 for IERC20;

    uint32 private constant RATE = 100_000;
    uint256 public constant Min_Lucky_Volume = 1000;
    uint16 private DefaultOfficialFee = 150;
    uint16 private DefaultLiquidityFee = 150;
    uint16 private DefaultOracleFee = 100;
    uint16 private DefaultLuckyFee = 100;
    uint16 private DefaultCreatorFee = 100;
    uint16 private DefaultTotalFee = 600;
    uint32 private DefaultVirtualLiquidity = 100_000;

    uint256 public marketId;

    address public elfiNFT;
    address public feeReceiver;
    address public aroundPoolFactory;
    address public oracle;
    bool public isInitialize;

    mapping(uint256 => FeeInfo) private feeInfo;
    mapping(uint256 => MarketInfo) private marketInfo;
    mapping(uint256 => LiqudityInfo) private liqudityInfo;
    mapping(address => mapping(uint256 => UserPosition)) private userPosition;

    mapping(uint256 => mapping(uint64 => address)) public raffleTicketToUser;
    mapping(address => TokenInfo) public tokenInfo;

    function initialize(address thisAroundPoolFactory, address thisOracle) external {
        if(isInitialize) {
            revert AlreadyInitialize();
        }
        aroundPoolFactory = thisAroundPoolFactory;
        oracle = thisOracle;
        isInitialize = true;
    }

    function changeDefaultVirtualLiquidity(uint32 newDefaultVirtualLiquidity) external {
        DefaultVirtualLiquidity = newDefaultVirtualLiquidity;
    }

    function setMarketOpenAave(uint256 thisMarketId, bool state) external {
        marketInfo[thisMarketId].marketState.ifOpenAave = state;
    }

    function setFeeInfo(
        PackedBaseFees calldata baseFee
    ) external {
        DefaultOfficialFee =  baseFee.officialFee;
        DefaultLuckyFee = baseFee.luckyFee;
        DefaultOracleFee = baseFee.oracleFee;
        DefaultCreatorFee = baseFee.creatorFee;
        DefaultLiquidityFee = baseFee.liquidityFee;
        DefaultTotalFee = DefaultOfficialFee + DefaultLuckyFee + 
        DefaultOracleFee + DefaultCreatorFee + DefaultLiquidityFee;
    }

    function setTokenInfo(
        address token, 
        bool state,
        uint128 amount
    ) external {
        tokenInfo[token] = TokenInfo({
            valid: state,
            guaranteeAmount: amount
        });
    }

    function createMarket(
        CreateMarketParams calldata params
    ) external {
        uint8 decimals = _getDecimals(params.collateral);
        uint64 currentTime = uint64(block.timestamp);
        uint64 endTime = currentTime + params.period;
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
            feeInfo[marketId] = FeeInfo({
                officialFee: DefaultOfficialFee,
                luckyFee: DefaultLiquidityFee,
                oracleFee: DefaultOracleFee,
                liquidityFee: DefaultLuckyFee,
                creatorFee: DefaultCreatorFee,
                totalFee: DefaultTotalFee
            });
            marketInfo[marketId] = MarketInfo({
                result: Result.Pending,
                marketState: MarketState({
                    ifOpenAave: false,
                    locked: false,
                    valid: true
                }),
                startTime: currentTime,
                endTime: endTime,
                totalRaffleTicket: 0,
                collateral: params.collateral,
                creator: msg.sender,
                questInfo: newQuestInfo
            });
            liqudityInfo[marketId].virtualLiquidity = uint128(actualVirtualAmount);
            IEchoOptimisticOracle(oracle).injectQuest(marketId, params.quest);
        }
        marketId++;
    }

    function buy(Result bet, uint128 amount, uint256 thisMarketId) external {
        _checkZeroAmount(amount);
        //TODO
        _checkMarketIfClosed(thisMarketId);

        // Transfer fund
        {
            uint128 oracleFee = amount * getFeeInfo(thisMarketId).oracleFee / RATE;
            uint128 officialFee = amount * getFeeInfo(thisMarketId).officialFee / RATE;
            uint128 creatorFee = amount * getFeeInfo(thisMarketId).creatorFee / RATE;
            uint128 luckyFee = amount * getFeeInfo(thisMarketId).luckyFee / RATE;
            uint128 liquidityFee = amount * getFeeInfo(thisMarketId).liquidityFee / RATE;
            uint128 remainAmount = amount - getFeeInfo(thisMarketId).totalFee / RATE;

            _transferFee(
                getMarketInfo(thisMarketId).collateral,
                thisMarketId,
                oracleFee,
                creatorFee,
                officialFee
            );
            
            //Transfer fund to around
            IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(
                msg.sender, 
                _getPoolInfo(thisMarketId).aroundPool, 
                remainAmount + luckyFee + liquidityFee
            );
            //inject aroundPool
            _injectAroundPool(
                _getPoolInfo(thisMarketId).aroundPool,
                remainAmount, 
                luckyFee,
                liquidityFee
            );
        }
        uint8 decimals = _getDecimals(getMarketInfo(thisMarketId).collateral);
        uint128 netInput;
        // Calculate the net input (minus handling fees)
        (netInput, ) = AroundMath._calculateNetInput(getFeeInfo(thisMarketId).totalFee, amount);
        
        // Calculate the output quantity and handling fee
        (uint256 output, uint128 fee) = AroundMath._calculateBuyOutput(
            bet,
            getFeeInfo(thisMarketId).totalFee,
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
                userPosition[msg.sender][thisMarketId].raffleTicketNumber = number;
            }
        }
    }

    function sell(Result bet, uint256 amount, uint256 thisMarketId) external {
        _checkZeroAmount(amount);

        //TODO
        _checkMarketIfClosed(thisMarketId);

        uint8 decimals = _getDecimals(getMarketInfo(thisMarketId).collateral);
        uint128 fee;
        uint256 output;
        // Calculate the output quantity and handling fee
        (output, fee) = AroundMath._calculateSellOutput(
            bet,
            getFeeInfo(thisMarketId).totalFee,
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
        uint128 creatorFee;
        if(fee > 0) {
            officialFee = fee * getFeeInfo(thisMarketId).officialFee / getFeeInfo(thisMarketId).totalFee;
            oracleFee = fee * getFeeInfo(thisMarketId).oracleFee / getFeeInfo(thisMarketId).totalFee;
            creatorFee = fee * getFeeInfo(thisMarketId).creatorFee / getFeeInfo(thisMarketId).totalFee;
            _transferFee(
                getMarketInfo(thisMarketId).collateral,
                thisMarketId,
                oracleFee,
                creatorFee,
                officialFee
            );
        }

        //Touch aroundPool
        _touchAroundPool(
            false,
            _getPoolInfo(thisMarketId).aroundPool,
            address(this),
            output + fee - officialFee - oracleFee - creatorFee
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
        _checkLiquidityWayIfClosed(thisMarketId);
        _checkZeroAmount(amount);
        
        //Transfer to aroundPool
        IERC20(getMarketInfo(thisMarketId).collateral).safeTransferFrom(
            msg.sender, 
            _getPoolInfo(thisMarketId).aroundPool, 
            amount
        );
        //inject aroundPool
        _injectAroundPool(
            _getPoolInfo(thisMarketId).aroundPool,
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
        _checkLiquidityWayIfClosed(thisMarketId);
        if(lpShare == 0 || getUserPosition(msg.sender, thisMarketId).lp < lpShare){
            revert InvalidLpShare();
        }
        
        // Calculate the due share of collateral tokens and transaction fees
        (uint128 collateralAmount, uint128 liquidityFeeShare) = AroundMath._calculateLiquidityWithdrawal(
            getLiqudityInfo(thisMarketId).liquidityFeeAmount,
            getUserPosition(msg.sender, thisMarketId).collateralAmount,
            lpShare,
            getUserPosition(msg.sender, thisMarketId).lp,
            getLiqudityInfo(thisMarketId).totalLp
        );
        _checkZeroAmount(collateralAmount + liquidityFeeShare);
        
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
        _touchAroundPool(
            false,
            _getPoolInfo(thisMarketId).aroundPool,
            msg.sender,
            collateralAmount + liquidityFeeShare
        );
    }

    // TODO  allocates fees and withdraws all funds from aave to AroundPool
    function touchOracle(uint256 thisMarketId) external {

    }

    function redeemWinnings(uint256 thisMarketId) external returns (uint256 winnings) {
        if(block.timestamp <= getMarketInfo(thisMarketId).endTime + 2 hours){
            revert NotWithdrawTime();
        }
        // UserPosition memory position = userPosition[msg.sender][thisMarketId];
        if(
            getUserPosition(msg.sender, thisMarketId).yesBalance == 0 && 
            getUserPosition(msg.sender, thisMarketId).noBalance == 0 && 
            getUserPosition(msg.sender, thisMarketId).lp == 0
        ){
            revert ZeroAmount();
        }
        
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
        
        _checkZeroAmount(winnings);

        //Touch aroundPool
        _touchAroundPool(
            true,
            _getPoolInfo(thisMarketId).aroundPool,
            msg.sender,
            winnings
        );
        // clear
        delete userPosition[msg.sender][thisMarketId];
    }

    function _transferFee(
        address _collateral,
        uint256 _thisMarketId,
        uint128 _oracleFee,
        uint128 _creatorFee,
        uint128 _officialFee
    ) private {
        IERC20(_collateral).safeTransferFrom(msg.sender, oracle, _oracleFee);
        IEchoOptimisticOracle(oracle).injectFee(_thisMarketId, _oracleFee);
            //Creator fee
        IERC20(_collateral).safeTransferFrom(
            msg.sender, 
            getMarketInfo(_thisMarketId).creator, 
            _creatorFee
        );
            //Official fee
        IERC20(_collateral).safeTransferFrom(msg.sender, feeReceiver, _officialFee);
    }

    function _injectAroundPool(
        address _aroundPool,
        uint128 _amountIn,
        uint128 _luckyFee,
        uint128 _liquidityFee
    ) private {
        (bool suc, ) = _aroundPool.call(abi.encodeCall(
            IAroundPool(_aroundPool).deposite,
            (_amountIn, _luckyFee, _liquidityFee)
        ));
        if(suc == false) {revert TouchAroundErr();}
    }

    function _touchAroundPool(
        bool _ifEnd, 
        address _aroundPool,
        address _receiver, 
        uint256 _value
    ) private {
        (bool suc, ) = _aroundPool.call(abi.encodeCall(
            IAroundPool(_aroundPool).touch,
            (_ifEnd, _receiver, _value)
        ));
        if(suc == false) {revert TouchAroundErr();}
    }

    function _checkLiquidityWayIfClosed(uint256 _thisMarketId) private view {
        if(block.timestamp + 1 hours >= getMarketInfo(_thisMarketId).endTime) {
            revert LiquidityWayClosed();
        }
    }

    function _checkMarketIfClosed(uint256 _thisMarketId) private view {
        if(block.timestamp >= getMarketInfo(_thisMarketId).endTime) {
            revert MarketClosed();
        }
    }

    function _checkZeroAmount(uint256 _amount) private pure {
        if(_amount == 0) {
            revert ZeroAmount();
        }
    }

    function _getPoolInfo(uint256 thisMarketId) private view returns (IAroundPoolFactory.PoolInfo memory thisPoolInfo) {
        thisPoolInfo = IAroundPoolFactory(aroundPoolFactory).getPoolInfo(thisMarketId);
    }

    function _getDecimals(address token) private view returns (uint8 thisDecimals) {
        thisDecimals = IERC20Metadata(token).decimals();
    }

    function getFeeInfo(uint256 thisMarketId) public view returns (FeeInfo memory thisFeeInfo) {
        thisFeeInfo = feeInfo[thisMarketId];
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