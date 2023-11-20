// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";

import { USER_1 } from "test/utils/Constants.sol";
import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { SigUtils } from "test/utils/SigUtils.sol";

/// Test the `permit` function.
contract TestUsdnPermit is UsdnTokenFixture {
    SigUtils internal sigUtils;
    uint256 internal userPrivateKey;
    address internal user;

    /// We need a user for which we know the private key
    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(usdn.DOMAIN_SEPARATOR());
        (user, userPrivateKey) = makeAddrAndKey("alice");
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(user, 100 ether);
    }

    /// Check that the domain separator is correct
    function test_domainSeparator() public {
        assertEq(usdn.DOMAIN_SEPARATOR(), hex"788006238c8d8eb7589a46d342d5e773630b340060ab348e6e4f155e72c651de");
    }

    /**
     * Test that a permit can be redeemed by the token to increase the allowance of a contract.
     *
     * A `transferFrom` call is then make to ensure proper allowance management.
     */
    function test_permit() public {
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

    function test_RevertWhen_signatureIsOutdated() public {
        uint256 nonce = usdn.nonces(user);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(this),
            value: 100 ether,
            nonce: nonce,
            deadline: block.timestamp - 1
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSelector(ERC2612ExpiredSignature.selector, block.timestamp - 1));
        usdn.permit(user, address(this), 100 ether, block.timestamp - 1, v, r, s);
    }

    function test_RevertWhen_invalidSigner() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: user,
            spender: address(this),
            value: 100 ether,
            nonce: 0,
            deadline: type(uint256).max
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (address bob, uint256 bobPrivateKey) = makeAddrAndKey("bob");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSelector(ERC2612InvalidSigner.selector, bob, user));
        usdn.permit(user, address(this), 100 ether, type(uint256).max, v, r, s);
    }
}
