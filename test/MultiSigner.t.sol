// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MultiSigner} from "../src/MultSigner.sol";

contract MultiSignerTest is Test {
    MultiSigner multiSigner;

    address authorizer1;
    address authorizer2;
    address authorizer3;
    address outsider;

    function setUp() public {
        // Create deterministic addresses
        authorizer1 = makeAddr("authorizer1");
        authorizer2 = makeAddr("authorizer2");
        authorizer3 = makeAddr("authorizer3");
        outsider = makeAddr("outsider");

        address[] memory init = new address[](4);
        init[0] = authorizer1;
        init[1] = authorizer2;
        init[2] = authorizer3;

        // Deploy from this contract; owner = address(this)
        multiSigner = new MultiSigner(init);
    }

    function testConstructor_RevertWhenTooFewSigners() public {
        address[] memory init = new address[](2); // minSigners = 3, revert when < 3
        init[0] = makeAddr("authorizer1");
        init[1] = makeAddr("authorizer2");

        vm.expectRevert(MultiSigner.lessThanMinSigners.selector);
        new MultiSigner(init);
    }

    function testConstructor_RevertWhenZeroAddress() public {
        address[] memory init = new address[](4);
        init[0] = address(0);
        init[1] = makeAddr("b1");
        init[2] = makeAddr("b2");
        init[3] = makeAddr("b3");

        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        new MultiSigner(init);
    }

    function testConstructor_RevertWhenOwnerIncluded() public {
        // Owner is address(this) during deployment
        address[] memory init = new address[](4);
        init[0] = makeAddr("b1");
        init[1] = makeAddr("b2");
        init[2] = makeAddr("b3");
        init[3] = address(this);

        vm.expectRevert(MultiSigner.InvalidSigner.selector);
        new MultiSigner(init);
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
        address newSigner = makeAddr("newSigner");

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
        emit MultiSigner.SignerAdded(newSigner);
        // Third vote by authorizer3 triggers addition
        vm.prank(authorizer3);
        multiSigner.addSigner(newSigner);

        assertTrue(multiSigner.isSigner(newSigner));
        // New total signers = 5 => signaturesRequired = (5/2)+1 = 3
        assertEq(multiSigner.signaturesRequired(), 3);
    }

    function testAddSigner_OnlySignerCanVote() public {
        address newSigner = makeAddr("newbie");
        vm.prank(outsider);
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
        address newSigner = makeAddr("dup");
        vm.prank(authorizer1);
        multiSigner.addSigner(newSigner);
        // authorizer1 votes again
        vm.prank(authorizer1);
        vm.expectRevert(MultiSigner.AlreadyVoted.selector);
        multiSigner.addSigner(newSigner);
    }
}
