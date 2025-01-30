// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IWusdn } from "./../interfaces/Usdn/IWusdn.sol";

interface IWusdnBalancerAdaptor {
    /**
     * @notice Gets the WUSDN token.
     * @return wusdn_ The WUSDN token.
     */
    function WUSDN() external view returns (IWusdn wusdn_);

    /**
     * @notice Gets the current redemption rate.
     * @return rate_ Number of USDN tokens per WUSDN token.
     */
    function getRate() external view returns (uint256 rate_);
}

/// @title Balancer.fi Adaptor to Get USDN Redemption Rate
contract WusdnBalancerAdaptor is IWusdnBalancerAdaptor {
    /// @inheritdoc IWusdnBalancerAdaptor
    IWusdn public immutable WUSDN;

    /// @param wusdn The address of the WUSDN token.
    constructor(IWusdn wusdn) {
        WUSDN = wusdn;
    }

    /// @inheritdoc IWusdnBalancerAdaptor
    function getRate() external view returns (uint256 rate_) {
        return WUSDN.redemptionRate();
    }
}
