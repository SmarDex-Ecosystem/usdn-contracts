// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature Fuzzing of the USDN token functions
 * @custom:background Given MAX_TOKENS, a maximum amount of tokens that can exist
 */
contract TestUsdnFuzzing is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
    }

    /**
     * @custom:scenario Convert an amount of tokens to the corresponding amount of shares, then back to tokens
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are converted to shares and back to tokens
     * @custom:then The result is the same as the original amount of tokens
     * @param divisor The divisor to use
     * @param tokens The amount of tokens to convert
     */
    function testFuzz_convertBetweenTokensAndShares(uint256 divisor, uint256 tokens) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        tokens = bound(tokens, 0, usdn.maxTokens());

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 shares = usdn.convertToShares(tokens);
        uint256 tokensOut = usdn.convertToTokens(shares);

        assertEq(tokens, tokensOut);
    }

    /**
     * @custom:scenario Transfer an amount of tokens to a user and check the balance changes
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are transferred to a user
     * @custom:then The balance of this contract is decreased by the amount of tokens
     * @custom:and The balance of the user is increased by the amount of tokens
     * @custom:and The `Transfer` event is emitted with the correct amount
     * @param divisor The divisor to use
     * @param transferAmount The amount of tokens to transfer
     */
    function testFuzz_balance(uint256 divisor, uint256 transferAmount) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        transferAmount = bound(transferAmount, 0, usdn.maxTokens());

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        usdn.mint(address(this), usdn.maxTokens());
        uint256 balanceBefore = usdn.balanceOf(address(this));

        vm.expectEmit(address(usdn));
        emit Transfer(address(this), USER_1, transferAmount); // expected event
        usdn.transfer(USER_1, transferAmount);

        assertEq(usdn.balanceOf(address(this)), balanceBefore - transferAmount, "contract balance decrease");
        assertEq(usdn.balanceOf(USER_1), transferAmount, "user balance increase");
    }

    /**
     * @custom:scenario Mint a balance, adjust divisor and then transfer an amount of tokens to a user and check the
     * balance changes
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are transferred to a user after changing the divisor
     * @custom:then The balance of this contract is decreased by the amount of tokens
     * @custom:and The balance of the user is increased by the amount of tokens
     * @custom:and The `Transfer` event is emitted with the correct amount
     * @param divisor The divisor to use
     * @param transferAmount The amount of tokens to transfer
     */
    function testFuzz_balanceAfterMultiplier(uint256 divisor, uint256 transferAmount) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        transferAmount = bound(transferAmount, 0, usdn.maxTokens());

        usdn.mint(address(this), usdn.maxTokens());

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 balanceBefore = usdn.balanceOf(address(this));

        vm.expectEmit(address(usdn));
        emit Transfer(address(this), USER_1, transferAmount); // expected event
        usdn.transfer(USER_1, transferAmount);

        assertEq(usdn.balanceOf(address(this)), balanceBefore - transferAmount, "contract balance decrease");
        assertEq(usdn.balanceOf(USER_1), transferAmount, "user balance increase");
    }

    /**
     * @custom:scenario Mint two balances, adjust divisor and then transfer an amount of tokens between the two
     * @custom:given This contract with a balance between 1 and MAX_TOKENS
     * @custom:and A user with a balance between 0 and MAX_TOKENS - balance of this contract
     * @custom:when The tokens are transferred to the user after changing the divisor
     * @custom:then The balance of this contract is decreased by the amount of tokens (with 1 wei tolerance)
     * @custom:and The balance of the user is increased by the amount of tokens (with 1 wei tolerance)
     * @custom:and The sum of the two balances does not change (with 1 wei tolerance)
     * @custom:and The `Transfer` event is emitted with the correct amount
     * @param divisor The divisor to use
     * @param balanceThis The balance of this contract
     * @param balanceUser The balance of the user
     * @param transferAmount The amount of tokens to transfer
     */
    function testFuzz_transferWithTwoBalances(
        uint256 divisor,
        uint256 balanceThis,
        uint256 balanceUser,
        uint256 transferAmount
    ) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        balanceThis = bound(balanceThis, 1, usdn.maxTokens());
        balanceUser = bound(balanceUser, 0, usdn.maxTokens() - balanceThis);
        usdn.mint(address(this), balanceThis);
        if (balanceUser > 0) {
            usdn.mint(USER_1, balanceUser);
        }

        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 balanceBefore = usdn.balanceOf(address(this));
        uint256 balanceUserBefore = usdn.balanceOf(USER_1);
        transferAmount = bound(transferAmount, 0, balanceBefore);

        vm.expectEmit(address(usdn));
        emit Transfer(address(this), USER_1, transferAmount); // expected event
        usdn.transfer(USER_1, transferAmount);

        assertApproxEqAbs(usdn.balanceOf(address(this)), balanceBefore - transferAmount, 1, "contract balance decrease");
        assertApproxEqAbs(usdn.balanceOf(USER_1), balanceUserBefore + transferAmount, 1, "user balance increase");
        assertApproxEqAbs(
            balanceBefore + balanceUserBefore,
            usdn.balanceOf(address(this)) + usdn.balanceOf(USER_1),
            1,
            "sum of balances"
        );
    }

    /**
     * @custom:scenario Check that the total supply is the sum of the balances of all holders
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and 10 holders with random balances
     * @custom:when The total supply is queried
     * @custom:then The result is the sum of the balances of all holders
     * @param divisor The divisor to use
     */
    function testFuzz_totalSupply(uint256 divisor) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 totalHolders = 10;
        uint256[] memory balances = new uint256[](totalHolders);
        uint256 totalBalances;
        for (uint256 i = 0; i < totalHolders; i++) {
            balances[i] = _bound(uint256(keccak256(abi.encodePacked(i + divisor))), 0, usdn.maxTokens() / totalHolders);
            totalBalances += balances[i];
            usdn.mint(address(uint160(i + 1)), balances[i]);
        }
        assertEq(usdn.totalSupply(), totalBalances);
    }

    /**
     * @custom:scenario Mint an amount of tokens, change the divisor and then burn the full balance
     * @custom:given A divisor between MAX_DIVISOR and MIN_DIVISOR
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are burned after changing the divisor
     * @custom:then The balance of this contract is 0
     * @custom:and The total supply is 0
     * @param divisor The divisor to use
     * @param tokens The amount of tokens to mint and burn
     */
    function testFuzz_totalBurn(uint256 divisor, uint256 tokens) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        tokens = bound(tokens, 0, usdn.MAX_DIVISOR());

        usdn.mint(address(this), tokens);
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        usdn.burn(usdn.balanceOf(address(this)));
        assertEq(usdn.balanceOf(address(this)), 0, "contract balance");
        assertEq(usdn.totalSupply(), 0, "total supply");
    }

    /**
     * @custom:scenario transfer part of balance, adjust divisor to MIN_DIVISOR, check that no shares have been created
     * or lost.
     * @custom:given MAX_TOKENS USDN are minted at MAX_DIVISOR
     * @custom:and The divisor is adjusted to a value between MAX_DIVISOR and MIN_DIVISOR before transferring
     * @custom:when A part of the balance is transferred
     * @custom:and The divisor is adjusted to MIN_DIVISOR
     * @custom:then There are no tokens created or lost
     * @custom:and There are no shares created or lost
     * @param divisor the divisor before the transfer
     * @param tokens the amount of tokens to transfer
     */
    function testFuzz_partialTransfer(uint256 divisor, uint256 tokens) public {
        divisor = bound(divisor, usdn.MIN_DIVISOR(), usdn.MAX_DIVISOR());
        tokens = bound(tokens, 0, usdn.maxTokens());

        usdn.mint(address(this), usdn.maxTokens());
        uint256 sharesBefore = usdn.sharesOf(address(this));
        if (divisor < usdn.MAX_DIVISOR()) {
            usdn.rebase(divisor);
        }

        uint256 balanceBefore = usdn.balanceOf(address(this));
        usdn.transfer(USER_1, tokens);
        assertEq(usdn.balanceOf(address(this)), balanceBefore - tokens, "contract balance decrease");
        assertEq(usdn.balanceOf(USER_1), tokens, "user balance increase");
        assertEq(usdn.sharesOf(address(this)) + usdn.sharesOf(USER_1), sharesBefore, "sum of the share balances");

        if (divisor != usdn.MIN_DIVISOR()) {
            usdn.rebase(usdn.MIN_DIVISOR());
        }

        assertEq(usdn.balanceOf(address(this)) + usdn.balanceOf(USER_1), usdn.totalSupply(), "total supply");
        assertEq(usdn.sharesOf(address(this)) + usdn.sharesOf(USER_1), sharesBefore, "sum of the share balances after");
    }
}
