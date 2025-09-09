// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

contract MultiSigner {

    error OnlySigner();
    error AlreadyInitialized();
    error lessThanMinSigners();
    error InvalidSigner();
    error AlreadySigner();
    error AlreadyVoted();

    event SignerAdded(address indexed newSigner);
    event SignerRemoved(address indexed removedSigner);

    address public owner;

    uint256 public signaturesRequired;
    uint256 public minSigners = 3;
    address[] public signers;
    mapping(address => bool) public isSigner;

    enum OperationType { AddSigner, RemoveSigner}

    struct Operation {
        OperationType opType;
        address signer;
        uint256 voteCount;
        mapping(address => bool) votes;
    }

    mapping(address => int256) public addSignerVotes;
    mapping(address => int256) public removeSignerVotes;
    mapping(bytes32 => Operation) public operations;

    constructor(address[] memory initialSigners) {
        owner = msg.sender;
        if (initialSigners.length < minSigners) revert lessThanMinSigners();

        for (uint256 i = 0; i < initialSigners.length; i++) {
            address signer = initialSigners[i];
            if (signer == address(0)) revert InvalidSigner();
            if (signer == owner) revert InvalidSigner();
            signers.push(signer);
            isSigner[signer] = true;
        }

        signaturesRequired = (signers.length / 2) + 1; // strict majority
    }

    function addSigner(address newSigner) public {
        if (newSigner == address(0)) revert InvalidSigner();
        if (newSigner == owner) revert InvalidSigner();
        if (isSigner[newSigner]) revert AlreadySigner();
        if (!isSigner[msg.sender]) revert OnlySigner();

        bytes32 opKey = keccak256(abi.encodePacked(OperationType.AddSigner, newSigner));
        Operation storage op = operations[opKey];

        if (op.votes[msg.sender]) revert AlreadyVoted();

        op.opType = OperationType.AddSigner;
        op.signer = newSigner;
        op.votes[msg.sender] = true;
        op.voteCount += 1;

        if (op.voteCount >= signaturesRequired) {
            // execute operation
            signers.push(newSigner);
            isSigner[newSigner] = true;
            signaturesRequired = (signers.length / 2) + 1; // update majority
            _resetOperation(opKey);
            emit SignerAdded(newSigner);
        }
    }

    function _resetOperation(bytes32 opKey) internal {
        delete operations[opKey];
    }
}
