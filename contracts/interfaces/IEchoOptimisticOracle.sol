//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IEchoOptimisticOracle {

    enum OracleState{
        Normal,
        Dispute
    }

    enum EventState {
        Pending,
        Yes,
        No
    }

    enum OracleWithdrawState {
        Pending,
        providerWithdrawd,
        disputeWithdrawd
    }

    struct DataProviderInfo {
        bool valid;
        uint64 latestSubmitTime;
        uint128 depositeAmount;
    }

    struct OracleInfo {
        EventState eventState;
        OracleWithdrawState withdrawState;
        uint16 yesVote;
        uint16 noVote;
        uint64 randomNumber;
        uint64 updateTime;
        uint256 earn;
        string quest;
        OptimisticInfo optimisticInfo;
    }

    struct OptimisticInfo {
        OracleState state;
        bool isDisputePass;
        uint16 disputeVotes;
        uint16 responseCount;
        address challenger; 
        string evidence;
        address[] providers;
        address[] investigators;
    }

    struct SubmitDataInfo {
        EventState eventState;
        bool isSubmit;
        uint256 randomNumber;
        string dataSources;
    }

    event RegisterProvider(address indexed newProvider);
    event InjectFee(uint256 indexed thisMarketId, uint256 indexed value);
    event InjectQuest(uint256 indexed thisMarketId, string thisQuest);
    event SubmitData(address indexed provider, uint256 indexed thisMarketId, EventState thisEventState, uint64 thisRandomNumber);
    event Challenge(address indexed challenger, uint256 indexed thisMarketId);

    function injectQuest(uint256 id, string calldata thisQuest) external;
    function injectFee(uint256 id, uint256 value) external;

    function getOracleInfo(uint256 id) external view returns (
        OracleInfo memory thisOracleInfo
    );

    function getSubmitDataInfo(address user, uint256 id) external view returns (SubmitDataInfo memory);
}