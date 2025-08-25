// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Script } from "forge-std/Script.sol";

import { MockChainlinkOnChain } from "../../test/unit/Middlewares/utils/MockChainlinkOnChain.sol";

import { WstEthOracleMiddlewareWithPyth } from "../../src/OracleMiddleware/WstEthOracleMiddlewareWithPyth.sol";
import { MockWstEthOracleMiddlewareWithPyth } from
    "../../src/OracleMiddleware/mock/MockWstEthOracleMiddlewareWithPyth.sol";
import { Usdn } from "../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { PriceInfo } from "../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocol } from "../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

abstract contract UsdnForkBase is Script {
    address immutable CHAINLINK_ETH_PRICE_MOCKED = address(new MockChainlinkOnChain());
    uint256 price = 3000 ether;

    // config related vars
    IERC20Metadata immutable UNDERLYING_ASSET_BASE;
    address immutable PYTH_ADDRESS_BASE;
    address immutable CHAINLINK_ETH_PRICE_BASE;
    bytes32 immutable PYTH_ETH_FEED_ID_BASE;
    uint256 immutable CHAINLINK_PRICE_VALIDITY_BASE;

    constructor(
        IERC20Metadata underlying,
        address pyth,
        address chainlinkPrice,
        bytes32 pythFeedId,
        uint256 chainlinkPriceValidity
    ) {
        UNDERLYING_ASSET_BASE = underlying;
        price = vm.envOr("START_PRICE_USDN", price);
        PYTH_ADDRESS_BASE = pyth;
        CHAINLINK_ETH_PRICE_BASE = chainlinkPrice;
        PYTH_ETH_FEED_ID_BASE = pythFeedId;
        CHAINLINK_PRICE_VALIDITY_BASE = chainlinkPriceValidity;
    }

    function postRun(IUsdnProtocol usdnProtocol_) external {
        setRoles(usdnProtocol_);
        setPeripheralContracts(usdnProtocol_);
        vm.clearMockedCalls();
    }

    function setRoles(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();
        usdnProtocol.grantRole(Constants.ADMIN_SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_OPTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_PROTOCOL_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_SET_USDN_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_EXTERNAL_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_OPTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_PROTOCOL_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.SET_USDN_PARAMS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_CRITICAL_FUNCTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_PROXY_UPGRADE_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_PAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.ADMIN_UNPAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.CRITICAL_FUNCTIONS_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.PROXY_UPGRADE_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.PAUSER_ROLE, msg.sender);
        usdnProtocol.grantRole(Constants.UNPAUSER_ROLE, msg.sender);
        vm.stopBroadcast();
        Usdn usdn = Usdn(address(usdnProtocol.getUsdn()));
        vm.startBroadcast();
        vm.startPrank(address(usdnProtocol));
        usdn.grantRole(usdn.MINTER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(usdnProtocol));
        usdn.grantRole(usdn.MINTER_ROLE(), msg.sender);
        usdn.grantRole(usdn.REBASER_ROLE(), msg.sender);
        vm.stopPrank();
        vm.stopBroadcast();
    }

    // Mock oracle price
    function preRun() external {
        address computedMiddlewareAddress = address(
            new WstEthOracleMiddlewareWithPyth(
                PYTH_ADDRESS_BASE,
                PYTH_ETH_FEED_ID_BASE,
                CHAINLINK_ETH_PRICE_BASE,
                address(UNDERLYING_ASSET_BASE),
                CHAINLINK_PRICE_VALIDITY_BASE
            )
        );
        PriceInfo memory priceInfo = PriceInfo({ price: price, neutralPrice: price, timestamp: block.timestamp });
        vm.mockCall(
            computedMiddlewareAddress,
            abi.encodeWithSelector(WstEthOracleMiddlewareWithPyth.parseAndValidatePrice.selector),
            abi.encode(priceInfo)
        );
    }

    function setPeripheralContracts(IUsdnProtocol usdnProtocol) internal {
        vm.startBroadcast();

        MockWstEthOracleMiddlewareWithPyth wstEthOracleMiddleware_ = new MockWstEthOracleMiddlewareWithPyth(
            PYTH_ADDRESS_BASE,
            PYTH_ETH_FEED_ID_BASE,
            CHAINLINK_ETH_PRICE_MOCKED,
            address(UNDERLYING_ASSET_BASE),
            CHAINLINK_PRICE_VALIDITY_BASE
        );
        wstEthOracleMiddleware_.setVerifySignature(false);
        wstEthOracleMiddleware_.setWstethMockedPrice(price);
        usdnProtocol.setOracleMiddleware(wstEthOracleMiddleware_);

        vm.stopBroadcast();
    }
}
