// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../utils/Constants.sol";
import { PermitSigUtils } from "../../utils/PermitSigUtils.sol";
import { UsdnTokenFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The `permit` function of `USDN`
 * @custom:background Given a user with 100 tokens
 * @custom:and A user `alice` with a private key
 */
contract TestUsdnPermit is UsdnTokenFixture {
    PermitSigUtils internal sigUtils;
    uint256 internal userPrivateKey;
    address internal user;

    function setUp() public override {
        super.setUp();
        sigUtils = new PermitSigUtils(usdn.DOMAIN_SEPARATOR());
        (user, userPrivateKey) = makeAddrAndKey("alice");
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.mint(user, 100 ether);
    }

    /**
     * @custom:scenario Getting the domain separator
     * @custom:when The domain separator is retrieved
     * @custom:then The domain separator is equal to the expected value
     */
    function test_domainSeparator() public view {
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        assertEq(
            usdn.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    typeHash,
                    keccak256(bytes("Ultimate Synthetic Delta Neutral")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(usdn)
                )
            )
        );
    }

    /**
     * @custom:scenario Permitting a spender
     * @custom:given Alice has signed a permit for this contract to spend 100 tokens
     * @custom:when This contract calls the `permit` function with the signature of Alice
     * @custom:then The `Approval` event is emitted with Alice as the owner, this contract as the spender and amount 100
     * tokens
     * @custom:and The allowance of Alice for this contract is 100 tokens
     * @custom:and The nonce of Alice is incremented
     */
    function test_permit() public {
        uint256 nonce = usdn.nonces(user);

        PermitSigUtils.Permit memory permit = PermitSigUtils.Permit({
            owner: user,
            spender: address(this),
            value: 100 ether,
            nonce: nonce,
            deadline: type(uint256).max
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectEmit(address(usdn));
        emit Approval(user, address(this), 100 ether); // expected event
        usdn.permit(user, address(this), 100 ether, type(uint256).max, v, r, s);
        assertEq(usdn.allowance(user, address(this)), 100 ether, "allowance");
        assertEq(usdn.nonces(user), nonce + 1, "nonce");
    }

    /**
     * @custom:scenario Transferring tokens with a permit
     * @custom:given Alice has signed a permit for this contract to spend 100 tokens
     * @custom:and This contract has used the signature to get an allowance of 100 tokens
     * @custom:when This contract calls the `transferFrom` function with Alice as the sender, another user as the
     * recipient and amount 100 tokens
     * @custom:then The `Transfer` event is emitted with Alice as the sender, the other user as the recipient and amount
     * 100 tokens
     * @custom:and The allowance of Alice for this contract is zero
     */
    function test_permitTransfer() public {
        uint256 nonce = usdn.nonces(user);

        PermitSigUtils.Permit memory permit = PermitSigUtils.Permit({
            owner: user,
            spender: address(this),
            value: 100 ether,
            nonce: nonce,
            deadline: type(uint256).max
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        usdn.permit(user, address(this), 100 ether, type(uint256).max, v, r, s);

        // transfer from
        vm.expectEmit(address(usdn));
        emit Transfer(user, USER_1, 100 ether); // expected event
        usdn.transferFrom(user, USER_1, 100 ether);

        assertEq(usdn.allowance(user, address(this)), 0);
    }

    /**
     * @custom:scenario Permitting a spender with a deadline
     * @custom:given Alice has signed a permit for this contract to spend 100 tokens with a timestamp in the past
     * @custom:when This contract calls the `permit` function with the signature of Alice
     * @custom:then The transaction reverts with the `ERC2612ExpiredSignature` error
     */
    function test_RevertWhen_signatureIsOutdated() public {
        uint256 nonce = usdn.nonces(user);

        PermitSigUtils.Permit memory permit = PermitSigUtils.Permit({
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

    /**
     * @custom:scenario Permitting a spender with an invalid signature
     * @custom:given Bob has signed a permit for this contract to spend 100 of Alice's tokens
     * @custom:when This contract calls the `permit` function with the signature of Bob
     * @custom:then The transaction reverts with the `ERC2612InvalidSignature` error
     */
    function test_RevertWhen_invalidSigner() public {
        PermitSigUtils.Permit memory permit = PermitSigUtils.Permit({
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
