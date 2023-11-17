// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { BaseFixture } from "test/utils/Fixtures.sol";
import { OracleMiddleware } from "./OracleMiddleware.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { UsdnVault } from "src/UsdnVault/UsdnVault.sol";
import { ERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "test/utils/Constants.sol";

contract USDN is ERC20 {
    constructor() ERC20("Ultimate Synthetic Delta Neutral", "USDN") { }
}

/**
 * @title UsdnVaultFixture
 * @dev Utils for testing UsdnVault
 */
contract UsdnVaultFixture is BaseFixture {
    IUsdn usdn;
    UsdnVault usdnVault;
    OracleMiddleware oracleMiddleware;

    function setUp() public virtual {
        // TODO: replace ERC20/USDN/IUsdn by Usdn
        ERC20 _usdn = new USDN();
        usdn = IUsdn(address(_usdn));

        oracleMiddleware = new OracleMiddleware();

        usdnVault = new UsdnVault(usdn, IERC20Metadata(WSTETH), oracleMiddleware, 10);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public override { }
}
