// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { WstEthOracleMiddleware } from "../src/OracleMiddleware/WstEthOracleMiddleware.sol";
import { Usdn } from "../src/Usdn/Usdn.sol";
import { IWstETH } from "../src/interfaces/IWstETH.sol";
import { IUsdnProtocol } from "../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../src/libraries/HugeUint.sol";

contract TransferProtocolOwnership is Script {
    Usdn internal _usdn;
    IUsdnProtocol internal _usdnProtocol;
    uint256 internal _longAmount;
    IWstETH _wstETH;
    WstEthOracleMiddleware _wstEthOracleMiddleware;

    /**
     * @notice Transfer protocol ownership to a new owner
     * @dev The script should be run by the current owner, `NEW_OWNER_ADDRESS` and `USDN_PROTOCOL_ADDRESS` should be set
     * in the environment
     * @dev The script will transfer the default admin role to the new owner
     * @dev To run the script in standalone use : `forge script script/03_TransferProtocolOwnership.s.sol -f
     * YOUR_RPC_URL --private-key YOUR_PRIVATE_KEY --broadcast`
     */
    function run() external {
        // grant the minter and rebaser roles to the protocol and then renounce the admin role of the deployer
        _usdn.grantRole(_usdn.MINTER_ROLE(), address(_usdnProtocol));
        _usdn.grantRole(_usdn.REBASER_ROLE(), address(_usdnProtocol));
        _usdn.renounceRole(_usdn.DEFAULT_ADMIN_ROLE(), msg.sender);

        _initializeUsdnProtocol();
    }

    /**
     * @notice Initialize the USDN Protocol by opening a long and depositing the necessary amount
     * @dev The deposit amount is calculated to reach a balanced state with a leverage of ~2x on the long position
     */
    function _initializeUsdnProtocol() internal {
        uint24 liquidationPenalty = _usdnProtocol.getLiquidationPenalty();
        int24 tickSpacing = _usdnProtocol.getTickSpacing();
        uint256 price = _wstEthOracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), Types.ProtocolAction.Initialize, ""
        ).price;

        // we want a leverage of ~2x so we get the current price from the middleware and divide it by two
        uint128 desiredLiqPrice = uint128(price / 2);
        // get the liquidation price with the tick rounding
        uint128 liqPriceWithoutPenalty = _usdnProtocol.getLiqPriceFromDesiredLiqPrice(
            desiredLiqPrice, price, 0, HugeUint.wrap(0), tickSpacing, liquidationPenalty
        );
        // get the total exposure of the wanted long position
        uint256 positionTotalExpo = FixedPointMathLib.fullMulDiv(_longAmount, price, price - liqPriceWithoutPenalty);
        // get the amount to deposit to reach a balanced state
        uint256 depositAmount = positionTotalExpo - _longAmount;

        if (vm.envOr("GET_WSTETH", false)) {
            uint256 ethAmount = (depositAmount + _longAmount + 10_000) * _wstETH.stEthPerToken() / 1 ether;
            (bool result,) = address(_wstETH).call{ value: ethAmount }(hex"");
            require(result, "Failed to mint wstETH");
        }

        _wstETH.approve(address(_usdnProtocol), depositAmount + _longAmount);

        _usdnProtocol.initialize(uint128(depositAmount), uint128(_longAmount), desiredLiqPrice, "");
    }

    function _handleEnvVariables() internal {
        // mandatory env variables : USDN_PROTOCOL_ADDRESS and INIT_LONG_AMOUNT SAFE_ADDRESS
        try vm.envAddress("USDN_PROTOCOL_ADDRESS") {
            _usdnProtocol = IUsdnProtocol(vm.envAddress("USDN_PROTOCOL_ADDRESS"));
        } catch {
            revert("USDN_PROTOCOL_ADDRESS is required");
        }

        try vm.envUint("INIT_LONG_AMOUNT") {
            _longAmount = vm.envUint("INIT_LONG_AMOUNT");
        } catch {
            revert("INIT_LONG_AMOUNT is required");
        }

        _usdn = Usdn(address(_usdnProtocol.getUsdn()));
        _wstETH = IWstETH(address(_usdnProtocol.getAsset()));
        _wstEthOracleMiddleware = WstEthOracleMiddleware(address(_usdnProtocol.getOracleMiddleware()));
    }
}
