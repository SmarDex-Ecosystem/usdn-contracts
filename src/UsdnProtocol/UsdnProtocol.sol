// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";

contract UsdnProtocol is UsdnProtocolLong, Ownable, Initializable {
    /**
     * @notice Constructor.
     * @param _usdn The USDN ERC20 contract.
     * @param _asset The asset ERC20 contract (wstETH).
     * @param _oracleMiddleware The oracle middleware contract.
     * @param _tickSpacing The positions tick spacing.
     */
    constructor(IUsdn _usdn, IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing)
        Ownable(msg.sender)
        UsdnProtocolStorage(_usdn, _asset, _oracleMiddleware, _tickSpacing)
    { }
}
