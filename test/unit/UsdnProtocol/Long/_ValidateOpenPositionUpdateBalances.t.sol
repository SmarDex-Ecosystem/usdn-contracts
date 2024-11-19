// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature the {_validateOpenPositionUpdateBalances} internal
 * function of the {UsdnProtocolActionsLongLibrary} library
 */
contract TestUsdnProtocolValidateOpenPositionUpdateBalances is UsdnProtocolBaseFixture {
    uint256 _initialBalanceVault;
    uint256 _initialBalanceLong;
    uint256 _allBalances;
    uint256 _newPosValue;
    uint256 _oldPosValue;

    uint256 internal constant ONE_WEI = 1;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        _initialBalanceVault = protocol.getBalanceVault();
        _initialBalanceLong = protocol.getBalanceLong();
        _allBalances = _initialBalanceVault + _initialBalanceLong;
        assertTrue(_initialBalanceVault > 0 && _initialBalanceLong > 0, "Initial balances should not be 0");
    }

    /**
     * @custom:scenario Validates position balances for a {_newPosValue} equal a wei
     * @custom:given The initial protocol balances
     * @custom:when The function {_validateOpenPositionUpdateBalance} is called
     * @custom:then The {_balanceLong} should be incremented by a wei
     * @custom:and The {_balanceVault} should be decremented by a wei
     */
    function test_validateOpenPositionUpdateBalanceNewPosValueOneWei() external {
        _newPosValue = ONE_WEI;
        protocol.i_validateOpenPositionUpdateBalances(_newPosValue, 0);
        assertEq(
            protocol.getBalanceLong(), _initialBalanceLong + ONE_WEI, "balance long should be incremented by a wei"
        );
        assertEq(
            protocol.getBalanceVault(), _initialBalanceVault - ONE_WEI, "balance vault should be decremented by a wei"
        );
    }

    /**
     * @custom:scenario Validates position balances for a {_newPosValue} greater than the vault balance
     * @custom:given The initial protocol balances
     * @custom:when The function {_validateOpenPositionUpdateBalance} is called
     * @custom:then The {_balanceLong} should be clamped with the sum of initial balances
     * @custom:and The {_balanceVault} should be equal 0
     */
    function test_validateOpenPositionUpdateBalanceNewPosValueGtVaultBalance() external {
        _newPosValue = _initialBalanceVault + ONE_WEI;
        protocol.i_validateOpenPositionUpdateBalances(_newPosValue, 0);
        assertEq(protocol.getBalanceLong(), _allBalances, "should be clamped with the sum of initial balances");
        assertEq(protocol.getBalanceVault(), 0, "should be equal 0");
    }

    /**
     * @custom:scenario Validates position balances for a {_oldPosValue} equal a wei
     * @custom:given The initial protocol balances
     * @custom:when The function {_validateOpenPositionUpdateBalance} is called
     * @custom:then The {_balanceVault} should be incremented by a wei
     * @custom:and The {_balanceLong} should be decremented by a wei
     */
    function test_validateOpenPositionUpdateBalanceOldPosValueOneWei() external {
        _oldPosValue = ONE_WEI;
        protocol.i_validateOpenPositionUpdateBalances(0, _oldPosValue);
        assertEq(
            protocol.getBalanceVault(), _initialBalanceVault + ONE_WEI, "balance vault should be incremented by a wei"
        );
        assertEq(
            protocol.getBalanceLong(), _initialBalanceLong - ONE_WEI, "balance long should be decremented by a wei"
        );
    }

    /**
     * @custom:scenario Validates position balances for a {_oldPosValue} greater than the long balance
     * @custom:given The initial protocol balances
     * @custom:when The function {_validateOpenPositionUpdateBalance} is called
     * @custom:then The {_balanceVault} should be clamped with the sum of initial balances
     * @custom:and The {_balanceLong} should be equal 0
     */
    function test_validateOpenPositionUpdateBalanceOldPosValueGtLongBalance() external {
        _oldPosValue = _initialBalanceLong + ONE_WEI;
        protocol.i_validateOpenPositionUpdateBalances(_newPosValue, _oldPosValue);
        assertEq(protocol.getBalanceVault(), _allBalances, "should be clamped with the sum of initial balances");
        assertEq(protocol.getBalanceLong(), 0, "should be equal 0");
    }
}
