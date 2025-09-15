// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface BridgeInterface {
    function increaseUnionBridgeLockingCap(uint256 newLockingCap) external returns (int);

    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external payable returns (int);
}

contract MultiSigner {

    BridgeInterface public bridge = BridgeInterface(0x0000000000000000000000000000000001000006);

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

    enum OperationType { AddSigner, RemoveSigner, IncreaseLockingCap, SetTransferPermissions}

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

        signaturesRequired = (signers.length / 2) + 1;

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

    function removeSigner(address signerToRemove) public {
        if (!isSigner[msg.sender]) revert OnlySigner();
        if (signerToRemove == address(0)) revert InvalidSigner();
        if (signerToRemove == owner) revert InvalidSigner();
        if (!isSigner[signerToRemove]) revert InvalidSigner();
        // Never allow fewer than minSigners to exist
        if (signers.length <= minSigners) revert lessThanMinSigners();

        bytes32 opKey = keccak256(abi.encodePacked(OperationType.RemoveSigner, signerToRemove));
        Operation storage op = operations[opKey];

        if (op.votes[msg.sender]) revert AlreadyVoted();

        op.opType = OperationType.RemoveSigner;
        op.signer = signerToRemove;
        op.votes[msg.sender] = true;
        op.voteCount += 1;

        if (op.voteCount >= signaturesRequired) {
            // execute operation
            _removeSignerFromSet(signerToRemove);
            signaturesRequired = (signers.length / 2) + 1; // update majority after removal
            _resetOperation(opKey);
            emit SignerRemoved(signerToRemove);
        }
    }

    function _removeSignerFromSet(address target) internal {
        // Clear mapping
        isSigner[target] = false;
        // Find and remove from array by swapping with last
        uint256 len = signers.length;
        for (uint256 i = 0; i < len; i++) {
            if (signers[i] == target) {
                if (i != len - 1) {
                    signers[i] = signers[len - 1];
                }
                signers.pop();
                break;
            }
        }
    }

    function increaseUnionBridgeLockingCap(uint256 newLockingCap) public {
        if (!isSigner[msg.sender]) revert OnlySigner();
        // Operation id = by type + newLockingCap
        bytes32 opKey = keccak256(abi.encodePacked(OperationType.IncreaseLockingCap, newLockingCap));
        Operation storage op = operations[opKey];
        if (op.votes[msg.sender]) revert AlreadyVoted();
        op.opType = OperationType.IncreaseLockingCap;
        op.votes[msg.sender] = true;
        op.voteCount += 1;
        if (op.voteCount >= signaturesRequired) {
            // execute call on bridge
            bridge.increaseUnionBridgeLockingCap(newLockingCap);
            _resetOperation(opKey);
        }
    }

    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) public {
        if (!isSigner[msg.sender]) revert OnlySigner();
        // Operation ID = by type + requestEnabled + releaseEnabled
        bytes32 opKey = keccak256(abi.encodePacked(OperationType.SetTransferPermissions, requestEnabled, releaseEnabled));
        Operation storage op = operations[opKey];
        if (op.votes[msg.sender]) revert AlreadyVoted();
        op.opType = OperationType.SetTransferPermissions;
        op.votes[msg.sender] = true;
        op.voteCount += 1;
        if (op.voteCount >= signaturesRequired) {
            // execute call on bridge
            bridge.setUnionBridgeTransferPermissions(requestEnabled, releaseEnabled);
            _resetOperation(opKey);
        }
    }

    function _resetOperation(bytes32 opKey) internal {
        delete operations[opKey];
    }
}
