// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IWusdn } from "./../interfaces/Usdn/IWusdn.sol";

interface IRateProvider {
    /// @notice Returns the current redemption rate of the WUSDN.
    function getRate() external view returns (uint256);
}

/**
 * @title Adaptor to Get USDN Redemption Rate
 * @dev Minimum implementation of the IRateProvider interface.
 */
contract WusdnAdaptor is IRateProvider {
    /// @notice WUSDN contract
    IWusdn immutable WUSDN;

    /// @param wusdn The address of the WUSDN token.
    constructor(IWusdn wusdn) {
        WUSDN = wusdn;
    }

    /// @inheritdoc IRateProvider
    function getRate() external view returns (uint256) {
        return WUSDN.redemptionRate();
    }
}
