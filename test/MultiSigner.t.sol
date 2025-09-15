// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MultiSigner} from "../src/MultiSigner.sol";

// Mock bridge to capture calls from MultiSigner
contract MockBridge {
    event IncreaseLockingCap(uint256 newLockingCap);
    event SetTransferPermissions(bool requestEnabled, bool releaseEnabled);

    uint256 public _unionBridgeLockingCap;
    bool public _requestEnabled;
    bool public _releaseEnabled;
    uint256 public increaseUnionLockingCapNumberOfCalls;
    uint256 public setTransferPermissionsNumberOfCalls;

    function increaseUnionBridgeLockingCap(uint256 newLockingCap) external returns (int) {
        _unionBridgeLockingCap = newLockingCap;
        increaseUnionLockingCapNumberOfCalls += 1;
        emit IncreaseLockingCap(newLockingCap);
        return 0;
    }

    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external payable returns (int) {
        _requestEnabled = requestEnabled;
        _releaseEnabled = releaseEnabled;
        setTransferPermissionsNumberOfCalls += 1;
        emit SetTransferPermissions(requestEnabled, releaseEnabled);
        return 0;
    }
}

contract MultiSignerTest is Test {
    event SignerAdded(address indexed newSigner);
    event SignerRemoved(address indexed removedSigner);
    MultiSigner multiSigner;

    // Hardcoded bridge address used by MultiSigner
    address constant BRIDGE_ADDR = 0x0000000000000000000000000000000001000006;
    // Handle to the mock residing at BRIDGE_ADDR
    MockBridge bridgeAt;

    address authorizer1;
    address authorizer2;
    address authorizer3;
    address authorizer4;
    address unauthorizedCaller;

    function setUp() public {
        // init authorizers
        authorizer1 = makeAddr("authorizer1");
        authorizer2 = makeAddr("authorizer2");
        authorizer3 = makeAddr("authorizer3");
        authorizer4 = makeAddr("authorizer4");
        unauthorizedCaller = makeAddr("unauthorizedCaller");

        address[] memory initAuthorizers = new address[](4);
        initAuthorizers[0] = authorizer1;
        initAuthorizers[1] = authorizer2;
        initAuthorizers[2] = authorizer3;
        initAuthorizers[3] = authorizer4;

        // Deploy from this contract; owner = address(this)
        multiSigner = new MultiSigner(initAuthorizers);

        // Deploy mock bridge and install its code at the hardcoded bridge address
        MockBridge deployed = new MockBridge();
        bytes memory code = address(deployed).code;
        vm.etch(BRIDGE_ADDR, code);
        bridgeAt = MockBridge(BRIDGE_ADDR);
    }

    function testConstructor_RevertWhenTooFewSigners() public {
        address[] memory initAuthorizers = new address[](2); // minSigners = 3, revert when < 3
        initAuthorizers[0] = makeAddr("authorizer1");
        initAuthorizers[1] = makeAddr("authorizer2");

        vm.expectRevert(MultiSigner.lessThanMinSigners.selector);
        new MultiSigner(initAuthorizers);
    }

    function testConstructor_RevertWhenZeroAddress() public {
        address[] memory initAuthorizers = new address[](4);
        initAuthorizers[0] = address(0);
        initAuthorizers[1] = makeAddr("authorizer1");
        initAuthorizers[2] = makeAddr("authorizer2");
        initAuthorizers[3] = makeAddr("authorizer3");

        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        new MultiSigner(initAuthorizers);
    }

    function testConstructor_RevertWhenOwnerIncluded() public {
        // Owner is address(this) during deployment
        address[] memory initAuthorizers = new address[](4);
        initAuthorizers[0] = makeAddr("authorizer1");
        initAuthorizers[1] = makeAddr("authorizer2");
        initAuthorizers[2] = makeAddr("authorizer3");
        initAuthorizers[3] = address(this);

        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        new MultiSigner(initAuthorizers);
    }

    function testInitialSetup() public {
        // signaturesRequired should be strict majority of 3 => 3
        assertEq(multiSigner.signaturesRequired(), 3);
        // initial signers are set
        assertTrue(multiSigner.isSigner(authorizer1));
        assertTrue(multiSigner.isSigner(authorizer2));
        assertTrue(multiSigner.isSigner(authorizer3));

        // owner is not a signer
        assertFalse(multiSigner.isSigner(address(this)));
    }

    function testAddSigner_MajorityRequiredAndEvent() public {
        address newSigner = makeAddr("newAuthorizer");

        // First vote by authorizer1
        vm.prank(authorizer1);
        multiSigner.addSigner(newSigner);
        assertFalse(multiSigner.isSigner(newSigner));
        // Second vote by authorizer2
        vm.prank(authorizer2);
        multiSigner.addSigner(newSigner);
        assertFalse(multiSigner.isSigner(newSigner));

        // Expect event on the third vote
        vm.expectEmit(true, false, false, true);
        emit SignerAdded(newSigner);
        // Third vote by authorizer3 triggers addition
        vm.prank(authorizer3);
        multiSigner.addSigner(newSigner);

        assertTrue(multiSigner.isSigner(newSigner));
        // New total signers = 5 => signaturesRequired = (5/2)+1 = 3
        assertEq(multiSigner.signaturesRequired(), 3);
    }

    function testAddSigner_OnlySignerCanVote() public {
        address newSigner = makeAddr("newAuthorizer");
        vm.prank(unauthorizedCaller);
        vm.expectRevert(MultiSigner.OnlySigner.selector);
        multiSigner.addSigner(newSigner);
    }

    function testAddSigner_RevertOnInvalidInputs() public {
        // zero address
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        multiSigner.addSigner(address(0));

        // owner address (address(this)) is invalid
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        multiSigner.addSigner(address(this));

        // already signer
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.AlreadySigner.selector);
        multiSigner.addSigner(authorizer2);
    }

    function testAddSigner_PreventDoubleVote() public {
        address newSigner = makeAddr("newAuthorizer");
        vm.prank(authorizer1);
        multiSigner.addSigner(newSigner);
        // authorizer1 votes again
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.AlreadyVoted.selector);
        multiSigner.addSigner(newSigner);
    }

    function testRemoveSigner_MajorityRequiredAndEvent() public {
        // remove authorizer4 by majority (3-of-4)
        vm.prank(authorizer1);
        multiSigner.removeSigner(authorizer4);
        assertTrue(multiSigner.isSigner(authorizer4));

        vm.prank(authorizer2);
        multiSigner.removeSigner(authorizer4);
        assertTrue(multiSigner.isSigner(authorizer4));

        vm.expectEmit(true, false, false, true);
        emit SignerRemoved(authorizer4);
        vm.prank(authorizer3);
        multiSigner.removeSigner(authorizer4);

        assertFalse(multiSigner.isSigner(authorizer4));
        // New total signers = 3 => signaturesRequired = (3/2)+1 = 2
        assertEq(multiSigner.signaturesRequired(), 2);
    }

    function testRemoveSigner_OnlySignerCanVote() public {
        vm.prank(unauthorizedCaller);
        vm.expectRevert(MultiSigner.OnlySigner.selector);
        multiSigner.removeSigner(authorizer1);
    }

    function testRemoveSigner_RevertOnInvalidInputs() public {
        // zero address
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        multiSigner.removeSigner(address(0));

        // owner address invalid
        vm.prank(authorizer2);
        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        multiSigner.removeSigner(address(this));

        // non-signer address invalid
        address notSigner = makeAddr("notSigner");
        vm.prank(authorizer3);
        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        multiSigner.removeSigner(notSigner);
    }

    function testRemoveSigner_PreventDoubleVote() public {
        vm.prank(authorizer1);
        multiSigner.removeSigner(authorizer4);
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.AlreadyVoted.selector);
        multiSigner.removeSigner(authorizer4);
    }

    function testRemoveSigner_CannotDropBelowMinSigners() public {
        // First remove one signer to go from 4 -> 3
        vm.prank(authorizer1); multiSigner.removeSigner(authorizer4);
        vm.prank(authorizer2); multiSigner.removeSigner(authorizer4);
        vm.prank(authorizer3); multiSigner.removeSigner(authorizer4);
        assertEq(multiSigner.signaturesRequired(), 2);
        assertFalse(multiSigner.isSigner(authorizer4));

        // Now we have 3 signers. Any attempt to remove another must revert with lessThanMinSigners
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.lessThanMinSigners.selector);
        multiSigner.removeSigner(authorizer2);
    }

    function testAddThenRemove_Combination() public {
        address newSigner = makeAddr("newAuthorizer");
        // Add newGuy (3 votes required)
        vm.prank(authorizer1); multiSigner.addSigner(newSigner);
        vm.prank(authorizer2); multiSigner.addSigner(newSigner);
        vm.expectEmit(true, false, false, true);
        emit SignerAdded(newSigner);
        vm.prank(authorizer3); multiSigner.addSigner(newSigner);
        assertTrue(multiSigner.isSigner(newSigner));
        assertEq(multiSigner.signaturesRequired(), 3); // 5 signers => 3

        // Remove newGuy (still 3 votes required at 5 signers)
        vm.prank(authorizer1); multiSigner.removeSigner(newSigner);
        vm.prank(authorizer2); multiSigner.removeSigner(newSigner);
        vm.expectEmit(true, false, false, true);
        emit SignerRemoved(newSigner);
        vm.prank(authorizer3); multiSigner.removeSigner(newSigner);

        assertFalse(multiSigner.isSigner(newSigner));
        assertEq(multiSigner.signaturesRequired(), 3); // back to 4 signers => 3
    }

    function testBridge_IncreaseLockingCap_MajorityVoteAndExecutes() public {
        uint256 cap = 1_000_000 ether;
        // First vote
        vm.prank(authorizer1);
        multiSigner.increaseUnionBridgeLockingCap(cap);
        assertEq(bridgeAt.increaseUnionLockingCapNumberOfCalls(), 0);

        // Second vote
        vm.prank(authorizer2);
        multiSigner.increaseUnionBridgeLockingCap(cap);
        assertEq(bridgeAt.increaseUnionLockingCapNumberOfCalls(), 0);

        // Third vote triggers execution
        vm.prank(authorizer3);
        multiSigner.increaseUnionBridgeLockingCap(cap);
        assertEq(bridgeAt.increaseUnionLockingCapNumberOfCalls(), 1);
        assertEq(bridgeAt._unionBridgeLockingCap(), cap);
    }

    function testBridge_IncreaseLockingCap_OnlySignerAndNoDoubleVote() public {
        uint256 cap = 12345;
        // Non-signer cannot vote
        vm.prank(unauthorizedCaller);
        vm.expectRevert(MultiSigner.OnlySigner.selector);
        multiSigner.increaseUnionBridgeLockingCap(cap);

        // Same signer cannot vote twice on same param
        vm.prank(authorizer1);
        multiSigner.increaseUnionBridgeLockingCap(cap);
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.AlreadyVoted.selector);
        multiSigner.increaseUnionBridgeLockingCap(cap);
    }

    function testBridge_SetTransferPermissions_MajorityVoteAndExecutes() public {
        bool req = true;
        bool rel = false;
        // First vote
        vm.prank(authorizer1);
        multiSigner.setUnionBridgeTransferPermissions(req, rel);
        assertEq(bridgeAt.setTransferPermissionsNumberOfCalls(), 0);

        // Second vote
        vm.prank(authorizer2);
        multiSigner.setUnionBridgeTransferPermissions(req, rel);
        assertEq(bridgeAt.setTransferPermissionsNumberOfCalls(), 0);

        // Third vote triggers execution
        vm.prank(authorizer3);
        multiSigner.setUnionBridgeTransferPermissions(req, rel);
        assertEq(bridgeAt.setTransferPermissionsNumberOfCalls(), 1);
        assertEq(bridgeAt._requestEnabled(), req);
        assertEq(bridgeAt._releaseEnabled(), rel);
    }

    function testBridge_SetTransferPermissions_OnlySignerAndNoDoubleVote() public {
        bool req = false;
        bool rel = true;
        vm.prank(unauthorizedCaller);
        vm.expectRevert(MultiSigner.OnlySigner.selector);
        multiSigner.setUnionBridgeTransferPermissions(req, rel);

        vm.prank(authorizer2);
        multiSigner.setUnionBridgeTransferPermissions(req, rel);
        vm.prank(authorizer2);
        vm.expectRevert(MultiSigner.AlreadyVoted.selector);
        multiSigner.setUnionBridgeTransferPermissions(req, rel);
    }
}
