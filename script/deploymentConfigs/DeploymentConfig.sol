// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Sdex } from "../../test/utils/Sdex.sol";

contract DeploymentConfig {
    address immutable CHAINLINK_ETH_PRICE;
    address immutable PYTH_ADDRESS;
    bytes32 immutable PYTH_ETH_FEED_ID;
    IWstETH immutable WSTETH;
    Sdex immutable SDEX;
    uint256 immutable CHAINLINK_GAS_PRICE_VALIDITY;
    uint256 immutable CHAINLINK_PRICE_VALIDITY;
    uint256 immutable INITIAL_LONG_AMOUNT;

    Types.InitStorage internal initStorage;
}
