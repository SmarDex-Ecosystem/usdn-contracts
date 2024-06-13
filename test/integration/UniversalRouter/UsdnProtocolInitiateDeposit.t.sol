// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Constants } from "@uniswap/universal-router/contracts/libraries/Constants.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UniversalRouterBaseFixture } from "test/integration/UniversalRouter/utils/Fixtures.sol";

import { Commands } from "src/UniversalRouter/libraries/Commands.sol";
import { DepositPendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Initiating a deposit through the router
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUniversalRouterInitiateDeposit is UniversalRouterBaseFixture {
    uint256 constant DEPOSIT_AMOUNT = 0.1 ether;
    uint256 internal _securityDeposit;

    function setUp() public {
        _setUp();
        deal(address(wstETH), address(this), DEPOSIT_AMOUNT * 2);
        deal(address(sdex), address(this), 1e6 ether);
        _securityDeposit = protocol.getSecurityDepositValue();
    }

    /**
     * @custom:scenario Initiating a deposit through the router
     * @custom:given The user sent the exact amount of assets and exact amount of SDEX to the router
     * @custom:when The user initiates a deposit through the router
     * @custom:then The deposit is initiated successfully
     */
    function test_ForkInitiateDeposit() public {
        wstETH.transfer(address(router), DEPOSIT_AMOUNT);
        _transferSdex(DEPOSIT_AMOUNT);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] =
            abi.encode(DEPOSIT_AMOUNT, USER_1, address(this), NO_PERMIT2, "", EMPTY_PREVIOUS_DATA, _securityDeposit);
        router.execute{ value: _securityDeposit }(commands, inputs);

        DepositPendingAction memory action =
            protocol.i_toDepositPendingAction(protocol.getUserPendingAction(address(this)));

        assertEq(action.to, USER_1, "pending action to");
        assertEq(action.validator, address(this), "pending action validator");
        assertEq(action.amount, DEPOSIT_AMOUNT, "pending action amount");
    }

    /**
     * @custom:scenario Initiating a deposit through the router with a "full balance" amount
     * @custom:given The user sent the `DEPOSIT_AMOUNT` of wstETH to the router
     * @custom:when The user initiates a deposit through the router with amount `CONTRACT_BALANCE`
     * @custom:then The deposit is initiated successfully with the full balance of the router
     * @custom:and The user's asset balance is reduced by `DEPOSIT_AMOUNT`
     */
    function test_ForkInitiateDepositFullBalance() public {
        uint256 wstEthBalanceBefore = wstETH.balanceOf(address(this));

        wstETH.transfer(address(router), DEPOSIT_AMOUNT);
        _transferSdex(DEPOSIT_AMOUNT);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.INITIATE_DEPOSIT)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            Constants.CONTRACT_BALANCE, USER_1, address(this), NO_PERMIT2, "", EMPTY_PREVIOUS_DATA, _securityDeposit
        );
        router.execute{ value: _securityDeposit }(commands, inputs);

        assertEq(wstETH.balanceOf(address(this)), wstEthBalanceBefore - DEPOSIT_AMOUNT, "asset balance");
    }

    function _transferSdex(uint256 depositAmount) internal returns (uint256 sdexToBurn_) {
        uint256 usdnSharesToMintEstimated = protocol.i_calcMintUsdnShares(
            depositAmount, protocol.getBalanceVault(), usdn.totalShares(), params.initialPrice
        );
        uint256 usdnToMintEstimated = usdn.convertToTokens(usdnSharesToMintEstimated);
        sdexToBurn_ = protocol.i_calcSdexToBurn(usdnToMintEstimated, protocol.getSdexBurnOnDepositRatio());
        sdex.transfer(address(router), sdexToBurn_);
    }

    receive() external payable { }
}
