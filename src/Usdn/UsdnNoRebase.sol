// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import { IRebaseCallback } from "../interfaces/Usdn/IRebaseCallback.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";

/**
 * @title USDN Token Contract Without Rebases
 * @notice The USDN token supports the USDN Protocol. It is minted when assets are deposited into the USDN Protocol
 * vault and burned when withdrawn. While the original USDN token implement rebases to inflates its supply to stay as
 * close to a certain price as possible, this version removes all of this logic to be used with a protocol that does not
 * have any target price.
 * @dev As rebasing is completely disabled, 1 share always equals to 1 token, and the divisor never changes.
 */
contract UsdnNoRebase is IUsdn, ERC20Permit, ERC20Burnable, Ownable {
    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @inheritdoc IUsdn
     * @dev Only here to match the `IUsdn` interface, this contract uses `Ownable` instead.
     */
    bytes32 public constant MINTER_ROLE = bytes32(0);

    /**
     * @inheritdoc IUsdn
     * @dev Only here to match the `IUsdn` interface, this contract uses `Ownable` instead.
     */
    bytes32 public constant REBASER_ROLE = bytes32(0);

    /**
     * @inheritdoc IUsdn
     * @dev Only here to match the `IUsdn` interface, this contract does not use shares.
     */
    uint256 public constant MAX_DIVISOR = 1;

    /**
     * @inheritdoc IUsdn
     * @dev Only here to match the `IUsdn` interface, this contract does not use shares.
     */
    uint256 public constant MIN_DIVISOR = 1;

    /**
     * @param name The name of the ERC20 token.
     * @param symbol The symbol of the ERC20 token.
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) Ownable(msg.sender) { }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 view functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /* -------------------------------------------------------------------------- */
    /*                            ERC-20 base functions                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function burn(uint256 value) public override(ERC20Burnable, IUsdn) {
        super.burn(value);
    }

    /// @inheritdoc IUsdn
    function burnFrom(address account, uint256 value) public override(ERC20Burnable, IUsdn) {
        super.burnFrom(account, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                           Special token functions                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function sharesOf(address account) public view returns (uint256 shares_) {
        shares_ = balanceOf(account);
    }

    /// @inheritdoc IUsdn
    function totalShares() external view returns (uint256 shares_) {
        shares_ = totalSupply();
    }

    /// @inheritdoc IUsdn
    function convertToTokens(uint256 amountShares) external pure returns (uint256 tokens_) {
        tokens_ = amountShares;
    }

    /// @inheritdoc IUsdn
    function convertToTokensRoundUp(uint256 amountShares) external pure returns (uint256 tokens_) {
        tokens_ = amountShares;
    }

    /// @inheritdoc IUsdn
    function convertToShares(uint256 amountTokens) public pure returns (uint256 shares_) {
        shares_ = amountTokens;
    }

    /// @inheritdoc IUsdn
    function divisor() external pure returns (uint256 divisor_) {
        divisor_ = MIN_DIVISOR;
    }

    /// @inheritdoc IUsdn
    function rebaseHandler() external pure returns (IRebaseCallback) { }

    /// @inheritdoc IUsdn
    function maxTokens() public pure returns (uint256 maxTokens_) {
        maxTokens_ = type(uint256).max;
    }

    /// @inheritdoc IUsdn
    function transferShares(address to, uint256 value) external returns (bool success_) {
        return transfer(to, value);
    }

    /// @inheritdoc IUsdn
    function transferSharesFrom(address from, address to, uint256 value) external returns (bool success_) {
        return transferFrom(from, to, value);
    }

    /// @inheritdoc IUsdn
    function burnShares(uint256 value) external {
        super.burn(value);
    }

    /// @inheritdoc IUsdn
    function burnSharesFrom(address account, uint256 value) public {
        super.burnFrom(account, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Privileged functions                            */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IUsdn
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @inheritdoc IUsdn
    function mintShares(address to, uint256 amount) external onlyOwner returns (uint256 mintedTokens_) {
        _mint(to, amount);
        mintedTokens_ = amount;
    }

    /// @inheritdoc IUsdn
    function rebase(uint256) external pure returns (bool rebased_, uint256 oldDivisor_, bytes memory callbackResult_) {
        rebased_ = false;
        oldDivisor_ = MIN_DIVISOR;
        callbackResult_ = bytes("");
    }

    /// @inheritdoc IUsdn
    function setRebaseHandler(IRebaseCallback) external pure {
        revert UsdnRebaseNotSupported();
    }
}
