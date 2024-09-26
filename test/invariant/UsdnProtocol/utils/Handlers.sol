// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { ADMIN, USER_1, USER_2, USER_3, USER_4 } from "../../../utils/Constants.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol//libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolFallback } from "../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolCoreLibrary as Core } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { PriceInfo } from "../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";

/**
 * @notice A handler for invariant testing of the USDN protocol
 * @dev This handler does not perform input validation and might result in reverted transactions
 * To perform invariant testing without unexpected reverts, use UsdnProtocolSafeHandler
 */
contract UsdnProtocolHandler is UsdnProtocolImpl, UsdnProtocolFallback, Test {
    WstETH immutable _mockAsset;
    Sdex immutable _mockSdex;

    constructor(WstETH mockAsset, Sdex mockSdex) {
        _mockAsset = mockAsset;
        _mockSdex = mockSdex;
    }

    /* ------------------------ Invariant testing helpers ----------------------- */

    function mine(uint256 rand) external {
        uint256 blocks = rand % 9;
        blocks++;
        emit log_named_uint("mining blocks", blocks);
        skip(12 * blocks);
        vm.roll(block.number + blocks);
    }

    function senders() public pure returns (address[] memory senders_) {
        senders_ = new address[](5);
        senders_[0] = ADMIN;
        senders_[1] = USER_1;
        senders_[2] = USER_2;
        senders_[3] = USER_3;
        senders_[4] = USER_4;
    }

    /* ----------------------- Exposed internal functions ----------------------- */

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        return Long._getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty, assetPrice, longTradingExpo, accumulator, tickSpacing, liquidationPenalty
        );
    }

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        return Utils._calcPositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    /* -------------------------------- Internal -------------------------------- */

    function _getPreviousActionsData() internal view returns (PreviousActionsData memory) {
        (PendingAction[] memory actions, uint128[] memory rawIndices) = Vault.getActionablePendingActions(s, msg.sender);
        return PreviousActionsData({ priceData: new bytes[](actions.length), rawIndices: rawIndices });
    }

    function _minDeposit() internal returns (uint128 minDeposit_) {
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        // minimum USDN shares to mint for burning 1 wei of SDEX
        uint256 minUsdnShares = FixedPointMathLib.divUp(
            Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR * s._usdn.divisor(), s._sdexBurnOnDepositRatio
        );
        // minimum USDN shares to mint 1 wei of USDN tokens
        uint256 halfDivisor = FixedPointMathLib.divUp(s._usdn.divisor(), 2);
        if (halfDivisor > minUsdnShares) {
            minUsdnShares = halfDivisor;
        }
        // minimum deposit that respects both conditions above
        minDeposit_ = uint128(
            FixedPointMathLib.fullMulDiv(
                minUsdnShares,
                vaultBalance * Constants.BPS_DIVISOR,
                s._usdn.totalShares() * (Constants.BPS_DIVISOR - s._vaultFeeBps)
            )
        );
        // if the minimum deposit is less than 1 wei of assets, set it to 1 wei (can't deposit 0)
        if (minDeposit_ == 0) {
            minDeposit_ = 1;
        }
    }

    function _maxDeposit() internal returns (uint128 maxDeposit_) {
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 longBalance = s._balanceLong;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            longBalance = Core.longAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        int256 longTradingExpo = int256(s._totalExpo - longBalance);
        int256 maxDeposit = (s._depositExpoImbalanceLimitBps * longTradingExpo / int256(Constants.BPS_DIVISOR))
            + longTradingExpo - int256(vaultBalance) - int256(s._pendingBalanceVault);
        if (maxDeposit < 0) {
            return 0;
        }
        maxDeposit_ = uint128(_bound(uint256(maxDeposit), 0, type(uint128).max));
    }

    function _maxWithdrawal(uint256 balance) internal returns (uint152 maxWithdrawal_) {
        PriceInfo memory price = s._oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateWithdrawal, ""
        );
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        int256 v = int256(vaultBalance);
        uint256 longBalance = s._balanceLong;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            longBalance = Core.longAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        uint256 longTradingExpo = s._totalExpo - longBalance;
        int256 l = int256(longTradingExpo);
        int256 b = int256(Constants.BPS_DIVISOR);
        int256 t = int256(s._usdn.totalShares());
        int256 p = int256(s._pendingBalanceVault);
        int256 f = int256(uint256(s._vaultFeeBps));
        int256 maxWithdrawal = b * t * (b * (p + v - l) + s._withdrawalExpoImbalanceLimitBps * (p + v))
            / (v * (b - f) * (b - s._withdrawalExpoImbalanceLimitBps));
        if (maxWithdrawal < 0) {
            return 0;
        }
        if (maxWithdrawal > int256(balance)) {
            maxWithdrawal = int256(balance);
        }
        maxWithdrawal_ = uint152(_bound(uint256(maxWithdrawal), 0, type(uint152).max));
    }

    function _isFoundryContract(address addr) internal pure returns (bool) {
        return addr == address(vm) || addr == 0x000000000000000000636F6e736F6c652e6c6f67
            || addr == 0x4e59b44847b379578588920cA78FbF26c0B4956C || addr <= address(0xff);
    }
}

/**
 * @notice A handler for invariant testing of the USDN protocol which does not revert in normal operation
 * @dev Inputs are sanitized to prevent reverts. If a call is not possible, each function is a no-op
 */
contract UsdnProtocolSafeHandler is UsdnProtocolHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet _depositValidators;
    EnumerableSet.AddressSet _withdrawalValidators;
    EnumerableSet.AddressSet _openValidators;
    EnumerableSet.AddressSet _closeValidators;

    constructor(WstETH mockAsset, Sdex mockSdex) UsdnProtocolHandler(mockAsset, mockSdex) { }

    /* ------------------------ Protocol actions helpers ------------------------ */

    function initiateDepositTest(uint128 amount, address to, address payable validator) external {
        if (_maxDeposit() < _minDeposit()) {
            return;
        }
        validator = boundAddress(validator);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.None) {
            return;
        }
        _depositValidators.add(validator);
        amount = uint128(_bound(amount, _minDeposit(), _maxDeposit()));
        _mockAsset.mintAndApprove(msg.sender, amount, address(this), amount);
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 sdexToBurn;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            (, sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(price.timestamp));
        } else {
            (, sdexToBurn) = this.previewDeposit(amount, uint128(price.neutralPrice), uint128(block.timestamp));
        }
        sdexToBurn = sdexToBurn * 15 / 10; // margin
        _mockSdex.mintAndApprove(msg.sender, sdexToBurn, address(this), sdexToBurn);
        console.log("deposit of amount %s to %s and validator %s", amount, to, validator);

        vm.startPrank(msg.sender);
        this.initiateDeposit{ value: s._securityDepositValue }(
            amount, 0, boundAddress(to), validator, "", _getPreviousActionsData()
        );
        vm.stopPrank();
    }

    function validateDepositTest(address payable validator) external {
        validator = _boundValidator(validator, _depositValidators);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.ValidateDeposit) {
            return;
        }
        if (block.timestamp < action.timestamp + s._oracleMiddleware.getValidationDelay()) {
            return;
        }
        _depositValidators.remove(validator);
        uint256 oracleFee = s._oracleMiddleware.validationCost("", ProtocolAction.ValidateDeposit);
        emit log_named_address("validate deposit for", validator);
        vm.startPrank(msg.sender);
        this.validateDeposit{ value: oracleFee }(validator, "", _getPreviousActionsData());
        vm.stopPrank();
    }

    function initiateWithdrawalTest(uint152 shares, address to, address payable validator) external {
        uint152 maxWithdrawal = _maxWithdrawal(s._usdn.sharesOf(msg.sender));
        if (maxWithdrawal < 1) {
            return;
        }
        validator = boundAddress(validator);
        PendingAction memory action = Core.getUserPendingAction(s, validator);
        if (action.action != ProtocolAction.None) {
            return;
        }
        _withdrawalValidators.add(validator);
        shares = uint152(_bound(shares, 1, maxWithdrawal));

        console.log("withdrawal of shares %s to %s and validator %s", shares, to, validator);
        vm.startPrank(msg.sender);
        s._usdn.approve(address(this), shares);
        this.initiateWithdrawal{ value: s._securityDepositValue }(
            shares, 0, boundAddress(to), validator, "", _getPreviousActionsData()
        );
        vm.stopPrank();
    }

    /* ------------------------ Invariant testing helpers ----------------------- */

    function boundAddress(address addr) public view returns (address payable) {
        // there is a 50% chance of returning one of the senders, otherwise the input address unless it's a contract
        bool isContract = addr.code.length > 0 || _isFoundryContract(addr);
        if (isContract || uint256(uint160(addr)) % 2 == 0) {
            address[] memory senders = senders();
            return payable(senders[uint256(uint160(addr) / 2) % senders.length]);
        } else {
            return payable(addr);
        }
    }

    /* --------------------------- Internal functions --------------------------- */

    function _boundValidator(address addr, EnumerableSet.AddressSet storage validators)
        internal
        view
        returns (address payable)
    {
        uint256 length = validators.length();
        if (length == 0) {
            return payable(addr);
        }
        uint256 pick = uint256(uint160(addr)) % length;
        return payable(validators.at(pick));
    }
}

/**
 * @notice A USDN token handler for invariant testing of the USDN protocol
 * @dev This handler is very simple and just serves to test some out-of-band transfers and burns while using the
 * protocol
 */
contract UsdnHandler is Usdn, Test {
    constructor() Usdn(address(0), address(0)) { }

    function burnTest(uint256 value) external {
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        value = bound(value, 1, balanceOf(msg.sender));
        emit log_named_decimal_uint("USDN burn", value, 18);

        _burn(msg.sender, value);
    }

    function transferTest(address to, uint256 value) external {
        if (balanceOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        value = bound(value, 1, balanceOf(msg.sender));
        console.log("USDN transfer from %s to %s with value %s", msg.sender, to, value);

        _transfer(msg.sender, to, value);
    }

    function burnSharesTest(uint256 value) external {
        if (sharesOf(msg.sender) == 0) {
            return;
        }
        value = bound(value, 1, sharesOf(msg.sender));
        emit log_named_uint("USDN burn shares", value);

        _burnShares(msg.sender, value, _convertToTokens(value, Rounding.Closest, _divisor));
    }

    function transferSharesTest(address to, uint256 value) external {
        if (sharesOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        value = bound(value, 1, sharesOf(msg.sender));
        console.log("USDN transfer shares from %s to %s with value %s", msg.sender, to, value);

        _transferShares(msg.sender, to, value, _convertToTokens(value, Rounding.Closest, _divisor));
    }
}
