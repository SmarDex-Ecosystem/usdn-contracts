// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnr } from "../interfaces/Usdn/IUsdnr.sol";

/**
 * @title USDNr Token
 * @notice The USDNr token is a wrapper around the USDN token, allowing users to wrap and unwrap USDN at a 1:1 ratio.
 * @dev The generated yield from the underlying USDN tokens is retained within the contract, and withdrawable by the
 * owner.
 */
contract Usdnr is ERC20, IUsdnr, Ownable2Step {
    /// @inheritdoc IUsdnr
    IUsdn public immutable USDN;

    /**
     * @param usdn The address of the USDN token contract.
     * @param owner The owner of the USDNr contract.
     */
    constructor(IUsdn usdn, address owner) ERC20("USDN Reserve", "USDNr") Ownable(owner) {
        USDN = usdn;
    }

    /// @inheritdoc IUsdnr
    function wrap(uint256 usdnAmount) external {
        if (usdnAmount == 0) {
            revert USDNrZeroAmount();
        }

        USDN.transferFrom(msg.sender, address(this), usdnAmount);

        _mint(msg.sender, usdnAmount);
    }

    /// @inheritdoc IUsdnr
    function unwrap(uint256 usdnrAmount) external {
        if (usdnrAmount == 0) {
            revert USDNrZeroAmount();
        }

        _burn(msg.sender, usdnrAmount);

        USDN.transfer(msg.sender, usdnrAmount);
    }

    /// @inheritdoc IUsdnr
    function withdrawYield(address recipient) external onlyOwner {
        if (recipient == address(0)) {
            revert USDNrZeroRecipient();
        }

        // we divide the USDN shares by the USDN divisor to round down, ensuring the leftover shares covers all USDNr
        // tokens
        uint256 usdnBalanceRoundDown = USDN.sharesOf(address(this)) / USDN.divisor();
        // the yield is the difference between the USDN balance and the total supply of USDNr, ensuring every USDNr is
        // backed by USDN
        uint256 usdnYield = usdnBalanceRoundDown - totalSupply();

        if (usdnYield == 0) {
            revert USDNrNoYield();
        }

        // todo: use transfer shares?
        USDN.transfer(recipient, usdnYield);
    }
}
