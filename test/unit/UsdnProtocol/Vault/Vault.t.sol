// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1, USER_2 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the functions in the vault contract
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolVault is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the splitting of the withdrawal shares amount into two parts
     * @custom:given An amount to be split in the range of uint152
     * @custom:when The amount is split with the protocol function and then merged back
     * @custom:then The original amount should be the same as the input
     * @param amount The amount to be split and merged
     */
    function testFuzz_withdrawalAmountSplitting(uint152 amount) public view {
        uint24 lsb = protocol.i_calcWithdrawalAmountLSB(amount);
        uint128 msb = protocol.i_calcWithdrawalAmountMSB(amount);
        uint256 res = protocol.i_mergeWithdrawalAmountParts(lsb, msb);
        assertEq(res, amount, "Amount splitting and merging failed");
    }

    /**
     * @custom:scenario Check the inherent loss of the vault position after a rebase compared to the inherent gain of
     * the long position
     * @custom:given A vault position and a long position
     * @custom:when The price of the asset changes after a rebase of stETH/wstETH
     * @custom:then The vault position should have an inherent loss and the long position should have an inherent gain
     */
    function test_vaultPositionInherentLossAfterRebase() public view {
        uint256 balanceUserOutsideProtocol = protocol.getBalanceVault();
        uint128 newPrice = 2200 ether;

        uint256 longAssetAvailableAfterRebase = uint256(protocol.i_longAssetAvailable(newPrice));
        uint256 vaultAssetAvailableAfterRebase = uint256(protocol.i_vaultAssetAvailable(newPrice));

        uint256 valueLongAfterRebase = longAssetAvailableAfterRebase * newPrice;
        uint256 valueVaultAfterRebase = vaultAssetAvailableAfterRebase * newPrice;
        uint256 valueUserAfterRebase = balanceUserOutsideProtocol * newPrice;

        assertGt(valueLongAfterRebase, valueUserAfterRebase, "User outside protocol is a loser over the long position");
        assertLt(
            valueVaultAfterRebase, valueUserAfterRebase, "User outside protocol is a winner over the vault position"
        );
        // Long positions are inherently profitable due to the stETh/wstETH rebase and the vault positions are
        // inherently lossy due to the same rebase
    }

    function test_multipleWithdrawAgainstOne() public {
        // sdex.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        // wstETH.mintAndApprove(USER_1, 100 ether, address(protocol), type(uint256).max);
        bytes memory encodedPrice = abi.encode(params.initialPrice);
        address USER_1_2ND_ADDR = USER_2;

        setUpUserPositionInVault(USER_1, ProtocolAction.ValidateDeposit, 10 ether, params.initialPrice);
        uint256 user1SharesBefore = usdn.sharesOf(USER_1);
        uint256 securityDeposit = protocol.getSecurityDepositValue();

        uint256 id = vm.snapshot();

        vm.startPrank(USER_1);
        protocol.initiateWithdrawal{ value: securityDeposit }(
            uint152(user1SharesBefore),
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            payable(USER_1),
            type(uint256).max,
            encodedPrice,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();
        protocol.validateWithdrawal(payable(USER_1), encodedPrice, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        uint256 user1BalanceOneWithdraw = wstETH.balanceOf(USER_1);

        vm.revertTo(id);

        vm.startPrank(USER_1);
        protocol.initiateWithdrawal{ value: securityDeposit }(
            uint152(user1SharesBefore / 2),
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            payable(USER_1),
            type(uint256).max,
            encodedPrice,
            EMPTY_PREVIOUS_DATA
        );
        protocol.initiateWithdrawal{ value: securityDeposit }(
            uint152(usdn.sharesOf(USER_1)),
            DISABLE_AMOUNT_OUT_MIN,
            USER_1,
            payable(USER_1_2ND_ADDR),
            type(uint256).max,
            encodedPrice,
            EMPTY_PREVIOUS_DATA
        );
        vm.stopPrank();
        _waitDelay();

        vm.startPrank(USER_1);
        protocol.validateWithdrawal(payable(USER_1), encodedPrice, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();
        vm.startPrank(USER_1_2ND_ADDR);
        protocol.validateWithdrawal(payable(USER_1_2ND_ADDR), encodedPrice, EMPTY_PREVIOUS_DATA);
        vm.stopPrank();

        uint256 user1BalanceTwoWithdraw = wstETH.balanceOf(USER_1);

        emit log_named_uint("user1BalanceOneWithdraw", user1BalanceOneWithdraw);
        emit log_named_uint("user1BalanceTwoWithdraw", user1BalanceTwoWithdraw);
    }
}
