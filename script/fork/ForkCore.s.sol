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

    constructor(
        address _collat,
        address _pyth,
        address _chainlinkPrice,
        bytes32 _pythFeedId,
        uint256 _chainlinkPriceValidity
    ) {
        UNDERLYING_ASSET_FORK = IWusdn(vm.envOr("UNDERLYING_ADDRESS_WUSDN", _collat));
        price = vm.envOr("START_PRICE_USDN", price);
        PYTH_ADDRESS_FORK = _pyth;
        CHAINLINK_ETH_PRICE_FORK = _chainlinkPrice;
        PYTH_ETH_FEED_ID_FORK = _pythFeedId;
        CHAINLINK_PRICE_VALIDITY_FORK = _chainlinkPriceValidity;
        vm.startBroadcast();
        (, SENDER_BASE,) = vm.readCallers();
        vm.stopBroadcast();
    }

    /**
     * @notice Executes post-deployment configuration including role setup and peripheral contracts
     * @param _usdnProtocol The USDN protocol contract to configure
     */
    function postRun(IUsdnProtocol _usdnProtocol) internal {
        setRoles(_usdnProtocol);
        setPeripheralContracts(_usdnProtocol);
        vm.clearMockedCalls();
    }

    /**
     * @notice Sets up all necessary roles for the USDN protocol
     * @param _usdnProtocol The USDN protocol contract to grant roles to SENDER_BASE
     */
    function setRoles(IUsdnProtocol _usdnProtocol) internal {
        vm.startBroadcast();
        _usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.PAUSER_ROLE, SENDER_BASE);
        _usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, SENDER_BASE);
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
     * @param _usdnProtocol The USDN protocol contract to configure
     */
    function setPeripheralContracts(IUsdnProtocol _usdnProtocol) internal {
        vm.startBroadcast();

        MockWstEthOracleMiddlewareWithPyth wstEthOracleMiddleware_ = new MockWstEthOracleMiddlewareWithPyth(
            PYTH_ADDRESS_FORK,
            PYTH_ETH_FEED_ID_FORK,
            CHAINLINK_ETH_PRICE_MOCKED,
            address(UNDERLYING_ASSET_FORK),
            CHAINLINK_PRICE_VALIDITY_FORK
        );
        wstEthOracleMiddleware_.setVerifySignature(false);
        wstEthOracleMiddleware_.setWstethMockedPrice(price);
        _usdnProtocol.setOracleMiddleware(wstEthOracleMiddleware_);

        vm.stopBroadcast();
    }
}
