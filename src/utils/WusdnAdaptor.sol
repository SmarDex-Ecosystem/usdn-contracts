// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IWusdn } from "./../interfaces/Usdn/IWusdn.sol";

interface IRateProvider {
    /**
     * @notice Gets the current redemption rate.
     * @return redemptionRate_ The current redemption rate.
     */
    function getRate() external view returns (uint256 redemptionRate_);
}

interface IWusdnAdaptor is IRateProvider {
    /**
     * @notice Gets the WUSDN token.
     * @return The WUSDN token.
     */
    function WUSDN() external view returns (IWusdn);
}

/**
 * @title Adaptor to Get USDN Redemption Rate
 * @dev Minimum implementation of the IRateProvider interface.
 */
contract WusdnAdaptor is IWusdnAdaptor {
    /// @inheritdoc IWusdnAdaptor
    IWusdn public immutable WUSDN;

    /// @param wusdn The address of the WUSDN token.
    constructor(IWusdn wusdn) {
        WUSDN = wusdn;
    }

    /**
     * @inheritdoc IRateProvider
     * @dev Number of USDN tokens per WUSDN token.
     */
    function getRate() external view returns (uint256) {
        return WUSDN.redemptionRate();
    }
}
