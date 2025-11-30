// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {IEchoOptimisticOracle} from "../interfaces/IEchoOptimisticOracle.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LuckyPool {

    using SafeERC20 for IERC20;
    
    IAroundMarket AroundMarket;

    uint64 public luckyNumber;
    address public luckyWinner;

    address public aroundPoolFactory;
    bool public ifWithdraw;

    constructor(
        address thisAroundMarket
    ) { 
        aroundPoolFactory = msg.sender;
        AroundMarket = IAroundMarket(thisAroundMarket);
    }

    event WithdrawReward(address indexed sender, address indexed luckyUser, uint256 indexed value);

    function bump(uint256 thisMarketId) external {
        require(ifWithdraw == false, "Already wthdraw");
        uint64 participants = AroundMarket.getMarketInfo(thisMarketId).totalRaffleTicket;
        uint64 endTime = AroundMarket.getMarketInfo(thisMarketId).endTime;
        require(block.timestamp >= endTime + 2 hours, "It's not time yet");
        require(participants > 0, "No participants");
        address oracle = AroundMarket.oracle();
        require(IEchoOptimisticOracle(oracle).getOracleRandomNumberInfo(thisMarketId).valid, "Invalid");
        uint64 oracleRandomNumber = IEchoOptimisticOracle(oracle).getOracleRandomNumberInfo(thisMarketId).randomNumber;
        require(oracleRandomNumber != 0, "Invalid oracle randomNumber");
        _selectLuckyWinner(thisMarketId, oracleRandomNumber, participants);
        ifWithdraw = true;
    }
    
    function _selectLuckyWinner(
        uint256 _thisMarketId, 
        uint64 _oracleRandomNumber, 
        uint64 _totalUser
    ) internal {
        uint64 winnerNumber = uint64(_getLuckyRandomNumber(_oracleRandomNumber, _totalUser));
        address collateral = AroundMarket.getMarketInfo(_thisMarketId).collateral;
        require(collateral != address(0), "Collateral is zero address");
        uint256 winnerReward = IERC20(collateral).balanceOf(address(this));
        require(winnerReward > 0, "Zero");
        luckyWinner = AroundMarket.raffleTicketToUser(_thisMarketId, winnerNumber);
        require(luckyWinner != address(0), "Winner is zero address");
        IERC20(collateral).safeTransfer(luckyWinner, winnerReward);
        emit WithdrawReward(msg.sender, luckyWinner, winnerReward);
    }
    
    function _getLuckyRandomNumber(uint64 _oracleRandomNumber, uint64 _totalUser) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            _oracleRandomNumber,
            block.timestamp,
            _totalUser
        ))) % _totalUser;
    }
    
}