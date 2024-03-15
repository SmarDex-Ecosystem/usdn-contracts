// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import {
    ProtocolAction,
    LongPendingAction,
    Position,
    PendingAction
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The open position function of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolOpenPosition is UsdnProtocolBaseFixture {
    uint256 internal SECURITY_DEPOSIT_VALUE;
    bytes priceData;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);
        priceData = abi.encode(params.initialPrice);

        SECURITY_DEPOSIT_VALUE = protocol.getSecurityDepositValue();
        assertGt(SECURITY_DEPOSIT_VALUE, 0);
    }

    function test_securityDeposit_deposit() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;
        protocol.initiateDeposit{ value: SECURITY_DEPOSIT_VALUE }(1 ether, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    function test_securityDeposit_withdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        uint256 balanceOf = usdn.balanceOf(address(this));
        usdn.approve(address(protocol), balanceOf);
        protocol.initiateWithdrawal{ value: SECURITY_DEPOSIT_VALUE }(uint128(balanceOf), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    function test_securityDeposit_openPosition() public {
        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            1 ether, params.initialPrice / 2, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    function test_securityDeposit_closePosition() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        uint256 balanceSenderBefore = address(this).balance;
        uint256 balanceProtocolBefore = address(protocol).balance;

        protocol.initiateClosePosition{ value: SECURITY_DEPOSIT_VALUE }(
            tick, tickVersion, index, 1 ether, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        assertEq(address(this).balance, balanceSenderBefore - SECURITY_DEPOSIT_VALUE);
        assertEq(address(protocol).balance, balanceProtocolBefore + SECURITY_DEPOSIT_VALUE);

        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);

        assertEq(address(this).balance, balanceSenderBefore);
        assertEq(address(protocol).balance, balanceProtocolBefore);
    }

    receive() external payable { }
}
