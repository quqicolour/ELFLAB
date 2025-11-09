// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import '../interfaces/IELFFactory.sol';
import './ELFPair.sol';

contract ELFFactory is IELFFactory{

    address private owner;
    address private manager;
    address public feeReceiver;
    address public luckyPool;

    address[] private allPairs;

    mapping(address => PoolInfo) public poolInfo;

    mapping(address => mapping(address => address)) public getPair;

    constructor(
        address _owner, 
        address _manager,
        address _feeReceiver
    ){
        owner = _owner;
        manager = _manager;
        feeReceiver = _feeReceiver;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == msg.sender, "Non owner");
        _;
    }

    modifier onlyManager() {
        require(manager == msg.sender, "Non mananger");
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'ELFFactory: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ELFFactory: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'ELFFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = pairCodeHash();
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0));
        ELFPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        poolInfo[pair].feeReceiver = feeReceiver;
        emit PairCreated(token0, token1, pair);
    }

    function setManager(address _manager) external onlyOwner {
        manager = _managerl
    }

    function setPoolInfo(
        address pair,
        uint16 token0FeePercent,
        uint16 token1FeePercent,
        uint16 luckyPoolFeePercent,
        address feeReceiver,
        address luckyPool,
        bool stableSwap,
        bool isActive
    ) external onlyManager {
        poolInfo[pair].token0FeePercent = token0FeePercent;
        poolInfo[pair].token1FeePercent = token1FeePercent;
        poolInfo[pair].luckyPoolFeePercent = luckyPoolFeePercent;
        poolInfo[pair].feeReceiver = feeReceiver;
        poolInfo[pair].luckyPool = luckyPool;
        poolInfo[pair].stableSwap = stableSwap;
        poolInfo[pair].isActive = isActive;
    }

    function indexPair(uint256 index) external view returns (address _thisPair) {
        _thisPair = allPairs[index];
    }

    function allPairsLength() external view returns (uint256 _groupLength) {
        _groupLength = allPairs.length;
    }

    function pairCodeHash() public view returns (bytes32 _pairCodeHash) {
        _pairCodeHash = keccak256(type(ELFPair).creationCode);
    }

}