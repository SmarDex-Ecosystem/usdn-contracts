// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ISmardexPair } from "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexPair.sol";
import { ISmardexSwapCallback } from
    "@smardex-dex-contracts/contracts/ethereum/core/v2/interfaces/ISmardexSwapCallback.sol";
import { SmardexLibrary } from "@smardex-dex-contracts/contracts/ethereum/core/v2/libraries/SmardexLibrary.sol";

import { IFeeCollectorCallback } from "./../interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IAutoSwapperWusdnSdex } from "./../interfaces/Utils/IAutoSwapperWusdnSdex.sol";

import { console } from "forge-std/console.sol";

/**
 * @title SDEX buy-back and burn Autoswapper
 * @notice Automates protocol fee conversion from WUSDN to SDEX via Smardex.
 */
contract AutoSwapperWusdnSdex is
    Ownable2Step,
    IAutoSwapperWusdnSdex,
    IFeeCollectorCallback,
    ERC165,
    ISmardexSwapCallback
{
    using SafeERC20 for IERC20;

    /// @notice Decimal points for basis points (bps).
    uint16 internal constant BPS_DIVISOR = 10_000;

    /// @notice SmarDex pair address for WUSDN/SDEX swaps.
    ISmardexPair internal constant SMARDEX_WUSDN_SDEX_PAIR = ISmardexPair(0x11443f5B134c37903705e64129BEFc20e35a3725);

    /// @notice Wrapped USDN token address.
    IERC20 internal constant WUSDN = IERC20(0x99999999999999Cc837C997B882957daFdCb1Af9);

    /// @notice Allowed slippage for swaps (in basis points).
    uint256 internal _swapSlippage = 100; // 1%

    constructor() Ownable(msg.sender) { }

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256) external {
        try this.swapWusdnToSdex() { }
        catch {
            emit FailedSwap();
        }
    }

    /// @inheritdoc IAutoSwapperWusdnSdex
    function swapWusdnToSdex() external {
        uint256 wusdnAmount = WUSDN.balanceOf(address(this));

        uint256 quoteAmountSdexOut = _quoteAmountOut(wusdnAmount);
        uint256 minSdexAmount = quoteAmountSdexOut * (BPS_DIVISOR - _swapSlippage) / BPS_DIVISOR;
        (int256 amountSdexOut,) = SMARDEX_WUSDN_SDEX_PAIR.swap(address(0xdead), false, int256(wusdnAmount), "");

        if (uint256(-amountSdexOut) < minSdexAmount) {
            revert AutoSwapperSwapFailed();
        }
    }

    function _quoteAmountOut(uint256 amountIn) internal view returns (uint256 amountOut_) {
        (uint256 fictiveReserveSdex, uint256 fictiveReserveWusdn) = SMARDEX_WUSDN_SDEX_PAIR.getFictiveReserves();
        (uint256 reservesSdex, uint256 reservesWusdn) = SMARDEX_WUSDN_SDEX_PAIR.getReserves();
        (uint256 priceAvSdex, uint256 priceAvWusdn, uint256 priceAvTimestamp) =
            SMARDEX_WUSDN_SDEX_PAIR.getPriceAverage();

        (priceAvWusdn, priceAvSdex) = SmardexLibrary.getUpdatedPriceAverage(
            fictiveReserveWusdn, fictiveReserveSdex, priceAvTimestamp, priceAvWusdn, priceAvSdex, block.timestamp
        );

        (fictiveReserveWusdn, fictiveReserveSdex) =
            SmardexLibrary.computeFictiveReserves(reservesWusdn, reservesSdex, fictiveReserveWusdn, fictiveReserveSdex);

        (amountOut_,,,,) = SmardexLibrary.applyKConstRuleOut(
            SmardexLibrary.GetAmountParameters({
                amount: amountIn,
                reserveIn: reservesWusdn,
                reserveOut: reservesSdex,
                fictiveReserveIn: fictiveReserveWusdn,
                fictiveReserveOut: fictiveReserveSdex,
                priceAverageIn: priceAvWusdn,
                priceAverageOut: priceAvSdex,
                feesLP: 9000,
                feesPool: 1000
            })
        );
    }

    /// @inheritdoc ISmardexSwapCallback
    function smardexSwapCallback(int256, int256 amountWusdnIn, bytes calldata) external {
        if (msg.sender != address(SMARDEX_WUSDN_SDEX_PAIR)) {
            revert AutoSwapperInvalidCaller();
        }

        WUSDN.safeTransfer(msg.sender, uint256(amountWusdnIn));
    }

    /// @inheritdoc IAutoSwapperWusdnSdex
    function sweep(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IAutoSwapperWusdnSdex
    function updateSwapSlippage(uint256 newSwapSlippage) external onlyOwner {
        if (newSwapSlippage == 0) {
            revert AutoSwapperInvalidSwapSlippage();
        }
        _swapSlippage = newSwapSlippage;
        emit SwapSlippageUpdated(newSwapSlippage);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IFeeCollectorCallback).interfaceId) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }
}
