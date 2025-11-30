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

    uint64 public constant random_min = 1000000000000;
    uint64 public constant random_max = 9999999999999;

    //default == 3
    uint16 public eventPassThreshold = 3;
    //default == 5
    uint16 public randomNumberPassThreshold = 5;
    //default == 3;
    uint16 public disputePassThreshold = 3;
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

    mapping(uint256 => OracleEventInfo) private _oracleEventInfo;
    mapping(uint256 => OracleRandomNumberInfo) private _oracleRandomNumberInfo;

    mapping(address => mapping(uint256 => SubmitEventDataInfo)) private _submitEventDataInfo;
    mapping(address => mapping(uint256 => SubmitRandomNumberInfo)) private _submitRandomNumberInfo;

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

    function registProvider(address provider) external { 
        require(dataProvider[msg.sender] == false, "Already a challenger");
        uint256 value = registFee * 10 ** _getUSDCDecimals();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), value);
        dataProvider[provider] = true;
        emit RegisterProvider(provider);
    }

    function submitEventData(
        uint256 id,
        bool isYes,
        string calldata dataSources
    ) external nonReentrant {
        require(_submitEventDataInfo[msg.sender][id].eventState == EventState.Pending, "Already submit");
        EventState newEventState;

        _oracleEventInfo[id].optimisticInfo.responseCount++;
        _oracleEventInfo[id].optimisticInfo.providers.push(msg.sender);
        if(isYes) {
            newEventState = EventState.Yes;
            _oracleEventInfo[id].yesVote++;
        }else {
            newEventState = EventState.No;
            _oracleEventInfo[id].noVote++;
        }

        if(_oracleEventInfo[id].yesVote + _oracleEventInfo[id].noVote >= eventPassThreshold) {
            if(_oracleEventInfo[id].yesVote > _oracleEventInfo[id].noVote) {
                _oracleEventInfo[id].eventState = EventState.Yes;
                _oracleEventInfo[id].updateTime = uint64(block.timestamp);
            }else if(_oracleEventInfo[id].yesVote < _oracleEventInfo[id].noVote) {
                _oracleEventInfo[id].eventState = EventState.No;
                _oracleEventInfo[id].updateTime = uint64(block.timestamp);
            }
        }

        _submitEventDataInfo[msg.sender][id].eventState = newEventState;
        _submitEventDataInfo[msg.sender][id].dataSources = dataSources;
        emit SubmitEventData(msg.sender, newEventState, id);
    }

    function submitRandomNumber(uint256 id, uint64 randomNumber) external nonReentrant {
        require(randomNumber >= random_min && randomNumber <= random_max, "Invalid random number");
        require(_submitEventDataInfo[msg.sender][id].eventState == EventState.Pending, "Already submit");
        _submitRandomNumberInfo[msg.sender][id].isSubmit = true;
        _submitRandomNumberInfo[msg.sender][id].randomNumber = randomNumber;
        _oracleRandomNumberInfo[id].providers.push(msg.sender);
        _oracleRandomNumberInfo[id].responseCount++;
        if(_oracleRandomNumberInfo[id].responseCount >= randomNumberPassThreshold) {
            _oracleRandomNumberInfo[id].updateTime = uint64(block.timestamp);
            _oracleRandomNumberInfo[id].valid = true;
        }
        uint64 currentRandomNumber = _oracleRandomNumberInfo[id].randomNumber;
        uint64 actualRandomNumber;
        if(currentRandomNumber == 0) {
            actualRandomNumber = randomNumber;
        } else {
            actualRandomNumber = currentRandomNumber / 2 - 1 + randomNumber / 2;
        }
        _oracleRandomNumberInfo[id].randomNumber = actualRandomNumber;
        emit SubmitRandomNumber(msg.sender, actualRandomNumber, id);
    }

    function challenge(
        OracleType oracleType, 
        uint256 id, 
        string calldata evidence
    ) external {
        uint256 value = challengerFee * 10 ** _getUSDCDecimals();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), value);
        if (oracleType == OracleType.Event) {
            _oracleEventInfo[id].optimisticInfo.state = OracleState.Dispute;
            _oracleEventInfo[id].optimisticInfo.evidence = evidence;
            _oracleEventInfo[id].optimisticInfo.challenger = msg.sender;
        } else {
            revert ("Invalid oracleType");
        }
        emit Challenge(oracleType, msg.sender, id);
    }

    function disputeVote(
        OracleType oracleType,
        uint256 id
    ) external {
        require(investigator[msg.sender], "Non investigator");
        require(_oracleEventInfo[id].optimisticInfo.isDisputePass == false, "Dispute pass");
        if (oracleType == OracleType.Event) {
            require(block.timestamp <= _oracleEventInfo[id].optimisticInfo.coolingTime, "Over");
            _oracleEventInfo[id].optimisticInfo.disputeVotes++;
            _oracleEventInfo[id].optimisticInfo.investigators.push(msg.sender);
            if(_oracleEventInfo[id].optimisticInfo.disputeVotes >= disputePassThreshold){
                _oracleEventInfo[id].optimisticInfo.isDisputePass = true;
                if(_oracleEventInfo[id].eventState == EventState.Yes) {
                    _oracleEventInfo[id].eventState == EventState.No;
                }else if(_oracleEventInfo[id].eventState == EventState.No) {
                    _oracleEventInfo[id].eventState == EventState.Yes;
                }
            }
        } else {
            revert ("Invalid oracleType");
        }
    }

    function withdrawOracle() external nonReentrant {

    }

    function withdrawDispute(
        OracleType oracleType,
        uint256 id
    ) external nonReentrant {
        if (oracleType == OracleType.Event) {
            require(_oracleEventInfo[id].optimisticInfo.state == OracleState.Dispute, "Invalid");
            require(block.timestamp > _oracleEventInfo[id].optimisticInfo.coolingTime, "Over");
            if(_oracleEventInfo[id].optimisticInfo.isDisputePass) {
                address challenger = _oracleEventInfo[id].optimisticInfo.challenger;
                uint256 singleCollateralAmount = registFee * 10 ** _getUSDCDecimals() * challengRewardRate / 100;
                uint256 challengReward = challengerFee * 10 ** _getUSDCDecimals();
                unchecked {
                    for(uint256 i; i<_oracleEventInfo[id].optimisticInfo.responseCount; i++) {
                        address provider = _oracleEventInfo[id].optimisticInfo.providers[i];
                        if(_submitEventDataInfo[provider][id].eventState != _oracleEventInfo[id].eventState) {
                            challengReward += singleCollateralAmount;
                        }
                    }
                }
                IERC20(usdc).safeTransfer(challenger, challengReward);
            } else {
                uint256 len = _oracleEventInfo[id].optimisticInfo.disputeVotes;
                uint256 singleExamineFee = registFee * 10 ** _getUSDCDecimals() / len;
                unchecked {
                    for(uint256 i; i<len; i++) {
                        address thisInvestigator = _oracleEventInfo[id].optimisticInfo.investigators[i];
                        IERC20(usdc).safeTransfer(thisInvestigator, singleExamineFee);
                    }
                }
            }
        } else {
            revert ("Invalid oracleType");
        }
    }

    function touchOracle(uint256 thisMarketId, uint256 value) external {
        gains[thisMarketId] += value;
    }

    function _getUSDCDecimals() private view returns (uint8) {
        return IERC20Metadata(usdc).decimals();
    }

    function getOracleEventInfo(uint256 id) external view returns (
        OracleEventInfo memory thisOracleEventInfo
    ) {
        thisOracleEventInfo = _oracleEventInfo[id];
    }

    function getOracleRandomNumberInfo(uint256 id) external view returns (
        OracleRandomNumberInfo memory thisOracleRandomNumberInfo
    ) {
        thisOracleRandomNumberInfo = _oracleRandomNumberInfo[id];
    }

    function getSubmitEventDataInfo(address user, uint256 id) external view returns (SubmitEventDataInfo memory) {
        return _submitEventDataInfo[user][id];
    }

    function getSubmitRandomNumberInfo(address user, uint256 id) external view returns (SubmitRandomNumberInfo memory) {
        return _submitRandomNumberInfo[user][id];
    }
}