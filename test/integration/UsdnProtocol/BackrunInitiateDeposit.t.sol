// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../../unit/UsdnProtocol/utils/Fixtures.sol";
import { USER_1 } from "../../utils/Constants.sol";

import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";

/**
 * @custom:feature Testing outcomes of backrunning a user's initiateDeposit action
 * @custom:background Given a protocol initialized with a bit more long balance (3%)
 * @custom:and long fees, protocol fees, sdex burn and imbalance limits are enabled
 */
contract TestDepositBackrun is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSdexBurnOnDeposit = true;
        params.flags.enablePositionFees = true;
        params.flags.enableProtocolFees = true;
        params.flags.enableLimits = true;
        params.initialPrice = 2000 ether;
    }

    function manualSetUp(SetUpParams memory params) public {
        // less long balance to have more freedom with imbalance
        params.initialLong = params.initialDeposit * 103 / 100;
        super._setUp(params);

        usdn.approve(address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), 200_000_000 ether, address(protocol), type(uint256).max);

        vm.prank(USER_1);
        usdn.approve(address(protocol), type(uint256).max);
        sdex.mintAndApprove(USER_1, 200_000_000 ether, address(protocol), type(uint256).max);
    }

    /**
     * @notice Scenario to repeat for each test case
     * @param userDeposit The amount of assets the victim should deposit
     * @param attackerDeposit The amount of assets the attacker should deposit
     * @param priceForAttacker The price of the asset during the attacker's deposit
     */
    function backrunScenario(uint128 userDeposit, uint128 attackerDeposit, uint128 priceForAttacker) internal {
        emit log_named_decimal_uint("vault balance        ", protocol.getBalanceVault(), 18);
        uint256 priceIncreaseBps = (priceForAttacker - params.initialPrice) * 10_000 / params.initialPrice;
        emit log_named_decimal_uint("price increase (%)   ", priceIncreaseBps, 2);
        emit log_named_decimal_uint("user deposit         ", userDeposit, 18);
        emit log_named_decimal_uint("attacker deposit     ", attackerDeposit, 18);

        skip(1 hours);
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, userDeposit, params.initialPrice);
        skip(10 minutes);
        protocol.liquidate(abi.encode(priceForAttacker));
        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, attackerDeposit, priceForAttacker);
        protocol.validateDeposit(payable(this), abi.encode(params.initialPrice), EMPTY_PREVIOUS_DATA);

        /* -------------------------------- backrun -------------------------------- */
        vm.startPrank(USER_1);
        protocol.initiateWithdrawal(
            uint152(usdn.sharesOf(USER_1)),
            0,
            USER_1,
            USER_1,
            block.timestamp,
            abi.encode(priceForAttacker),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        uint256 balanceBefore = wstETH.balanceOf(USER_1);
        protocol.validateWithdrawal(USER_1, abi.encode(priceForAttacker), EMPTY_PREVIOUS_DATA);
        vm.stopPrank();
        uint256 withdrawn = wstETH.balanceOf(USER_1) - balanceBefore;
        emit log_named_decimal_uint("attacker withdraw    ", withdrawn, 18);
        emit log_named_decimal_int(
            "attacker profits (%)", (int256(withdrawn) - int128(attackerDeposit)) * 10_000 / int128(attackerDeposit), 2
        );

        /* ------------------------ First depositor withdraw ------------------------ */
        protocol.initiateWithdrawal(
            uint152(usdn.sharesOf(address(this))),
            0,
            address(this),
            payable(this),
            block.timestamp,
            abi.encode(priceForAttacker),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        balanceBefore = wstETH.balanceOf(address(this));
        protocol.validateWithdrawal(payable(this), abi.encode(priceForAttacker), EMPTY_PREVIOUS_DATA);
        withdrawn = wstETH.balanceOf(address(this)) - balanceBefore;
        emit log_named_decimal_uint("user withdraw        ", withdrawn, 18);
        emit log_named_decimal_int(
            "user profits (%)     ", (int256(withdrawn) - int128(userDeposit)) * 10_000 / int128(userDeposit), 2
        );
    }

    /**
     * @custom:scenario A user's deposit transaction got backrun
     * @custom:given A small vault balance, a small user deposit and a small price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_SmallVaultBalance_SmallDeposit_SmallPriceIncrease() public {
        params.initialDeposit = 30 ether;
        manualSetUp(params);

        uint128 newPrice = 2040 ether;
        backrunScenario(0.1 ether, 1.5 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A small vault balance, a small user deposit and a big price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_SmallVaultBalance_SmallDeposit_BigPriceIncrease() public {
        params.initialDeposit = 30 ether;
        manualSetUp(params);

        uint128 newPrice = 2300 ether;
        backrunScenario(0.1 ether, 1.5 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A small vault balance, a big user deposit and a small price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_SmallVaultBalance_BigDeposit_SmallPriceIncrease() public {
        params.initialDeposit = 30 ether;
        manualSetUp(params);

        uint128 newPrice = 2040 ether;
        backrunScenario(1.5 ether, 0.1 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A small vault balance, a big user deposit and a big price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_SmallVaultBalance_BigDeposit_BigPriceIncrease() public {
        params.initialDeposit = 30 ether;
        manualSetUp(params);

        uint128 newPrice = 2300 ether;
        backrunScenario(1.5 ether, 0.1 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A big vault balance, a big user deposit and a big price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_BigVaultBalance_BigDeposit_BigPriceIncrease() public {
        params.initialDeposit = 500 ether;
        manualSetUp(params);

        uint128 newPrice = 2300 ether;
        backrunScenario(24 ether, 4 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A big vault balance, a big user deposit and a small price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_BigVaultBalance_BigDeposit_SmallPriceIncrease() public {
        params.initialDeposit = 500 ether;
        manualSetUp(params);

        uint128 newPrice = 2040 ether;
        backrunScenario(24 ether, 4 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A big vault balance, a small user deposit and a big price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_BigVaultBalance_SmallDeposit_BigPriceIncrease() public {
        params.initialDeposit = 500 ether;
        manualSetUp(params);

        uint128 newPrice = 2300 ether;
        backrunScenario(4 ether, 24 ether, newPrice);
    }

    /**
     * @custom:scenario A user's deposit transaction gets backrun
     * @custom:given A big vault balance, a small user deposit and a small price increase
     * @custom:when An attacker backruns the validate deposit of the user
     * @custom:then The outcome is outputted
     */
    function test_Backrun_BigVaultBalance_SmallDeposit_SmallPriceIncrease() public {
        params.initialDeposit = 500 ether;
        manualSetUp(params);

        uint128 newPrice = 2040 ether;
        backrunScenario(4 ether, 24 ether, newPrice);
    }

    receive() external payable { }
}
