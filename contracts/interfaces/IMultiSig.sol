// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IMultiSig{

    error NonSigner(address);
    error AlreadySigner(address);

    event AddSigner(address newSigner);
    event DelSigner(address oldSigner);
    event ChangeThreshold(uint16 olderThreshold, uint16 newThreshold);

    enum ChangeType{AddSigner, DelSigner}

    function isSigner(address) external view returns (bool);


}