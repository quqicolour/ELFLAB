//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IEchoOptimisticOracle {

    enum OracleState{
        Normal,
        Dispute
    }

    enum OracleType {
        Event,
        Random
    }

    enum EventState {
        Pending,
        Yes,
        No
    }

    struct OptimisticInfo {
        OracleState state;
        bool isDisputePass;
        uint16 disputeVotes;
        uint16 responseCount;
        uint64 coolingTime;
        address challenger; 
        string evidence;
        address[] providers;
        address[] investigators;
    }

    struct OracleEventInfo {
        EventState eventState;
        uint16 yesVote;
        uint16 noVote;
        uint64 updateTime;
        string quest;
        OptimisticInfo optimisticInfo;
    }

    struct OracleRandomNumberInfo {
        bool valid;
        uint64 updateTime;
        uint64 randomNumber;
        uint16 responseCount;
        address[] providers;
    }

    struct SubmitEventDataInfo {
        EventState eventState;
        string dataSources;
    }

    struct SubmitRandomNumberInfo {
        bool isSubmit;
        uint256 randomNumber;
    }

    event RegisterProvider(address indexed newProvider);
    event SubmitEventData(address indexed provider, EventState indexed thisEventState, uint256 indexed eventId);
    event SubmitRandomNumber(address indexed provider, uint64 indexed thisRandomNumber, uint256 indexed randomNumberId);
    event Challenge(OracleType indexed oracleType, address indexed challenger, uint256 indexed id);

    function getOracleEventInfo(uint256 id) external view returns (
        OracleEventInfo memory thisOracleEventInfo
    );

    function getOracleRandomNumberInfo(uint256 id) external view returns (
        OracleRandomNumberInfo memory thisOracleRandomNumberInfo
    );

    function getSubmitEventDataInfo(address user, uint256 id) external view returns (SubmitEventDataInfo memory);

    function getSubmitRandomNumberInfo(address user, uint256 id) external view returns (SubmitRandomNumberInfo memory);
}