// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { UUPSUpgradeable } from "solady/src/utils/UUPSUpgradeable.sol";

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { UsdnProtocolImplV2 } from "../utils/UsdnProtocolImplV2.sol";

import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IUsdnProtocol } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolFallback } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolFallback.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The proxy functionality of the protocol
 * @custom:background Given an initialized protocol
 */
contract TestUsdnProtocolProxy is UsdnProtocolBaseFixture {
    Types.Storage sV1;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Try to call {initialize} function before {initializeStorage}
     * @custom:given An initialized protocol
     * @custom:when {initialize} is called
     * @custom:then The call should revert since the storage is not initialized
     */
    function test_RevertWhen_InitializeBeforeInitializeStorage() public {
        UsdnProtocolImpl freshProtocol = new UsdnProtocolImpl();
        // Deploy a fresh protocol without calling the initializeStorage function
        address freshProxy = UnsafeUpgrades.deployUUPSProxy(address(freshProtocol), "");
        freshProtocol = UsdnProtocolImpl(freshProxy);

        // The call should revert without message because the storage is not initialized
        vm.expectRevert();
        freshProtocol.initialize(
            DEFAULT_PARAMS.initialDeposit,
            DEFAULT_PARAMS.initialLong,
            DEFAULT_PARAMS.initialPrice / 2,
            abi.encode(DEFAULT_PARAMS.initialPrice)
        );
    }

    /**
     * @custom:scenario Try to upgrade the protocol with a non-admin account
     * @custom:given An initialized protocol
     * @custom:when {upgradeProxy} is called with a new implementation by a non-admin account
     * @custom:then The call should revert
     */
    function test_RevertWhen_upgradeProxyIsCalledWithNonAdmin() public {
        UsdnProtocolImplV2 newImplementation = new UsdnProtocolImplV2();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), protocol.PROXY_UPGRADE_ROLE()
            )
        );
        protocol.upgradeToAndCall(address(newImplementation), bytes(""));
    }

    /**
     * @custom:scenario Try to initialize the protocol twice
     * @custom:given An initialized protocol
     * @custom:when {initializeStorage} is called again
     * @custom:then The call should revert
     */
    function test_RevertWhen_initializeIsCalledSecondTime() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        protocol.initializeStorage(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            _tickSpacing,
            address(feeCollector),
            IUsdnProtocolFallback(address(0))
        );
    }

    /**
     * @custom:scenario Try to initialize the implementation of the protocol
     * @custom:given An initialized protocol
     * @custom:when {initializeStorage} is called on the implementation
     * @custom:then The call should revert with {InvalidInitialization} error
     */
    function test_RevertWhen_initializeIsCalledOnImplementation() public {
        // 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d38_2bbc
        uint256 implementation_slot = uint256(keccak256("eip1967.proxy.implementation")) - 1;
        bytes32 implementation_addr_bytes = vm.load(address(protocol), bytes32(implementation_slot));
        address implementation_addr = address(uint160(uint256(implementation_addr_bytes)));

        assertTrue(implementation_addr != address(0), "The implementation address should not be zero");

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        IUsdnProtocol(implementation_addr).initializeStorage(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            _tickSpacing,
            address(feeCollector),
            IUsdnProtocolFallback(address(0))
        );
    }

    /**
     * @custom:scenario Upgrading the protocol to a new version
     * @custom:given An initialized protocol
     * @custom:when {upgradeProxy} is called with a new implementation
     * @custom:then The storage should be preserved
     * @custom:and The new implementation should be initialized
     * @custom:and The new implementation function should return true
     */
    function test_upgrade() public {
        _storageSnapshot();

        vm.startPrank(ADMIN);
        UsdnProtocolFallback newProtocolFallback = new UsdnProtocolFallback();
        UsdnProtocolImplV2 newImplementation = new UsdnProtocolImplV2();

        vm.expectEmit();
        emit UUPSUpgradeable.Upgraded(address(newImplementation));
        vm.expectEmit();
        emit Initializable.Initialized(2);
        UnsafeUpgrades.upgradeProxy(
            address(protocol),
            address(newImplementation),
            abi.encodeWithSignature("initializeV2(address)", (newProtocolFallback))
        );
        UsdnProtocolImplV2 protocol = UsdnProtocolImplV2(address(protocol));

        _assertIdenticalStorage();

        assertEq(
            UsdnProtocolFallback(address(protocol)).getFallbackAddress(),
            address(newProtocolFallback),
            "The new fallback address should have been saved"
        );
        assertEq(protocol.newVariable(), 1, "initializeV2 should set newVariable to 1");
        assertEq(protocol.retBool(), true, "retBool should return true");
    }

    function _storageSnapshot() internal {
        sV1._tickSpacing = protocol.getTickSpacing();
        sV1._asset = protocol.getAsset();
        sV1._sdex = protocol.getSdex();
        sV1._priceFeedDecimals = protocol.getPriceFeedDecimals();
        sV1._assetDecimals = protocol.getAssetDecimals();
        sV1._usdn = protocol.getUsdn();
        sV1._usdnMinDivisor = protocol.getUsdnMinDivisor();
        sV1._oracleMiddleware = protocol.getOracleMiddleware();
        sV1._liquidationRewardsManager = protocol.getLiquidationRewardsManager();
        sV1._rebalancer = protocol.getRebalancer();
        sV1._minLeverage = protocol.getMinLeverage();
        sV1._maxLeverage = protocol.getMaxLeverage();
        sV1._lowLatencyValidatorDeadline = protocol.getLowLatencyValidatorDeadline();
        sV1._onChainValidatorDeadline = protocol.getOnChainValidatorDeadline();
        sV1._liquidationPenalty = protocol.getLiquidationPenalty();
        sV1._safetyMarginBps = protocol.getSafetyMarginBps();
        sV1._liquidationIteration = protocol.getLiquidationIteration();
        sV1._EMAPeriod = protocol.getEMAPeriod();
        sV1._fundingSF = protocol.getFundingSF();
        sV1._protocolFeeBps = protocol.getProtocolFeeBps();
        sV1._positionFeeBps = protocol.getPositionFeeBps();
        sV1._vaultFeeBps = protocol.getVaultFeeBps();
        sV1._rebalancerBonusBps = protocol.getRebalancerBonusBps();
        sV1._sdexBurnOnDepositRatio = protocol.getSdexBurnOnDepositRatio();
        sV1._securityDepositValue = protocol.getSecurityDepositValue();
        sV1._feeThreshold = protocol.getFeeThreshold();
        sV1._feeCollector = protocol.getFeeCollector();
        sV1._targetUsdnPrice = protocol.getTargetUsdnPrice();
        sV1._usdnRebaseThreshold = protocol.getUsdnRebaseThreshold();
        sV1._minLongPosition = protocol.getMinLongPosition();
        sV1._lastFundingPerDay = protocol.getLastFundingPerDay();
        sV1._lastPrice = protocol.getLastPrice();
        sV1._lastUpdateTimestamp = protocol.getLastUpdateTimestamp();
        sV1._pendingProtocolFee = protocol.getPendingProtocolFee();
        sV1._balanceVault = protocol.getBalanceVault();
        sV1._pendingBalanceVault = protocol.getPendingBalanceVault();
        sV1._EMA = protocol.getEMA();
        sV1._balanceLong = protocol.getBalanceLong();
        sV1._totalExpo = protocol.getTotalExpo();
        sV1._liqMultiplierAccumulator = protocol.getLiqMultiplierAccumulator();
        sV1._highestPopulatedTick = protocol.getHighestPopulatedTick();
        sV1._totalLongPositions = protocol.getTotalLongPositions();
        sV1._depositExpoImbalanceLimitBps = protocol.getDepositExpoImbalanceLimitBps();
        sV1._withdrawalExpoImbalanceLimitBps = protocol.getWithdrawalExpoImbalanceLimitBps();
        sV1._openExpoImbalanceLimitBps = protocol.getOpenExpoImbalanceLimitBps();
        sV1._closeExpoImbalanceLimitBps = protocol.getCloseExpoImbalanceLimitBps();
        sV1._longImbalanceTargetBps = protocol.getLongImbalanceTargetBps();
        sV1._protocolFallbackAddr = protocol.getFallbackAddress();
    }

    function _assertIdenticalStorage() internal view {
        assertEq(sV1._tickSpacing, protocol.getTickSpacing());
        assertEq(address(sV1._asset), address(protocol.getAsset()));
        assertEq(address(sV1._sdex), address(protocol.getSdex()));
        assertEq(sV1._priceFeedDecimals, protocol.getPriceFeedDecimals());
        assertEq(sV1._assetDecimals, protocol.getAssetDecimals());
        assertEq(address(sV1._usdn), address(protocol.getUsdn()));
        assertEq(sV1._usdnMinDivisor, protocol.getUsdnMinDivisor());
        assertEq(address(sV1._oracleMiddleware), address(protocol.getOracleMiddleware()));
        assertEq(address(sV1._liquidationRewardsManager), address(protocol.getLiquidationRewardsManager()));
        assertEq(address(sV1._rebalancer), address(protocol.getRebalancer()));
        assertEq(sV1._minLeverage, protocol.getMinLeverage());
        assertEq(sV1._maxLeverage, protocol.getMaxLeverage());
        assertEq(sV1._lowLatencyValidatorDeadline, protocol.getLowLatencyValidatorDeadline());
        assertEq(sV1._onChainValidatorDeadline, protocol.getOnChainValidatorDeadline());
        assertEq(sV1._liquidationPenalty, protocol.getLiquidationPenalty());
        assertEq(sV1._safetyMarginBps, protocol.getSafetyMarginBps());
        assertEq(sV1._liquidationIteration, protocol.getLiquidationIteration());
        assertEq(sV1._EMAPeriod, protocol.getEMAPeriod());
        assertEq(sV1._fundingSF, protocol.getFundingSF());
        assertEq(sV1._protocolFeeBps, protocol.getProtocolFeeBps());
        assertEq(sV1._positionFeeBps, protocol.getPositionFeeBps());
        assertEq(sV1._vaultFeeBps, protocol.getVaultFeeBps());
        assertEq(sV1._rebalancerBonusBps, protocol.getRebalancerBonusBps());
        assertEq(sV1._sdexBurnOnDepositRatio, protocol.getSdexBurnOnDepositRatio());
        assertEq(sV1._securityDepositValue, protocol.getSecurityDepositValue());
        assertEq(sV1._feeThreshold, protocol.getFeeThreshold());
        assertEq(sV1._feeCollector, protocol.getFeeCollector());
        assertEq(sV1._targetUsdnPrice, protocol.getTargetUsdnPrice());
        assertEq(sV1._usdnRebaseThreshold, protocol.getUsdnRebaseThreshold());
        assertEq(sV1._minLongPosition, protocol.getMinLongPosition());
        assertEq(sV1._lastFundingPerDay, protocol.getLastFundingPerDay());
        assertEq(sV1._lastPrice, protocol.getLastPrice());
        assertEq(sV1._lastUpdateTimestamp, protocol.getLastUpdateTimestamp());
        assertEq(sV1._pendingProtocolFee, protocol.getPendingProtocolFee());
        assertEq(sV1._balanceVault, protocol.getBalanceVault());
        assertEq(sV1._pendingBalanceVault, protocol.getPendingBalanceVault());
        assertEq(sV1._EMA, protocol.getEMA());
        assertEq(sV1._balanceLong, protocol.getBalanceLong());
        assertEq(sV1._totalExpo, protocol.getTotalExpo());
        assertEq(
            keccak256(abi.encode(sV1._liqMultiplierAccumulator)),
            keccak256(abi.encode(protocol.getLiqMultiplierAccumulator()))
        );
        assertEq(sV1._highestPopulatedTick, protocol.getHighestPopulatedTick());
        assertEq(sV1._totalLongPositions, protocol.getTotalLongPositions());
        assertEq(sV1._depositExpoImbalanceLimitBps, protocol.getDepositExpoImbalanceLimitBps());
        assertEq(sV1._withdrawalExpoImbalanceLimitBps, protocol.getWithdrawalExpoImbalanceLimitBps());
        assertEq(sV1._openExpoImbalanceLimitBps, protocol.getOpenExpoImbalanceLimitBps());
        assertEq(sV1._closeExpoImbalanceLimitBps, protocol.getCloseExpoImbalanceLimitBps());
        assertEq(sV1._longImbalanceTargetBps, protocol.getLongImbalanceTargetBps());
    }
}
