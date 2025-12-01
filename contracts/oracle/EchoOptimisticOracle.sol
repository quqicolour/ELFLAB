//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IAroundMarket} from "../interfaces/IAroundMarket.sol";
import {IEchoOptimisticOracle} from "../interfaces/IEchoOptimisticOracle.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EchoOptimisticOracle is Ownable, ReentrancyGuard, IEchoOptimisticOracle {

    using SafeERC20 for IERC20;

    uint64 public constant Random_Min = 1000000000000;
    uint64 public constant Random_Max = 9999999999999;
    uint64 public constant Minimum_Reward = 1000;

    uint16 public threshold = 3;
    uint16 public disputePassThreshold = 3;
    uint32 public coolingTime = 2 hours;
    //USDC
    uint256 public challengerFee = 100;
    uint256 public challengRewardRate = 75;
    uint256 public registFee = 10000;

    address public aroundMarket;
    address public usdc;
    bool public isInitialize;

    mapping(address => bool) public validCollateral;
    mapping(address => bool) public dataProvider;
    mapping(address => bool) public investigator;
    mapping(uint256 => uint256) public gains;

    mapping(address => uint256) public pledgeAmount;

    mapping(uint256 => OracleInfo) private oracleInfo;

    mapping(address => mapping(uint256 => SubmitDataInfo)) private submitDataInfo;

    constructor() Ownable(msg.sender) {}

    function initialize(address _aroundMarket) external {
        require(isInitialize == false, "Already initialize");
        aroundMarket = _aroundMarket;
        isInitialize = true;
    }

    function setRegistFee(uint256 newRegistFee) external {
        registFee = newRegistFee;
    }

    function setChallengerFee(uint256 newChallengerFee) external {
        challengerFee = newChallengerFee;
    }

    function setCoolingTime(uint32 newCoolingTime) external {
        coolingTime = newCoolingTime;
    }

    function registProvider(address provider) external { 
        require(dataProvider[msg.sender] == false, "Already a challenger");
        uint256 value = registFee * 10 ** _getUSDCDecimals();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), value);
        dataProvider[provider] = true;
        emit RegisterProvider(provider);
    }

    function injectQuest(uint256 id, string calldata thisQuest) external {
        require(msg.sender == aroundMarket, "Non aroundMarket");
        oracleInfo[id].quest = thisQuest;
    }

    function injectFee(uint256 thisMarketId, uint256 value) external {
        require(msg.sender == aroundMarket, "Non aroundMarket");
        gains[thisMarketId] += value;
        emit InjectFee(thisMarketId, value);
    }

    function submitData(
        uint256 id,
        bool isYes,
        uint64 randomNumber,
        string calldata eventDataSources
    ) external nonReentrant {
        require(submitDataInfo[msg.sender][id].eventState == EventState.Pending, "Already submit");
        require(dataProvider[msg.sender], "Not data provider");
        EventState newEventState;

        oracleInfo[id].optimisticInfo.responseCount++;
        oracleInfo[id].optimisticInfo.providers.push(msg.sender);
        if(isYes) {
            newEventState = EventState.Yes;
            oracleInfo[id].yesVote++;
        }else {
            newEventState = EventState.No;
            oracleInfo[id].noVote++;
        }

        if(oracleInfo[id].yesVote + oracleInfo[id].noVote >= threshold) {
            if(oracleInfo[id].yesVote > oracleInfo[id].noVote) {
                oracleInfo[id].eventState = EventState.Yes;
                oracleInfo[id].updateTime = uint64(block.timestamp);
            }else if(oracleInfo[id].yesVote < oracleInfo[id].noVote) {
                oracleInfo[id].eventState = EventState.No;
                oracleInfo[id].updateTime = uint64(block.timestamp);
            }
        }

        //Random number
        uint64 currentRandomNumber = oracleInfo[id].randomNumber;
        uint64 actualRandomNumber;
        if(currentRandomNumber == 0) {
            actualRandomNumber = randomNumber;
        } else {
            actualRandomNumber = currentRandomNumber / threshold - 1 + randomNumber / threshold;
        }
        oracleInfo[id].randomNumber = actualRandomNumber;

        submitDataInfo[msg.sender][id].eventState = newEventState;
        submitDataInfo[msg.sender][id].dataSources = eventDataSources;
        emit SubmitData(msg.sender, id, newEventState, actualRandomNumber);
    }

    function challenge(
        uint256 id, 
        string calldata evidence
    ) external {
        require(block.timestamp <= oracleInfo[id].updateTime + coolingTime, "Finished");
        uint256 value = challengerFee * 10 ** _getUSDCDecimals();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), value);
        oracleInfo[id].optimisticInfo.state = OracleState.Dispute;
        oracleInfo[id].optimisticInfo.evidence = evidence;
        oracleInfo[id].optimisticInfo.challenger = msg.sender;
        emit Challenge(msg.sender, id);
    }

    function disputeVote(
        uint256 id
    ) external {
        require(investigator[msg.sender], "Not investigator");
        require(oracleInfo[id].optimisticInfo.isDisputePass == false, "Dispute pass");
        require(block.timestamp <= oracleInfo[id].updateTime + coolingTime, "Finished");

        oracleInfo[id].optimisticInfo.disputeVotes++;
        oracleInfo[id].optimisticInfo.investigators.push(msg.sender);

        if(oracleInfo[id].optimisticInfo.disputeVotes >= disputePassThreshold){
            oracleInfo[id].optimisticInfo.isDisputePass = true;
            if(oracleInfo[id].eventState == EventState.Yes) {
                oracleInfo[id].eventState == EventState.No;
            }else if(oracleInfo[id].eventState == EventState.No) {
                oracleInfo[id].eventState == EventState.Yes;
            }
        }
    }

    function withdrawOracle(
        uint256 id
    ) external nonReentrant {
        require(block.timestamp > oracleInfo[id].updateTime + coolingTime, "Not finish");
        require(oracleInfo[id].optimisticInfo.isDisputePass == false, "Dispute pass");
        require(oracleInfo[id].ifWithdraw == false, "Already withdraw");
        uint256 len = oracleInfo[id].optimisticInfo.responseCount;
        uint256 earn = gains[id];
        require(earn > Minimum_Reward, "Invalid amount");
        uint256 singleExamineFee = earn / len;
        oracleInfo[id].ifWithdraw = true;
        //Transfer to each provider
        unchecked {
            for(uint256 i; i<len; i++) {
                address thisInvestigator = oracleInfo[id].optimisticInfo.providers[i];
                IERC20(usdc).safeTransfer(thisInvestigator, singleExamineFee);
            }
        }
    }

    function withdrawDispute(
        uint256 id
    ) external nonReentrant {
        require(oracleInfo[id].disputeWithdrawd == false, "Already withdraw");
        require(oracleInfo[id].optimisticInfo.state == OracleState.Dispute, "Invalid");
        require(block.timestamp > oracleInfo[id].updateTime + coolingTime, "Not finish");

        oracleInfo[id].disputeWithdrawd = true;

        if(oracleInfo[id].optimisticInfo.isDisputePass) {
            address challenger = oracleInfo[id].optimisticInfo.challenger;
            uint256 singleCollateralAmount = registFee * 10 ** _getUSDCDecimals() * challengRewardRate / 100;
            uint256 challengReward = challengerFee * 10 ** _getUSDCDecimals();
            unchecked {
                for(uint256 i; i<oracleInfo[id].optimisticInfo.responseCount; i++) {
                    address provider = oracleInfo[id].optimisticInfo.providers[i];
                    if(submitDataInfo[provider][id].eventState != oracleInfo[id].eventState) {
                        challengReward += singleCollateralAmount;
                    }
                }
            }
            IERC20(usdc).safeTransfer(challenger, challengReward);
        } else {
            uint256 len = oracleInfo[id].optimisticInfo.disputeVotes;
            uint256 singleExamineFee = registFee * 10 ** _getUSDCDecimals() / len;
            unchecked {
                for(uint256 i; i<len; i++) {
                    address thisInvestigator = oracleInfo[id].optimisticInfo.investigators[i];
                    IERC20(usdc).safeTransfer(thisInvestigator, singleExamineFee);
                }
            }
        }
    }

    function _getUSDCDecimals() private view returns (uint8) {
        return IERC20Metadata(usdc).decimals();
    }

    function getOracleInfo(uint256 id) external view returns (
        OracleInfo memory thisOracleInfo
    ) {
        thisOracleInfo = oracleInfo[id];
    }

    function getSubmitDataInfo(address user, uint256 id) external view returns (SubmitDataInfo memory) {
        return submitDataInfo[user][id];
    }
    
}