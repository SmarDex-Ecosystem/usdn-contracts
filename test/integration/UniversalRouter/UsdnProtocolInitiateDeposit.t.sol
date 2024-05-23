// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { DepositPendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract TestForkUniversalRouterInitiateDeposit is UniversalRouterBaseFixture {
    uint256 constant DEPOSIT_AMOUNT = 0.1 ether;

    function setUp() public {
        _setUp();
        deal(address(wstETH), address(this), DEPOSIT_AMOUNT * 2);
        deal(address(sdex), address(this), 1e6 ether);
    }

    function test_ForkInitiateDeposit() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 wstEthBalanceBefore = wstETH.balanceOf(address(this));
        uint256 sdexBalanceBefore = sdex.balanceOf(address(this));

        // send funds to router
        wstETH.transfer(address(router), DEPOSIT_AMOUNT);
        // we send too much sdex because value is kinda hard to know in advance
        sdex.transfer(address(router), sdexBalanceBefore);

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(DEPOSIT_AMOUNT, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        DepositPendingAction memory action =
            protocol.i_toDepositPendingAction(protocol.getUserPendingAction(address(this)));

        assertEq(action.to, USER_1, "pending action to");
        assertEq(action.validator, address(this), "pending action validator");
        assertEq(action.amount, DEPOSIT_AMOUNT, "pending action amount");

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
        assertEq(wstETH.balanceOf(address(this)), wstEthBalanceBefore - DEPOSIT_AMOUNT, "asset balance");

        uint256 tempUsdnToMint =
            protocol.i_calcMintUsdn(DEPOSIT_AMOUNT, action.balanceVault, action.usdnTotalSupply, action.assetPrice);
        uint256 burntSdex = protocol.i_calcSdexToBurn(tempUsdnToMint, protocol.getSdexBurnOnDepositRatio());

        assertEq(sdex.balanceOf(address(this)), sdexBalanceBefore - burntSdex, "sdex balance");
    }

    function test_ForkInitiateDepositAssetSweep() public {
        uint256 wstEthBalanceBefore = wstETH.balanceOf(address(this));

        // send too much wstETH
        wstETH.transfer(address(router), DEPOSIT_AMOUNT * 2);
        sdex.transfer(address(router), sdex.balanceOf(address(this)));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(DEPOSIT_AMOUNT, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(wstETH.balanceOf(address(this)), wstEthBalanceBefore - DEPOSIT_AMOUNT, "asset balance");
    }

    function test_ForkInitiateDepositEtherSweep() public {
        uint256 ethBalanceBefore = address(this).balance;

        // send assets
        wstETH.transfer(address(router), DEPOSIT_AMOUNT);
        sdex.transfer(address(router), sdex.balanceOf(address(this)));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(DEPOSIT_AMOUNT, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution (send too much eth)
        router.execute{ value: protocol.getSecurityDepositValue() * 2 }(commands, inputs);

        assertEq(address(this).balance, ethBalanceBefore - protocol.getSecurityDepositValue(), "ether balance");
    }

    function test_ForkInitiateDepositFullBalance() public {
        uint256 wstEthBalanceBefore = wstETH.balanceOf(address(this));

        // send assets to the router
        wstETH.transfer(address(router), DEPOSIT_AMOUNT);
        sdex.transfer(address(router), sdex.balanceOf(address(this)));

        // commands
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));

        // inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(Constants.CONTRACT_BALANCE, USER_1, address(this), "", EMPTY_PREVIOUS_DATA);

        // execution
        router.execute{ value: protocol.getSecurityDepositValue() }(commands, inputs);

        assertEq(wstETH.balanceOf(address(this)), wstEthBalanceBefore - DEPOSIT_AMOUNT, "asset balance");
    }

    receive() external payable { }
}
