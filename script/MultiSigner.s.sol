// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MultiSigner} from "../src/MultiSigner.sol";
import {Script} from "forge-std/Script.sol";

contract MultiSignerScript is Script {
    MultiSigner public multiSigner;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address authorizer1 = makeAddr("authorizer1");
        address authorizer2 = makeAddr("authorizer2");
        address authorizer3 = makeAddr("authorizer3");

        address[] memory initAuthorizers = new address[](3);
        initAuthorizers[0] = authorizer1;
        initAuthorizers[1] = authorizer2;
        initAuthorizers[2] = authorizer3;

        multiSigner = new MultiSigner(
            initAuthorizers
        );

        vm.stopBroadcast();
    }
}
