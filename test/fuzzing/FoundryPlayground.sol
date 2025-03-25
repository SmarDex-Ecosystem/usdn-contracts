// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "./reproducers/Reproducers.sol";

contract FoundryPlayground is Reproducers {
    using SignedMath for int256;

    function setUp() public {
        vm.warp(1_524_785_992); //echidna starting time
        setup(address(this));
    }

    function test_depositing() public {
        fuzz_guided_addLP();

        setActor(getRandomUser(1)); //same initiator + validator
        fuzz_initiateDeposit(uint256(1) * 1e18, 1);

        setActor(getRandomUser(1));
        fuzz_validateDeposit();
    }

    function test_openPosition() public {
        fuzz_guided_addLP();
        fuzz_guided_openPosition(1);
    }

    function test_price() public {
        pumpPrice(20);
        crashPrice(20);
    }
}
