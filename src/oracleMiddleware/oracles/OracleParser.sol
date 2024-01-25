// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { IWstETH } from "src/interfaces/IWstETH.sol";

import { PythOracle, ConfidenceInterval, FormattedPythPrice } from "src/oracleMiddleware/oracles/PythOracle.sol";
import { ChainlinkOracle, PriceInfo } from "src/oracleMiddleware/oracles/ChainlinkOracle.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OracleParser contract
 * @notice this contract is used to return the adjusted price for the asset.
 * @dev return price.
 */
contract OracleParser is PythOracle, ChainlinkOracle, Ownable {
    /// @notice wsteth instance
    IWstETH internal immutable _wstEth;

    /// @notice confidence ratio denominator
    uint16 private constant CONF_DENOMINATOR = 10_000;

    /// @notice updatable confidence ratio
    uint16 internal _confRatio = 4000;

    constructor(address pyth, bytes32 priceID, address priceFeed, address wsteth)
        PythOracle(pyth, priceID)
        ChainlinkOracle(priceFeed)
        Ownable(msg.sender)
    {
        _wstEth = IWstETH(wsteth);
    }

    /// @notice Set new confidence ratio ( only owner )
    function setConfRatio(uint16 newConfRatio) external onlyOwner {
        if (newConfRatio > CONF_DENOMINATOR * 2) {
            revert ConfRatioTooHigh();
        }

        _confRatio = newConfRatio;
    }

    /// @notice Conf ratio denominator
    function confDenominator() external pure returns (uint16) {
        return CONF_DENOMINATOR;
    }

    /// @notice Conf ratio
    function confRatio() external view returns (uint16) {
        return _confRatio;
    }

    /// @notice Wsteth contract address
    function wstEth() external view returns (address) {
        return address(_wstEth);
    }

    /// @notice Is it wsteth target
    function isWsteth() public view returns (bool) {
        return address(_wstEth) != address(0);
    }

    /**
     * @notice Get formatted pyth price. Apply conf ratio and eventually
     * apply steth to wsteth ratio.
     */
    function adjustedPythPrice(
        bytes calldata priceUpdateData,
        uint64 targetTimestamp,
        uint256 _decimals,
        ConfidenceInterval conf
    ) internal returns (PriceInfo memory price_) {
        FormattedPythPrice memory pythPrice = getFormattedPythPrice(priceUpdateData, targetTimestamp, _decimals);

        if (pythPrice.price == -1) {
            revert PythValidationFailed();
        }

        price_ = applyConfidenceRatio(pythPrice, conf);

        if (isWsteth()) {
            price_ = toWstEth(price_);
        }
    }

    /**
     * @notice Get formatted chainlink price and adjust eventually
     * steth to wsteth ratio.
     */
    function adjustedChainlinkPrice(uint8 decimals) internal view returns (PriceInfo memory price_) {
        price_ = getFormattedChainlinkPrice(decimals);

        if (isWsteth()) {
            price_ = toWstEth(price_);
        }
    }

    /// @notice Apply confidence ratio and parse.
    function applyConfidenceRatio(FormattedPythPrice memory pythPrice, ConfidenceInterval conf)
        private
        view
        returns (PriceInfo memory price_)
    {
        if (conf == ConfidenceInterval.Down) {
            price_.price = uint256(pythPrice.price) - (pythPrice.conf * _confRatio / CONF_DENOMINATOR);
        } else if (conf == ConfidenceInterval.Up) {
            price_.price = uint256(pythPrice.price) + (pythPrice.conf * _confRatio / CONF_DENOMINATOR);
        } else {
            price_.price = uint256(pythPrice.price);
        }

        price_.timestamp = pythPrice.publishTime;
        price_.neutralPrice = uint256(pythPrice.price);
    }

    /// @notice Apply stEth to wstEth ratio
    function toWstEth(PriceInfo memory stethPrice) private view returns (PriceInfo memory wstethPrice) {
        // stEth ratio for one wstEth
        uint256 stEthPerToken = _wstEth.stEthPerToken();
        // adjusted price
        return PriceInfo({
            price: stethPrice.price * 1 ether / stEthPerToken,
            neutralPrice: stethPrice.neutralPrice * 1 ether / stEthPerToken,
            timestamp: stethPrice.timestamp
        });
    }
}
