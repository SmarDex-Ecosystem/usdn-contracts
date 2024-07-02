// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { UsdnProtocol } from "../../../../src/UsdnProtocol/UsdnProtocol.sol";

/**
 * @custom:feature The constructor of the protocol's storage
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolStorageConstructor is UsdnProtocolBaseFixture {
    function setUp() public {
        _setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the USDN token having a non-zero total supply.
     * @custom:given Deployed external contracts.
     * @custom:when The protocol is instantiated with the USDN token already having some supply created
     * @custom:then The instantiation should revert.
     */
    function test_RevertWhen_constructorUSDNNonZeroTotalSupply() public {
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidUsdn.selector, address(usdn)));
        new UsdnProtocol(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100,
            address(1),
            Roles({ configRole: address(1), adminRole: address(1), actionRole: address(1) })
        );
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the zero address as the fee collector.
     * @custom:given Deployed external contracts.
     * @custom:when The protocol is instantiated with the fee collector being the zero address
     * @custom:then The instantiation should revert.
     */
    function test_RevertWhen_constructorFeeCollectorIsZeroAddress() public {
        usdn = new Usdn(address(0), address(0));

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidFeeCollector.selector));
        new UsdnProtocol(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100,
            address(0),
            Roles({ configRole: address(0), adminRole: address(0), actionRole: address(0) })
        );
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the asset decimal being lower than FUNDING_SF_DECIMALS.
     * @custom:given Deployed external contracts.
     * @custom:when The protocol is instantiated with the fee collector being the zero address
     * @custom:then The instantiation should revert.
     */
    function test_RevertWhen_constructorAssetDecimalsToLow() public {
        uint8 wrongDecimals = protocol.FUNDING_SF_DECIMALS() - 1;
        usdn = new Usdn(address(0), address(0));
        // Lower the asset's decimals
        wstETH.setDecimals(wrongDecimals);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidAssetDecimals.selector, wrongDecimals));
        new UsdnProtocol(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100,
            address(1),
            Roles({ configRole: address(1), adminRole: address(1), actionRole: address(1) })
        );
    }

    /**
     * @custom:scenario Try to instantiate the protocol with the SDEX tokens decimals not equal to TOKENS_DECIMALS.
     * @custom:given Deployed external contracts.
     * @custom:when The protocol is instantiated with tokens that do not have a number of decimals equal to
     * TOKENS_DECIMALS.
     * @custom:then The instantiation should revert.
     */
    function test_RevertWhen_constructorTokenDecimalsMismatch() public {
        usdn = new Usdn(address(0), address(0));
        sdex.setDecimals(protocol.TOKENS_DECIMALS() - 1);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidTokenDecimals.selector));
        new UsdnProtocol(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100,
            address(1),
            Roles({ configRole: address(1), adminRole: address(1), actionRole: address(1) })
        );
    }
}
