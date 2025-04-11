// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { FuzzBase } from "@perimetersec/fuzzlib/src/FuzzBase.sol";

import { WstEthOracleMiddleware } from "../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockWstEthOracleMiddleware } from "../../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Wusdn } from "../../../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { IFeeCollectorCallback } from "../../../src/interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { MockChainlinkOnChain } from "../../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { Sdex } from "../../../test/utils/Sdex.sol";
import { WstETH } from "../../../test/utils/WstEth.sol";
import { UsdnHandler } from "../../unit/USDN/utils/Handler.sol";
import { LiquidationRewardsManagerHandler } from "../mocks/LiquidationRewardsManagerHandler.sol";
import { MockPyth } from "../mocks/MockPyth.sol";
import { RebalancerHandler } from "../mocks/RebalancerHandler.sol";
import { UsdnProtocolHandler } from "../mocks/UsdnProtocolHandler.sol";
import { IUsdnProtocolHandler } from "../mocks/interfaces/IUsdnProtocolHandler.sol";
import { FuzzConstants } from "../util/FuzzConstants.sol";

contract FuzzStorageVariables is FuzzConstants, FuzzBase, Test {
    //Foundry
    bool SINGLE_ACTOR_MODE = false;

    //Echidna
    uint256 internal constant PRIME = 2_147_483_647;
    uint256 internal constant SEED = 22;
    uint256 iteration = 1; // first fuzzing iteration
    address currentActor;
    bool _setActor = true;

    //hardcoded Pyth price
    uint256 public pythPrice = 1;

    uint128 initialLongPositionPrice; //18 decimals

    bool lastFundingSwitch;
    bool LPAdded;

    Types.PositionId[] internal positionIds;

    UsdnProtocolFallback internal usdnProtocolFallback;
    UsdnProtocolHandler internal usdnProtocolHandler;
    LiquidationRewardsManagerHandler internal liquidationRewardsManager;
    MockWstEthOracleMiddleware internal wstEthOracleMiddleware;

    Sdex internal sdex;
    WstETH internal wstETH;
    UsdnHandler internal usdn;

    Wusdn internal wusdn;

    IUsdnProtocolHandler internal usdnProtocol;
    RebalancerHandler internal rebalancer;

    MockPyth internal pyth;
    MockChainlinkOnChain internal chainlink;
    IFeeCollectorCallback internal feeCollector;
}
