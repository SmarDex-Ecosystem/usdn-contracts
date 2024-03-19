// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { WusdnTokenFixture } from "test/unit/WUSDN/utils/Fixtures.sol";

/**
 * @custom:feature Invariants of `WUSDN`
 * @custom:background  Given four users that can mint tokens to themselves, burn their balance of tokens, and transfer
 *  to other users. Fallow invariants in Wusdn
 */
contract TestWusdnInvariants is WusdnTokenFixture {
    uint256 internal constant INITIAL_WUSDN_DEPOSIT = 1 ether;

    function setUp() public override {
        super.setUp();
        usdn.approve(address(wusdn), type(uint256).max);
        wusdn.deposit(INITIAL_WUSDN_DEPOSIT, address(this));

        targetContract(address(usdn));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = usdn.rebaseTest.selector;
        selectors[1] = usdn.mintTest.selector;
        selectors[2] = usdn.burnTest.selector;
        selectors[3] = usdn.transferTest.selector;
        targetSelector(FuzzSelector({ addr: address(usdn), selectors: selectors }));
    }

    /**
     * @custom:scenario Check that the contract returns the expected total supply
     */
    function invariant_supply_wusdn() public {
        assertEq(wusdn.totalSupply(), usdn.sharesOf(address(wusdn)), "total supply");
    }

    /**
     * @custom:scenario Check that the contract returns the expected total assets
     */
    function invariant_total_assets_wusdn() public {
        assertEq(wusdn.totalAssets(), wusdn.convertToAssets(usdn.sharesOf(address(wusdn))), "total assets");
    }
}
