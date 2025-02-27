// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { LiquidationRewardsManager } from "../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IWstETH } from "../../src/interfaces/IWstETH.sol";
import { IUsdnProtocolTypes as Types } from "../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Sdex } from "../../test/utils/Sdex.sol";
import { DeployUsdnProtocol } from "../utils/DeployUsdnProtocol.sol";

contract DeploymentConfig is DeployUsdnProtocol {
    address immutable CHAINLINK_ETH_PRICE;
    address immutable PYTH_ADDRESS;
    bytes32 immutable PYTH_ETH_FEED_ID;
    IWstETH immutable WSTETH;
    uint256 immutable CHAINLINK_GAS_PRICE_VALIDITY;
    uint256 immutable CHAINLINK_PRICE_VALIDITY;
    uint256 immutable INITIAL_LONG_AMOUNT;

    Types.InitStorage internal initStorage;
}
