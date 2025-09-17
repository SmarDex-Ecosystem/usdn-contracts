// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { IUsdnr } from "../interfaces/Usdn/IUsdnr.sol";

contract Usdnr is ERC20, IUsdnr {
    /// @inheritdoc IUsdnr
    IUsdn public immutable USDN;

    /// @dev Tracks the total amount of USDN wrapped into USDNr.
    uint256 internal totalWrapped;

    /// @param usdn The address of the USDN token contract.
    constructor(IUsdn usdn) ERC20("USDN Reserve", "USDNr") {
        USDN = usdn;
    }

    /// @inheritdoc IUsdnr
    function wrap(uint256 usdnAmount) external {
        USDN.transferFrom(msg.sender, address(this), usdnAmount);
        totalWrapped += usdnAmount;

        _mint(msg.sender, usdnAmount);
    }

    /// @inheritdoc IUsdnr
    function unwrap(uint256 usdnrAmount) external {
        _burn(msg.sender, usdnrAmount);
        totalWrapped -= usdnrAmount;
        USDN.transfer(msg.sender, usdnrAmount);
    }
}
