// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { USER_1 } from "../../../utils/Constants.sol";
import { OracleMiddlewareBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/// @custom:feature The pausable functions of `OracleMiddleware`
contract TestOracleMiddlewarePythFeedId is OracleMiddlewareBaseFixture, Pausable {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @custom:scenario Pause the oracle middleware
     * @custom:given An unpaused oracle middleware
     * @custom:when `pausePriceValidation` is called
     * @custom:then It should emit a `Paused` event
     * @custom:and `paused` should return `true`
     */
    function test_canPauseValidation() public {
        vm.expectEmit();
        emit Paused(address(this));
        oracleMiddleware.pausePriceValidation();

        assertEq(oracleMiddleware.paused(), true);
    }

    /**
     * @custom:scenario Unpause the oracle middleware
     * @custom:given A paused oracle middleware
     * @custom:when `unpausePriceValidation` is called
     * @custom:then It should emit a `Unpaused` event
     * @custom:and `paused` should return `false`
     */
    function test_canUnpauseValidation() public {
        oracleMiddleware.pausePriceValidation();
        assertEq(oracleMiddleware.paused(), true);

        vm.expectEmit();
        emit Unpaused(address(this));
        oracleMiddleware.unpausePriceValidation();
        assertEq(oracleMiddleware.paused(), false);
    }

    /**
     * @custom:scenario Pause the oracle middleware and call `parseAndValidatePrice`
     * @custom:given A paused oracle middleware
     * @custom:when parseAndValidatePrice is called
     * @custom:then It should revert with `EnforcedPause`
     */
    function test_RevertWhen_callPriceValidationInPause() public {
        oracleMiddleware.pausePriceValidation();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        oracleMiddleware.parseAndValidatePrice("", 0, Types.ProtocolAction.InitiateDeposit, "");
    }

    /**
     * @custom:scenario Pause and unpause the oracle middleware with a non-admin account
     * @custom:given An unpaused oracle middleware
     * @custom:when `pausePriceValidation` is called by a non-admin account
     * @custom:then It should revert with `OwnableUnauthorizedAccount`
     * @custom:and `unpausePriceValidation` is called by a non-admin account
     * @custom:then It should revert with `OwnableUnauthorizedAccount`
     */
    function test_RevertWhen_PauseAndUnpauseByNonAdmin() public {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        oracleMiddleware.pausePriceValidation();

        oracleMiddleware.pausePriceValidation();

        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER_1));
        oracleMiddleware.unpausePriceValidation();
    }
}
