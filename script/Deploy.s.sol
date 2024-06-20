// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";

import { Sdex } from "../test/utils/Sdex.sol";
import { WstETH } from "../test/utils/WstEth.sol";

import { ProtocolAction } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { MockLiquidationRewardsManager } from "../src/OracleMiddleware/mock/MockLiquidationRewardsManager.sol";
import { MockWstEthOracleMiddleware } from "../src/OracleMiddleware/mock/MockWstEthOracleMiddleware.sol";
import { LiquidationRewardsManager } from "../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { UsdnProtocol } from "../src/UsdnProtocol/UsdnProtocol.sol";
import { Rebalancer } from "../src/Rebalancer/Rebalancer.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";

contract Deploy is Script {
    /**
     * @notice Deploy the USDN ecosystem
     * @return WstETH_ The WstETH token
     * @return Sdex_ The SDEX token
     * @return WstEthOracleMiddleware_ The WstETH oracle middleware
     * @return LiquidationRewardsManager_ The liquidation rewards manager
     * @return Rebalancer_ The rebalancer
     * @return Usdn_ The USDN token
     * @return UsdnProtocol_ The USDN protocol
     */
    function run()
        external
        returns (
            WstETH WstETH_,
            Sdex Sdex_,
            WstEthOracleMiddleware WstEthOracleMiddleware_,
            LiquidationRewardsManager LiquidationRewardsManager_,
            Rebalancer Rebalancer_,
            Usdn Usdn_,
            UsdnProtocol UsdnProtocol_
        )
    {
        bool isProdEnv = block.chainid != vm.envOr("FORK_CHAIN_ID", uint256(31_337));

        vm.startBroadcast(vm.envAddress("DEPLOYER_ADDRESS"));

        uint256 depositAmount = vm.envOr("INIT_DEPOSIT_AMOUNT", uint256(0));
        uint256 longAmount = vm.envOr("INIT_LONG_AMOUNT", uint256(0));

        // deploy contracts
        WstETH_ = _deployWstETH(depositAmount, longAmount);
        WstEthOracleMiddleware_ = _deployWstEthOracleMiddleware(isProdEnv, address(WstETH_));
        LiquidationRewardsManager_ = _deployLiquidationRewardsManager(isProdEnv, address(WstETH_));
        Usdn_ = _deployUsdn();
        Sdex_ = _deploySdex();

        // deploy the protocol with tick spacing 100 = 1%
        UsdnProtocol_ = new UsdnProtocol(
            Usdn_,
            Sdex_,
            WstETH_,
            WstEthOracleMiddleware_,
            LiquidationRewardsManager_,
            100,
            vm.envAddress("FEE_COLLECTOR")
        );

        // deploy the rebalancer
        Rebalancer_ = _deployRebalancer(UsdnProtocol_);

        // set the rebalancer on the USDN protocol
        UsdnProtocol_.setRebalancer(Rebalancer_);

        // grant USDN minter and rebaser roles to protocol and approve wstETH spending
        Usdn_.grantRole(Usdn_.MINTER_ROLE(), address(UsdnProtocol_));
        Usdn_.grantRole(Usdn_.REBASER_ROLE(), address(UsdnProtocol_));
        WstETH_.approve(address(UsdnProtocol_), depositAmount + longAmount);

        if (depositAmount > 0 && longAmount > 0) {
            _initializeUsdnProtocol(isProdEnv, UsdnProtocol_, WstEthOracleMiddleware_, depositAmount, longAmount);
        }

        vm.stopBroadcast();
    }

    /**
     * @notice Deploy the WstETH oracle middleware if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param isProdEnv Env check
     * @param wstETHAddress The address of the WstETH token
     * @return wstEthOracleMiddleware_ The deployed contract
     */
    function _deployWstEthOracleMiddleware(bool isProdEnv, address wstETHAddress)
        internal
        returns (WstEthOracleMiddleware wstEthOracleMiddleware_)
    {
        address middlewareAddress = vm.envOr("MIDDLEWARE_ADDRESS", address(0));
        if (middlewareAddress != address(0)) {
            if (isProdEnv) {
                wstEthOracleMiddleware_ = WstEthOracleMiddleware(middlewareAddress);
            } else {
                wstEthOracleMiddleware_ = MockWstEthOracleMiddleware(middlewareAddress);
            }
        } else {
            address pythAddress = vm.envAddress("PYTH_ADDRESS");
            bytes32 pythFeedId = vm.envBytes32("PYTH_ETH_FEED_ID");
            bytes32 redstoneFeedId = vm.envBytes32("REDSTONE_ETH_FEED_ID");
            address chainlinkPriceAddress = vm.envAddress("CHAINLINK_ETH_PRICE_ADDRESS");
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_ETH_PRICE_VALIDITY", uint256(1 hours + 2 minutes));

            if (isProdEnv) {
                wstEthOracleMiddleware_ = new WstEthOracleMiddleware(
                    pythAddress,
                    pythFeedId,
                    redstoneFeedId,
                    chainlinkPriceAddress,
                    wstETHAddress,
                    chainlinkPriceValidity
                );
            } else {
                wstEthOracleMiddleware_ = new MockWstEthOracleMiddleware(
                    pythAddress,
                    pythFeedId,
                    redstoneFeedId,
                    chainlinkPriceAddress,
                    wstETHAddress,
                    chainlinkPriceValidity
                );
            }
        }
    }

    /**
     * @notice Deploy the liquidation rewards manager if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param isProdEnv Env check
     * @param wstETHAddress The address of the WstETH token
     * @return liquidationRewardsManager_ The deployed contract
     */
    function _deployLiquidationRewardsManager(bool isProdEnv, address wstETHAddress)
        internal
        returns (LiquidationRewardsManager liquidationRewardsManager_)
    {
        address liquidationRewardsManagerAddress = vm.envOr("LIQUIDATION_REWARDS_MANAGER_ADDRESS", address(0));
        if (liquidationRewardsManagerAddress != address(0)) {
            if (isProdEnv) {
                liquidationRewardsManager_ = LiquidationRewardsManager(liquidationRewardsManagerAddress);
            } else {
                liquidationRewardsManager_ = MockLiquidationRewardsManager(liquidationRewardsManagerAddress);
            }
        } else {
            address chainlinkGasPriceFeed = vm.envAddress("CHAINLINK_GAS_PRICE_ADDRESS");
            uint256 chainlinkPriceValidity = vm.envOr("CHAINLINK_GAS_PRICE_VALIDITY", uint256(2 hours + 5 minutes));
            if (isProdEnv) {
                liquidationRewardsManager_ =
                    new LiquidationRewardsManager(chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity);
            } else {
                liquidationRewardsManager_ = new MockLiquidationRewardsManager(
                    chainlinkGasPriceFeed, IWstETH(wstETHAddress), chainlinkPriceValidity
                );
            }
        }
    }

    /**
     * @notice Deploy the USDN token
     * @dev Will return the already deployed one if an address is in the env variables
     * @return usdn_ The deployed contract
     */
    function _deployUsdn() internal returns (Usdn usdn_) {
        address usdnAddress = vm.envOr("USDN_ADDRESS", address(0));
        if (usdnAddress != address(0)) {
            usdn_ = Usdn(usdnAddress);
        } else {
            usdn_ = new Usdn(address(0), address(0));
        }
    }

    /**
     * @notice Deploy the SDEX token
     * @dev Will return the already deployed one if an address is in the env variables
     * @return sdex_ The deployed contract
     */
    function _deploySdex() internal returns (Sdex sdex_) {
        address sdexAddress = payable(vm.envOr("SDEX_ADDRESS", address(0)));
        if (sdexAddress != address(0)) {
            sdex_ = Sdex(sdexAddress);
        } else {
            sdex_ = new Sdex();
        }
    }

    /**
     * @notice Deploy the WstETH token
     * @dev Will return the already deployed one if an address is in the env variables
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     * @return wstEth_ The deployed contract
     */
    function _deployWstETH(uint256 depositAmount, uint256 longAmount) internal returns (WstETH wstEth_) {
        address payable wstETHAddress = payable(vm.envOr("WSTETH_ADDRESS", address(0)));
        if (wstETHAddress != address(0)) {
            wstEth_ = WstETH(wstETHAddress);
            if (vm.envOr("GET_WSTETH", false) && depositAmount > 0 && longAmount > 0) {
                uint256 ethAmount = (depositAmount + longAmount + 10_000) * wstEth_.stEthPerToken() / 1 ether;
                (bool result,) = wstETHAddress.call{ value: ethAmount }(hex"");
                require(result, "Failed to mint wstETH");
            }
        } else {
            wstEth_ = new WstETH();
        }
    }

    /**
     * @notice Deploy the Rebalancer contract if necessary
     * @dev Will return the already deployed one if an address is in the env variables
     * @param usdnProtocol The USDN protocol
     * @return rebalancer_ The deployed contract
     */
    function _deployRebalancer(UsdnProtocol usdnProtocol) internal returns (Rebalancer rebalancer_) {
        address rebalancerAddress = vm.envOr("REBALANCER_ADDRESS", address(0));
        if (rebalancerAddress != address(0)) {
            rebalancer_ = Rebalancer(rebalancerAddress);
        } else {
            rebalancer_ = new Rebalancer(usdnProtocol);
        }
    }

    /**
     * @notice Initialize the USDN Protocol
     * @param isProdEnv Env check
     * @param UsdnProtocol_ The USDN protocol
     * @param WstEthOracleMiddleware_ The WstETH oracle middleware
     * @param depositAmount The amount to deposit during the protocol initialization
     * @param longAmount The size of the long to open during the protocol initialization
     */
    function _initializeUsdnProtocol(
        bool isProdEnv,
        UsdnProtocol UsdnProtocol_,
        WstEthOracleMiddleware WstEthOracleMiddleware_,
        uint256 depositAmount,
        uint256 longAmount
    ) internal {
        uint256 desiredLiqPrice;
        if (isProdEnv) {
            desiredLiqPrice = vm.envUint("INIT_LONG_LIQPRICE");
        } else {
            // for forks, we want a leverage of ~2x so we get the current
            // price from the middleware and divide it by two
            desiredLiqPrice = WstEthOracleMiddleware_.parseAndValidatePrice(
                "", uint128(block.timestamp), ProtocolAction.Initialize, ""
            ).price / 2;
        }

        UsdnProtocol_.initialize(uint128(depositAmount), uint128(longAmount), uint128(desiredLiqPrice), "");
    }
}
