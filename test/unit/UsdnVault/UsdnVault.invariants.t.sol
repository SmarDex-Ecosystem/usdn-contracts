// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { USER_1, USER_2, USER_3, USER_4 } from "test/utils/Constants.sol";
import { UsdnVaultFixture } from "test/unit/UsdnVault/utils/Fixtures.sol";

/**
 * @custom:feature Invariants of USDN
 * @custom:background Given four users that can mint tokens to themselves, burn their balance of tokens, and transfer
 *  to other users
 */
contract TestUsdnInvariants is UsdnVaultFixture {
    function setUp() public override {
        super.setUp();

        vm.deal(address(usdnVault), type(uint256).max);
        vm.deal(address(this), type(uint256).max);

        targetContract(address(usdnVault));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = usdnVault.openLongTestWithValue.selector;
        selectors[1] = usdnVault.closeLongTestWithValue.selector;
        selectors[2] = usdnVault.validateLongTestWithValue.selector;

        targetSelector(FuzzSelector({ addr: address(usdnVault), selectors: selectors }));
    }

    /// @custom:scenario Check that the contract returns the expected number of shares for each user
    function invariant_balanceLong() public displayLongBalances {
        assertEq(computedLongBalance(), usdnVault.balanceLong());
    }

    /* -------------------------------------------------------------------------- */
    /*                              Private functions                             */
    /* -------------------------------------------------------------------------- */

    function computedLongBalance() private returns (uint256){
        (,,,,, uint256 amount1,,,,,) = usdnVault.positionsTest(USER_1);
        (,,,,, uint256 amount2,,,,,) = usdnVault.positionsTest(USER_2);
        (,,,,, uint256 amount3,,,,,) = usdnVault.positionsTest(USER_3);
        (,,,,, uint256 amount4,,,,,) = usdnVault.positionsTest(USER_4);

        return amount1 + amount2 + amount3 + amount4;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Modifier                                  */
    /* -------------------------------------------------------------------------- */

    modifier displayLongBalances() {
        // console2.log("USER_1 positions", usdn.balanceOf(USER_1));
        // console2.log("USER_2 balance", usdn.balanceOf(USER_2));
        // console2.log("USER_3 balance", usdn.balanceOf(USER_3));
        // console2.log("USER_4 balance", usdn.balanceOf(USER_4));
        // console2.log("USER_1 shares ", usdn.sharesOf(USER_1));
        // console2.log("USER_2 shares ", usdn.sharesOf(USER_2));
        // console2.log("USER_3 shares ", usdn.sharesOf(USER_3));
        // console2.log("USER_4 shares ", usdn.sharesOf(USER_4));
        _;
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
