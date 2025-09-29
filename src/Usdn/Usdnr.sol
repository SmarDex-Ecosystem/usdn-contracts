// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnr } from "../interfaces/Usdn/IUsdnr.sol";

/**
 * @title USDnr Token
 * @notice The USDnr token is a wrapper around the USDN token, allowing users to wrap and unwrap USDN at a 1:1 ratio.
 * @dev The generated yield from the underlying USDN tokens is retained within the contract, and withdrawable by the
 * owner.
 */
contract Usdnr is ERC20, IUsdnr, Ownable2Step {
    using FixedPointMathLib for uint256;

    /// @inheritdoc IUsdnr
    uint256 public constant RESERVE = 1 gwei;

    /// @inheritdoc IUsdnr
    IUsdn public immutable USDN;

    /// @notice The address that will receive the yield when {withdrawYield} is called.
    address internal _yieldRecipient;

    /**
     * @param usdn The address of the USDN token contract.
     * @param owner The owner of the USDnr contract.
     * @param yieldRecipient The address that will receive the yield when {withdrawYield} is called.
     */
    constructor(IUsdn usdn, address owner, address yieldRecipient) ERC20("USDN Reserve", "USDnr") Ownable(owner) {
        USDN = usdn;
        _yieldRecipient = yieldRecipient;
    }

    /// @inheritdoc IUsdnr
    function getYieldRecipient() external view returns (address yieldRecipient_) {
        yieldRecipient_ = _yieldRecipient;
    }

    /// @inheritdoc IUsdnr
    function setYieldRecipient(address newYieldRecipient) external onlyOwner {
        if (newYieldRecipient == address(0)) {
            revert USDnrZeroRecipient();
        }
        _yieldRecipient = newYieldRecipient;
        emit USDnrYieldRecipientUpdated(newYieldRecipient);
    }

    /// @inheritdoc IUsdnr
    function wrap(uint256 usdnAmount, address recipient) external {
        if (usdnAmount == 0) {
            revert USDnrZeroAmount();
        }
        if (recipient == address(0)) {
            revert USDnrZeroRecipient();
        }

        USDN.transferFrom(msg.sender, address(this), usdnAmount);

        _mint(recipient, usdnAmount);
    }

    /// @inheritdoc IUsdnr
    function previewWrapShares(uint256 usdnSharesAmount) external view returns (uint256 wrappedAmount_) {
        wrappedAmount_ = usdnSharesAmount / USDN.divisor();
    }

    /// @inheritdoc IUsdnr
    function wrapShares(uint256 usdnSharesAmount, address recipient) external returns (uint256 wrappedAmount_) {
        if (recipient == address(0)) {
            revert USDnrZeroRecipient();
        }

        wrappedAmount_ = usdnSharesAmount / USDN.divisor();
        if (wrappedAmount_ == 0) {
            revert USDnrZeroAmount();
        }

        USDN.transferSharesFrom(msg.sender, address(this), usdnSharesAmount);

        _mint(recipient, wrappedAmount_);
    }

    /// @inheritdoc IUsdnr
    function unwrap(uint256 usdnrAmount, address recipient) external {
        if (usdnrAmount == 0) {
            revert USDnrZeroAmount();
        }
        if (recipient == address(0)) {
            revert USDnrZeroRecipient();
        }

        _burn(msg.sender, usdnrAmount);

        USDN.transfer(recipient, usdnrAmount);
    }

    /// @inheritdoc IUsdnr
    function withdrawYield() external {
        uint256 usdnDivisor = USDN.divisor();
        // we round down the USDN balance to ensure every USDnr is always fully backed by USDN
        uint256 usdnBalanceRoundDown = USDN.sharesOf(address(this)) / usdnDivisor;
        // the yield is the difference between the USDN balance and the total supply of USDnr
        uint256 usdnYield = (usdnBalanceRoundDown - totalSupply()).saturatingSub(RESERVE);

        if (usdnYield == 0) {
            revert USDnrNoYield();
        }
        address recipient = _yieldRecipient;

        emit USDnrYieldWithdrawn(recipient, usdnYield);

        // we use transferShares to save on gas
        USDN.transferShares(recipient, usdnYield * usdnDivisor);
    }
}
