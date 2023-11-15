// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { SigUtils } from "test/utils/SigUtils.sol";

contract TestUsdnPermit is UsdnTokenFixture {
    SigUtils internal sigUtils;
    uint256 internal userPrivateKey;
    address internal user;

    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(usdn.DOMAIN_SEPARATOR());
        userPrivateKey = 0xA11CE;
        user = vm.addr(userPrivateKey);
    }

    function test_permit() public {
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(user, 100 ether);

        uint256 nonce = usdn.nonces(user);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(this),
            value: 100 ether,
            nonce: nonce,
            deadline: type(uint256).max
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Approval(user, address(this), 100 ether); // expected event
        usdn.permit(user, address(this), 100 ether, type(uint256).max, v, r, s);
        assertEq(usdn.allowance(user, address(this)), 100 ether);
        assertEq(usdn.nonces(user), nonce + 1);

        // transfer from
        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(user, USER_1, 100 ether); // expected event
        usdn.transferFrom(user, USER_1, 100 ether);
        assertEq(usdn.allowance(user, address(this)), 0);
    }
}
