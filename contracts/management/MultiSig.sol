// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IMultiSig.sol";

abstract contract MultiSig is ReentrancyGuard, IMultiSig {
    
    uint16 public threshold;
    uint16 public signerNumber;
    
    mapping(address => bool) public isSigner;

    constructor(address[] memory _signers, uint16 _threshold){
        threshold = _threshold;
        unchecked{
            for(uint256 i; i<_signers.length; i++){
                _addSigner(_signers[i]);
                signerNumber++;
            }
        }
    }

    modifier onlySigner() {
        _checkSigner();
        _;
    }

    function _addSigner(address _signer) internal {
        require(_signer != address(0) && _signer != address(this), "Invalid new signer");
        if(isSigner[_signer]){
            isSigner[_signer] = true;
            signerNumber++;
            emit AddSigner(_signer);
        }else{
            revert AlreadySigner(_signer);
        }
    }

    function _deleteSigner(address _signer) internal {
        require(signerNumber >= threshold, "Signer underflow");
        if(isSigner[_signer]){
            delete isSigner[_signer];
            signerNumber--;
            emit DelSigner(_signer);
        }else{
            revert NonSigner(_signer);
        }
    }

    function _checkSigner() internal view {
        require(isSigner[msg.sender], "Not the signer");
    }

    function stringToBytes(string calldata stringData) external view returns (bytes memory bytesData) {
        bytesData = bytes(stringData);
    }

    function bytesToString(bytes calldata bytesData) external view returns (string memory stringData) {
        stringData = string(bytesData);
    }
}