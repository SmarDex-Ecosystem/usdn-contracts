// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { MockChainlinkOnChain } from "../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";

import { WstEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { MockWstEthOracleMiddlewareWithPyth } from
    "../../src/OracleMiddleware/mock/MockWstEthOracleMiddlewareWithPyth.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { PriceInfo } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IWusdn } from "../../src/interfaces/Usdn/IWusdn.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

abstract contract ForkCore is Script {
    address CHAINLINK_ETH_PRICE_MOCKED = address(new MockChainlinkOnChain());
    address SENDER_BASE;
    uint256 price = 3000 ether;

    // config related vars
    IERC20Metadata UNDERLYING_ASSET_FORK;
    address PYTH_ADDRESS_FORK;
    address CHAINLINK_ETH_PRICE_FORK;
    bytes32 PYTH_ETH_FEED_ID_FORK;
    uint256 CHAINLINK_PRICE_VALIDITY_FORK;

    /*
     * @notice Constructor to initialize the ForkCore with necessary parameters
     * @param collat The address of the underlying collateral asset
     * @param pyth The address of the Pyth oracle
     * @param chainlinkPrice The address of the Chainlink ETH price feed
     * @param pythFeedId The Pyth feed ID for ETH
     * @param chainlinkPriceValidity The validity duration for Chainlink price data
    */
    constructor(
        address collat,
        address pyth,
        address chainlinkPrice,
        bytes32 pythFeedId,
        uint256 chainlinkPriceValidity
    ) {
        UNDERLYING_ASSET_FORK = IWusdn(vm.envOr("UNDERLYING_ADDRESS_WUSDN", collat));
        price = vm.envOr("START_PRICE_USDN", price);
        PYTH_ADDRESS_FORK = pyth;
        CHAINLINK_ETH_PRICE_FORK = chainlinkPrice;
        PYTH_ETH_FEED_ID_FORK = pythFeedId;
        CHAINLINK_PRICE_VALIDITY_FORK = chainlinkPriceValidity;
        vm.startBroadcast();
        (, SENDER_BASE,) = vm.readCallers();
        vm.stopBroadcast();
    }

    /**
     * @notice Executes post-deployment configuration including role setup and peripheral contracts
     * @param usdnProtocol The USDN protocol contract to configure
     */
    function postRun(IUsdnProtocol usdnProtocol) internal {
        setRoles(usdnProtocol);
        setPeripheralContracts(usdnProtocol);
        vm.clearMockedCalls();
    }

    /**
     * @notice Sets up all necessary roles for the USDN protocol
     * @param usdnProtocol The USDN protocol contract to grant roles to SENDER_BASE
     */
    function setRoles(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, SENDER_BASE);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, SENDER_BASE);
        vm.stopBroadcast();
    }

    /// @notice Sets up mock oracle price through a mock call before deployment.
    function preRun() internal {
        address computedMiddlewareAddress = address(
            new WstEthOracleMiddlewareWithPyth(
                PYTH_ADDRESS_FORK,
                PYTH_ETH_FEED_ID_FORK,
                CHAINLINK_ETH_PRICE_FORK,
                address(UNDERLYING_ASSET_FORK),
                CHAINLINK_PRICE_VALIDITY_FORK
            )
        );
        PriceInfo memory priceInfo = PriceInfo({ price: price, neutralPrice: price, timestamp: block.timestamp });
        vm.mockCall(
            computedMiddlewareAddress,
            abi.encodeWithSelector(WstEthOracleMiddlewareWithPyth.parseAndValidatePrice.selector),
            abi.encode(priceInfo)
        );
    }

    /**
     * @notice Sets up peripheral contracts for the USDN protocol including mock oracle middleware
     * @param usdnProtocol The USDN protocol contract to configure
     */
    function setPeripheralContracts(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();

        MockWstEthOracleMiddlewareWithPyth wstEthOracleMiddleware = new MockWstEthOracleMiddlewareWithPyth(
            PYTH_ADDRESS_FORK,
            PYTH_ETH_FEED_ID_FORK,
            CHAINLINK_ETH_PRICE_MOCKED,
            address(UNDERLYING_ASSET_FORK),
            CHAINLINK_PRICE_VALIDITY_FORK
        );
        wstEthOracleMiddleware.setVerifySignature(false);
        wstEthOracleMiddleware.setWstethMockedPrice(price);
        usdnProtocol.setOracleMiddleware(wstEthOracleMiddleware);

        vm.stopBroadcast();
    }
}
