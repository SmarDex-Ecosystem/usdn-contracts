// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { TransferCallback } from "../utils/TransferCallback.sol";

import { UsdnProtocolVaultLibrary as Vault } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";

/**
 * @custom:feature Test the _initiateDeposit internal function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user with 10 wstETH in their wallet
 */
contract TestUsdnProtocolActionsInitiateDeposit is TransferCallback, UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10 ether;
    uint128 internal constant POSITION_AMOUNT = 1 ether;
    int256 internal pendingBalanceVaultBefore;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Initiate a deposit by using callback and verify if pendingBalanceVault changes before token
     * transfer
     * @custom:given The user has wstETH
     * @custom:when The user initiates a deposit of `POSITION_AMOUNT` with a contract that has callback to transfer
     * tokens
     * @custom:then The protocol updates the pending balance of the vault before receiving the tokens
     */
    function test_initiateDepositWithCallback() public {
        pendingBalanceVaultBefore = protocol.getPendingBalanceVault();
        protocol.i_initiateDeposit(
            Vault.InitiateDepositParams({
                user: address(this),
                to: address(this),
                validator: payable(address(this)),
                amount: POSITION_AMOUNT,
                sharesOutMin: DISABLE_SHARES_OUT_MIN,
                securityDepositValue: 0.5 ether
            }),
            abi.encode(uint128(2000 ether))
        );
    }

    /**
     * @notice Callback function to be called during initiate functions to verify pending balance of the vault is
     * updated and transfer asset tokens
     * @dev The implementation must ensure that the `msg.sender` is the protocol contract
     * @param token The token to transfer
     * @param amount The amount to transfer
     * @param to The address of the recipient
     */
    function transferCallback(IERC20Metadata token, uint256 amount, address to) external override {
        int256 pendingBalanceVaultAfter = protocol.getPendingBalanceVault();
        assertTrue(pendingBalanceVaultBefore != pendingBalanceVaultAfter, "Pending balance should change");
        token.transfer(to, amount);
    }
}
