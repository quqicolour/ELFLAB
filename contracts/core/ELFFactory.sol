// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import '../interfaces/IELFFactory.sol';
import './ELFPair.sol';

contract ELFFactory is IELFFactory {

    address private owner;
    address private manager;
    address public feeReceiver;
    address public elf;

    address[] private allPairs;

    mapping(address => PoolInfo) private poolInfo;

    mapping(address => mapping(address => address)) public getPair;

    constructor(
        address _owner, 
        address _manager,
        address _feeReceiver,
        address _elf
    ){
        owner = _owner;
        manager = _manager;
        feeReceiver = _feeReceiver;
        elf = _elf;
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
        _;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'ELFFactory: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ELFFactory: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'ELFFactory: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = abi.encodePacked(type(ELFPair).creationCode, abi.encode(elf));
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(pair)) {
                revert(0, 0)
            }
        }
        ELFPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        poolInfo[pair].feeReceiver = feeReceiver;
        emit PairCreated(token0, token1, pair);
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }

    function setFeeReceiver(address _newFeeReceiver) external onlyOwner {
        feeReceiver = _newFeeReceiver;
    }

    function setPoolInfo(
        uint16 _token0FeePercent,
        uint16 _token1FeePercent,
        uint16 _luckyPoolFeePercent,
        address _pair,
        address _luckyPool,
        bool _stableSwap,
        bool _isActive
    ) external onlyManager {
        poolInfo[_pair].token0FeePercent = _token0FeePercent;
        poolInfo[_pair].token1FeePercent = _token1FeePercent;
        poolInfo[_pair].luckyPoolFeePercent = _luckyPoolFeePercent;
        poolInfo[_pair].feeReceiver = feeReceiver;
        poolInfo[_pair].luckyPool = _luckyPool;
        poolInfo[_pair].stableSwap = _stableSwap;
        poolInfo[_pair].isActive = _isActive;
    }

    function indexPair(uint256 index) external view returns (address _thisPair) {
        _thisPair = allPairs[index];
    }

    function allPairsLength() external view returns (uint256 _groupLength) {
        _groupLength = allPairs.length;
    }

    function getPoolInfo(address pair) external view returns (PoolInfo memory _thisPoolInfo) {
        _thisPoolInfo = poolInfo[pair];
    }

    function pairCodeHash() external view returns (bytes32 _pairCodeHash) {
        _pairCodeHash = keccak256(type(ELFPair).creationCode);
    }

}