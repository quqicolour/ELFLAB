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

    address private feeReceiver;
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
        address thisCollateral = _getPoolInfo(params.thisMarketId).collateral;
        uint8 decimals = _getDecimals(thisCollateral);
        uint64 currentTime = uint64(block.timestamp);
        uint64 endTime = currentTime + params.period;
        require(params.period > 86400);
        if(tokenInfo[thisCollateral].valid == false) {
            revert InvalidToken();
        }
        //Create market fee
        if(tokenInfo[thisCollateral].guaranteeAmount > 0){
            IERC20(thisCollateral).safeTransferFrom(
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
            feeInfo[params.thisMarketId] = FeeInfo({
                officialFee: DefaultOfficialFee,
                luckyFee: DefaultLiquidityFee,
                oracleFee: DefaultOracleFee,
                liquidityFee: DefaultLuckyFee,
                creatorFee: DefaultCreatorFee,
                totalFee: DefaultTotalFee
            });
            marketInfo[params.thisMarketId] = MarketInfo({
                result: Result.Pending,
                marketState: MarketState({
                    ifOpenAave: false,
                    locked: false,
                    valid: true
                }),
                startTime: currentTime,
                endTime: endTime,
                totalRaffleTicket: 0,
                collateral: thisCollateral,
                creator: msg.sender,
                quest: params.quest
            });
            liqudityInfo[params.thisMarketId].virtualLiquidity = uint128(actualVirtualAmount);
            IEchoOptimisticOracle(oracle).injectQuest(params.thisMarketId, params.quest);
        }
        emit CreateNewMarket(params.thisMarketId, msg.sender);
    }

    function buy(Result bet, uint128 amount, uint256 thisMarketId) external {
        _checkZeroAmount(amount);
        //TODO
        _checkMarketIfClosed(thisMarketId);

        // Transfer fund
        {
            uint128 liquidityFee = amount * getFeeInfo(thisMarketId).totalFee / 
            RATE * getFeeInfo(thisMarketId).liquidityFee / getFeeInfo(thisMarketId).totalFee;
            uint128 remainAmount = amount - amount * getFeeInfo(thisMarketId).totalFee / RATE;
            liqudityInfo[thisMarketId].liquidityFeeAmount += liquidityFee;

            _transferFee(
                getMarketInfo(thisMarketId).collateral,
                amount * getFeeInfo(thisMarketId).totalFee / RATE,
                thisMarketId
            );

            //inject aroundPool
            _injectAroundPool(
                remainAmount,
                liquidityFee,
                thisMarketId
            );
        }
        uint8 decimals = _getDecimals(getMarketInfo(thisMarketId).collateral);
        uint128 netInput;
        // Calculate the net input (minus handling fees)
        (netInput, ) = AroundMath._calculateNetInput(getFeeInfo(thisMarketId).totalFee, amount);
        
        // Calculate the output quantity and handling fee
        (uint256 output, ) = AroundMath._calculateBuyOutput(
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

        //Check raffle ticket
        _updateRaffleTicket(decimals, thisMarketId);
        emit Buy(thisMarketId, msg.sender, bet, amount);
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
        if(fee > 0) {
            _transferFee(
                getMarketInfo(thisMarketId).collateral,
                fee,
                thisMarketId
            );
        }

        {   
            uint128 liquidityFee = fee * getFeeInfo(thisMarketId).liquidityFee / getFeeInfo(thisMarketId).totalFee;
            liqudityInfo[thisMarketId].liquidityFeeAmount += liquidityFee;
            //Touch aroundPool
            _touchAroundPool(
                false,
                getMarketInfo(thisMarketId).marketState.ifOpenAave,
                _getPoolInfo(thisMarketId).aroundPool,
                uint128(output)
            );
        }

        //Check raffle ticket
        _updateRaffleTicket(decimals, thisMarketId);
        emit Sell(thisMarketId, msg.sender, bet, amount);
    }

    function addLiquidity(uint128 amount, uint256 thisMarketId) external {
        _checkLiquidityWayIfClosed(thisMarketId);
        _checkZeroAmount(amount);
        
        //inject aroundPool
        _injectAroundPool(
            amount,
            0,
            thisMarketId
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
        
        // Update liqudityInfo state
        liqudityInfo[thisMarketId].yesAmount += yesShare;
        liqudityInfo[thisMarketId].noAmount += noShare;
        liqudityInfo[thisMarketId].lpCollateralAmount += amount;
        liqudityInfo[thisMarketId].totalLp += lpAmount;
        
        // Update user position
        userPosition[msg.sender][thisMarketId].lp += lpAmount;
        userPosition[msg.sender][thisMarketId].collateralAmount += amount;
        emit AddLiqudity(thisMarketId, msg.sender, amount);
    }

    function removeLiquidity(uint256 thisMarketId, uint128 lpAmount) external {
        _checkLiquidityWayIfClosed(thisMarketId);
        if(lpAmount == 0 || getUserPosition(msg.sender, thisMarketId).lp < lpAmount){
            revert InvalidLpShare();
        }
        
        // Calculate the due share of collateral tokens and transaction fees
        (uint128 collateralAmount, uint128 liquidityFeeShare) = AroundMath._calculateLiquidityWithdrawal(
            getLiqudityInfo(thisMarketId).liquidityFeeAmount,
            getUserPosition(msg.sender, thisMarketId).collateralAmount,
            lpAmount,
            getUserPosition(msg.sender, thisMarketId).lp,
            getLiqudityInfo(thisMarketId).totalLp
        );
        _checkZeroAmount(collateralAmount + liquidityFeeShare);
        
        // Calculate the number of YES and NO tokens that should be reduced
        (uint256 yesReduction, uint256 noReduction) = AroundMath._calculateLiquidityShares(
            lpAmount,
            getLiqudityInfo(thisMarketId).totalLp,
            getLiqudityInfo(thisMarketId).yesAmount,
            getLiqudityInfo(thisMarketId).noAmount
        );
        
        // Update the liquidity status
        liqudityInfo[thisMarketId].yesAmount -= yesReduction;
        liqudityInfo[thisMarketId].noAmount -= noReduction;
        liqudityInfo[thisMarketId].lpCollateralAmount -= collateralAmount;
        liqudityInfo[thisMarketId].totalLp -= lpAmount;
        
        // Update the balance of handling fee
        if (liquidityFeeShare > 0) {
            liqudityInfo[thisMarketId].liquidityFeeAmount -= liquidityFeeShare;
        }
        
        // Update the user's position
        userPosition[msg.sender][thisMarketId].lp -= lpAmount;
        userPosition[msg.sender][thisMarketId].collateralAmount -= collateralAmount;

        //Touch aroundPool
        _touchAroundPool(
            false,
            getMarketInfo(thisMarketId).marketState.ifOpenAave,
            _getPoolInfo(thisMarketId).aroundPool,
            collateralAmount
        );
        emit RemoveLiqudity(thisMarketId, msg.sender, lpAmount);
    }

    function touchAllot(bool ifOpenAave, uint256 thisMarketId) external {
        address aroundPool = _getPoolInfo(thisMarketId).aroundPool;
        if(getLiqudityInfo(thisMarketId).totalLp == 0) {
            liqudityInfo[thisMarketId].tradeCollateralAmount += getLiqudityInfo(thisMarketId).liquidityFeeAmount;
            liqudityInfo[thisMarketId].liquidityFeeAmount = 0;
        }
        (bool suc, ) = aroundPool.call(abi.encodeCall(
            IAroundPool(aroundPool).allot,
            (ifOpenAave)
        ));
        if(suc == false) {revert TouchAroundErr();}
    }

    function redeemWinnings(uint256 thisMarketId) external returns (uint256 winnings) {
        if(block.timestamp <= getMarketInfo(thisMarketId).endTime + 2 hours){
            revert NotWithdrawTime();
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
            (uint128 collateralAmount, uint128 feeShare) = AroundMath._calculateLiquidityWithdrawal(
                getLiqudityInfo(thisMarketId).liquidityFeeAmount,
                getUserPosition(msg.sender, thisMarketId).collateralAmount,
                getUserPosition(msg.sender, thisMarketId).lp,
                getUserPosition(msg.sender, thisMarketId).lp,
                getLiqudityInfo(thisMarketId).totalLp
            );
            winnings += (collateralAmount + feeShare);
            liqudityInfo[thisMarketId].lpCollateralAmount -= collateralAmount;
        }
        
        _checkZeroAmount(winnings);
        // clear
        delete userPosition[msg.sender][thisMarketId];

        //Touch aroundPool
        _touchAroundPool(
            true,
            getMarketInfo(thisMarketId).marketState.ifOpenAave,
            _getPoolInfo(thisMarketId).aroundPool,
            uint128(winnings)
        );
        emit Release(thisMarketId, msg.sender, winnings);
    }

    function _transferFee(
        address _collateral,
        uint128 _totalFeeAmount,
        uint256 _thisMarketId
    ) private {
        uint128 oracleFee = _totalFeeAmount * getFeeInfo(_thisMarketId).oracleFee / getFeeInfo(_thisMarketId).totalFee;
        uint128 officialFee = _totalFeeAmount * getFeeInfo(_thisMarketId).officialFee / getFeeInfo(_thisMarketId).totalFee;
        uint128 creatorFee = _totalFeeAmount * getFeeInfo(_thisMarketId).creatorFee / getFeeInfo(_thisMarketId).totalFee;
        uint128 luckyFee = _totalFeeAmount * getFeeInfo(_thisMarketId).luckyFee / getFeeInfo(_thisMarketId).totalFee;
        if(oracleFee > 0) {
            IERC20(_collateral).safeTransferFrom(msg.sender, oracle, oracleFee);
            IEchoOptimisticOracle(oracle).injectFee(_thisMarketId, oracleFee);
        }
        if(officialFee > 0) {
            IERC20(_collateral).safeTransferFrom(msg.sender, feeReceiver, officialFee);
        }
        if(creatorFee > 0) {
            IERC20(_collateral).safeTransferFrom(msg.sender, getMarketInfo(_thisMarketId).creator, creatorFee);
        }
        if(luckyFee > 0) {
            IERC20(_collateral).safeTransferFrom(msg.sender, _getPoolInfo(_thisMarketId).luckyPool, luckyFee);
        }
    }

    function _updateRaffleTicket(uint8 _decimals, uint256 _thisMarketId) private {
        if(getUserPosition(msg.sender, _thisMarketId).volume >= Min_Lucky_Volume * 10 ** _decimals) {
            marketInfo[_thisMarketId].totalRaffleTicket++;
            if(getUserPosition(msg.sender, _thisMarketId).raffleTicketNumber == 0){
                uint64 number = getMarketInfo(_thisMarketId).totalRaffleTicket;
                raffleTicketToUser[_thisMarketId][number] = msg.sender;
                userPosition[msg.sender][_thisMarketId].raffleTicketNumber = number;
            }
        }
    }

    function _injectAroundPool(
        uint128 _amountIn,
        uint128 _liquidityFee,
        uint256 _thisMarketId
    ) private {
        bool _ifOpenAave = getMarketInfo(_thisMarketId).marketState.ifOpenAave;
        address _aroundPool = _getPoolInfo(_thisMarketId).aroundPool;
        //Transfer fund to around
        IERC20(getMarketInfo(_thisMarketId).collateral).safeTransferFrom(
                msg.sender, 
                _aroundPool, 
                _amountIn + _liquidityFee
        );
        (bool suc, ) = _aroundPool.call(abi.encodeCall(
            IAroundPool(_aroundPool).deposite,
            (_ifOpenAave, _amountIn)
        ));
        if(suc == false) {revert TouchAroundErr();}
    }

    function _touchAroundPool(
        bool _ifEnd,
        bool _ifOpenAave,
        address _aroundPool,
        uint128 _amountOut
    ) private {
        (bool suc, ) = _aroundPool.call(abi.encodeCall(
            IAroundPool(_aroundPool).touch,
            (_ifEnd, _ifOpenAave, msg.sender, _amountOut)
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