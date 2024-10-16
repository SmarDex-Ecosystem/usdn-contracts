// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { IBaseLiquidationRewardsManager } from
    "../../../../src/interfaces/LiquidationRewardsManager/IBaseLiquidationRewardsManager.sol";
import { IBaseOracleMiddleware } from "../../../../src/interfaces/OracleMiddleware/IBaseOracleMiddleware.sol";
import { IUsdn } from "../../../../src/interfaces/Usdn/IUsdn.sol";

/**
 * @custom:feature The constructor of the protocol's storage
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolStorageConstructor is UsdnProtocolBaseFixture {
    UsdnProtocolImpl implementation;
    UsdnProtocolFallback protocolFallback;

    Managers managers = Managers({
        setExternalManager: address(0),
        criticalFunctionsManager: address(0),
        setProtocolParamsManager: address(0),
        setUsdnParamsManager: address(0),
        setOptionsManager: address(0),
        proxyUpgradeManager: address(0),
        pauserManager: address(0),
        unpauserManager: address(0)
    });

    function setUp() public {
        _setUp(DEFAULT_PARAMS);
        implementation = new UsdnProtocolImpl();
        protocolFallback = new UsdnProtocolFallback();
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the USDN token having a non-zero total supply
     * @custom:given Deployed external contracts
     * @custom:when The protocol is instantiated with the USDN token already having some supply created
     * @custom:then The instantiation should revert
     */
    function test_RevertWhen_constructorUSDNNonZeroTotalSupply() public {
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidUsdn.selector, address(usdn)));
        deployProtocol(usdn, sdex, wstETH, oracleMiddleware, liquidationRewardsManager, 100, address(1), managers);
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the zero address as the fee collector
     * @custom:given Deployed external contracts
     * @custom:when The protocol is instantiated with the fee collector being the zero address
     * @custom:then The instantiation should revert
     */
    function test_RevertWhen_constructorFeeCollectorIsZeroAddress() public {
        usdn = new Usdn(address(0), address(0));

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidFeeCollector.selector));
        deployProtocol(usdn, sdex, wstETH, oracleMiddleware, liquidationRewardsManager, 100, address(0), managers);
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the asset decimal being lower than FUNDING_SF_DECIMALS
     * @custom:given Deployed external contracts
     * @custom:when The protocol is instantiated with the fee collector being the zero address
     * @custom:then The instantiation should revert
     */
    function test_RevertWhen_constructorAssetDecimalsToLow() public {
        uint8 wrongDecimals = protocol.FUNDING_SF_DECIMALS() - 1;
        usdn = new Usdn(address(0), address(0));
        // Lower the asset's decimals
        wstETH.setDecimals(wrongDecimals);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidAssetDecimals.selector, wrongDecimals));
        deployProtocol(usdn, sdex, wstETH, oracleMiddleware, liquidationRewardsManager, 100, address(1), managers);
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the SDEX tokens decimals not equal to TOKENS_DECIMALS
     * @custom:given Deployed external contracts
     * @custom:when The protocol is instantiated with tokens that do not have a number of decimals equal to
     * TOKENS_DECIMALS
     * @custom:then The instantiation should revert
     */
    function test_RevertWhen_constructorTokenDecimalsMismatch() public {
        usdn = new Usdn(address(0), address(0));
        sdex.setDecimals(protocol.TOKENS_DECIMALS() - 1);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidTokenDecimals.selector));
        deployProtocol(usdn, sdex, wstETH, oracleMiddleware, liquidationRewardsManager, 100, address(1), managers);
    }

    /**
     * @custom:scenario Test the protocol's getters
     * @custom:given A protocol instance that was initialized with default params
     * @custom:when The getters are called
     * @custom:then The expected values should be returned
     */
    function test_getters() public view {
        assertEq(protocol.LIQUIDATION_MULTIPLIER_DECIMALS(), 38);
        assertEq(protocol.MAX_ACTIONABLE_PENDING_ACTIONS(), 20);
        assertEq(address(protocol.getSdex()), address(sdex));
        assertEq(protocol.getUsdnMinDivisor(), usdn.MIN_DIVISOR());
        assertEq(protocol.getMiddlewareValidationDelay(), oracleMiddleware.getValidationDelay());
        assertEq(protocol.getLastPrice(), DEFAULT_PARAMS.initialPrice);
    }

    function deployProtocol(
        IUsdn usdn,
        IERC20Metadata sdex,
        IERC20Metadata asset,
        IBaseOracleMiddleware oracleMiddleware,
        IBaseLiquidationRewardsManager liquidationRewardsManager,
        int24 tickSpacing,
        address feeCollector,
        Managers memory manager
    ) public {
        UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeCall(
                UsdnProtocolImpl.initializeStorage,
                (
                    usdn,
                    sdex,
                    asset,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    tickSpacing,
                    feeCollector,
                    manager,
                    protocolFallback,
                    params.eip712Version
                )
            )
        );
    }
}
