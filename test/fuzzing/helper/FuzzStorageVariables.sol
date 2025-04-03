// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@perimetersec/fuzzlib/src/FuzzBase.sol";
import { IHevm } from "@perimetersec/fuzzlib/src/IHevm.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { FuzzConstants } from "../util/FuzzConstants.sol";

import { RebalancerHandler } from "../../../test/unit/Rebalancer/utils/Handler.sol";
import { UsdnHandler as Usdn } from "../../../test/unit/USDN/utils/Handler.sol";
import { IUsdnProtocolHandler } from "../mocks/IUsdnProtocolHandler.sol";
import { UsdnProtocolHandler } from "../mocks/UsdnProtocolHandler.sol";

import { MockChainlinkOnChain } from "../../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { Sdex } from "../../../test/utils/Sdex.sol";
import { WstETH } from "../../../test/utils/WstEth.sol";
import { MockPyth } from "../mocks/MockPyth.sol";

import { LiquidationRewardsManager } from "../../../src/LiquidationRewardsManager/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../../../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { MockWstEthOracleMiddleware } from "../../../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { Rebalancer } from "../../../src/Rebalancer/Rebalancer.sol";
import { Wusdn } from "../../../src/Usdn/Wusdn.sol";
import { UsdnProtocolFallback } from "../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

// Rebalancer imports
import { IRebalancerEvents } from "../../../src/interfaces/Rebalancer/IRebalancerEvents.sol";
import { IRebalancerTypes } from "../../../src/interfaces/Rebalancer/IRebalancerTypes.sol";

// Usdn imports
import { IRebaseCallback } from "../../../src/interfaces/Usdn/IRebaseCallback.sol";
import { IUsdn } from "../../../src/interfaces/Usdn/IUsdn.sol";
import { IUsdnErrors } from "../../../src/interfaces/Usdn/IUsdnErrors.sol";
import { IUsdnEvents } from "../../../src/interfaces/Usdn/IUsdnEvents.sol";
import { IWusdn } from "../../../src/interfaces/Usdn/IWusdn.sol";
import { IWusdnErrors } from "../../../src/interfaces/Usdn/IWusdnErrors.sol";
import { IWusdnEvents } from "../../../src/interfaces/Usdn/IWusdnEvents.sol";

// UsdnProtocol imports

import { IStETH } from "../../../src/interfaces/IStETH.sol";
import { IWstETH } from "../../../src/interfaces/IWstETH.sol";
import { IFeeCollectorCallback } from "../../../src/interfaces/UsdnProtocol/IFeeCollectorCallback.sol";
import { IOwnershipCallback } from "../../../src/interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IPaymentCallback } from "../../../src/interfaces/UsdnProtocol/IPaymentCallback.sol";
import { IUsdnProtocolActions } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";
import { IUsdnProtocolCore } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import { IUsdnProtocolErrors } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolFallback } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolImpl } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolImpl.sol";
import { IUsdnProtocolLong } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolLong.sol";
import { IUsdnProtocolTypes } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolVault } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";

// LiquidationRewardsManager imports
import { IBaseLiquidationRewardsManager } from
    "../../../src/interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { ILiquidationRewardsManager } from
    "../../../src/interfaces/LiquidationRewardsManager/ILiquidationRewardsManager.sol";

// OracleMiddleware imports
import { IBaseOracleMiddleware } from "../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IChainlinkOracle } from "../../../src/interfaces/OracleMiddleware/IChainlinkOracle.sol";
import { IOracleMiddleware } from "../../../src/interfaces/OracleMiddleware/IOracleMiddleware.sol";
import { IOracleMiddlewareErrors } from "../../../src/interfaces/OracleMiddleware/IOracleMiddlewareErrors.sol";
import { IOracleMiddlewareEvents } from "../../../src/interfaces/OracleMiddleware/IOracleMiddlewareEvents.sol";
import { IOracleMiddlewareWithRedstone } from
    "../../../src/interfaces/OracleMiddleware/IOracleMiddlewareWithRedstone.sol";
import { IPythOracle } from "../../../src/interfaces/OracleMiddleware/IPythOracle.sol";
import { IRedstoneOracle } from "../../../src/interfaces/OracleMiddleware/IRedstoneOracle.sol";

// Additional Rebalancer imports
import { IBaseRebalancer } from "../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancer } from "../../../src/interfaces/Rebalancer/IRebalancer.sol";
import { IRebalancerErrors } from "../../../src/interfaces/Rebalancer/IRebalancerErrors.sol";

import { PriceInfo } from "../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { DoubleEndedQueue } from "../../../src/libraries/DoubleEndedQueue.sol";
import { SignedMath } from "../../../src/libraries/SignedMath.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";
import { FeeCollector } from "../../../src/utils/FeeCollector.sol";

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

    IUsdnProtocolTypes.PositionId[] internal positionIds;

    UsdnProtocolFallback internal usdnProtocolFallback;
    UsdnProtocolHandler internal usdnProtocolHandler;
    LiquidationRewardsManager internal liquidationRewardsManager;
    MockWstEthOracleMiddleware internal wstEthOracleMiddleware;

    Sdex internal sdex;
    WstETH internal wstETH;
    Usdn internal usdn;
    Wusdn internal wusdn;

    IUsdnProtocolHandler internal usdnProtocol;
    RebalancerHandler internal rebalancer;

    MockPyth internal pyth;
    MockChainlinkOnChain internal chainlink;
    IFeeCollectorCallback internal feeCollector;
}
