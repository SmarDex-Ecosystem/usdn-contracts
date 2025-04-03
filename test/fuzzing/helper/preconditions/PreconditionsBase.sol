// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { StdStyle, console } from "forge-std/Test.sol";

import { BeforeAfter } from "../BeforeAfter.sol";

import { UsdnProtocolUtilsLibrary } from "../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/* solhint-disable meta-transactions/no-msg-sender */
abstract contract PreconditionsBase is BeforeAfter {
    modifier setCurrentActor() {
        if (block.timestamp < 1_524_785_992) {
            vm.warp(block.timestamp + 1_524_785_992); //medusa workaround
        }
        if (_setActor) {
            if (SINGLE_ACTOR_MODE) {
                currentActor = USER1;
            } else {
                currentActor = USERS[uint256(keccak256(abi.encodePacked(iteration * PRIME + SEED))) % (USERS.length)];

                iteration += 1;
            }
        }

        // vm.startPrank(currentActor); //NOTE: this doesnt work in a current echidna build, leaving for future using
        // with pending update

        _;
        // vm.stopPrank();
    }

    modifier enforceOneActionPerCall() {
        if (checkOtherUsersPendingActions(0, currentActor)) {
            return;
        }
        _;
    }

    function getRandomUser(uint8 input) internal view returns (address) {
        uint256 randomIndex = input % USERS.length;
        return USERS[randomIndex];
    }

    // NOTE: from SmarDex team fuzzing suite
    //@custom:fuzzing price passed with 18 decimals
    function getPreviousActionsData(address user, uint256 currentPrice)
        internal
        view
        returns (
            Types.PreviousActionsData memory previousActionsData_,
            uint256 securityDeposit_,
            Types.PendingAction memory lastAction_,
            uint256 actionsLength_
        )
    {
        (Types.PendingAction[] memory actions, uint128[] memory rawIndices) =
            usdnProtocol.getActionablePendingActions(user, 0, 100);
        if (rawIndices.length == 0) {
            return (previousActionsData_, securityDeposit_, lastAction_, 0);
        }
        bytes[] memory priceData = new bytes[](rawIndices.length);
        for (uint256 i = 0; i < rawIndices.length; i++) {
            priceData[i] = createPythData();
            securityDeposit_ += actions[i].securityDepositValue;
        }
        lastAction_ = actions[actions.length - 1];
        actionsLength_ = actions.length;
        previousActionsData_ = Types.PreviousActionsData({ priceData: priceData, rawIndices: rawIndices });
    }
    /**
     * @dev Returns the amount of USDN shares and WstETH that will be transferred in the next action
     * @param action The pending action
     * @param price The current price
     * @return usdn_ The amount of USDN shares
     * @return wsteth_ The amount of WstETH
     * @custom:fuzzing NOTE: from SmarDex team fuzzing suite
     * @custom:fuzzing price passed with 18 decimals
     */

    function getTokenFromPendingAction(Types.PendingAction memory action, uint256 price)
        internal
        view
        returns (int256 usdn_, uint256 wsteth_)
    {
        if (action.action == Types.ProtocolAction.ValidateDeposit) {
            Types.DepositPendingAction memory depositAction = usdnProtocol.i_toDepositPendingAction(action);
            (uint256 usdnSharesExpected,) =
                usdnProtocol.previewDeposit(depositAction.amount, depositAction.assetPrice, uint128(block.timestamp));
            logValidateDeposit(depositAction, usdnSharesExpected);
            return (int256(usdnSharesExpected), 0);
        } else if (action.action == Types.ProtocolAction.ValidateWithdrawal) {
            Types.WithdrawalPendingAction memory withdrawalAction = usdnProtocol.i_toWithdrawalPendingAction(action);
            uint256 amount =
                usdnProtocol.i_mergeWithdrawalAmountParts(withdrawalAction.sharesLSB, withdrawalAction.sharesMSB);

            uint128 priceWithdrawal = uint128((createProtocolPrice() * wstETH.stEthPerToken()) / 1e18);

            int256 vaultAssetAvailable = UsdnProtocolUtilsLibrary._vaultAssetAvailable(
                withdrawalAction.totalExpo,
                withdrawalAction.balanceVault,
                withdrawalAction.balanceLong,
                priceWithdrawal,
                withdrawalAction.assetPrice
            );

            if (vaultAssetAvailable < 0) {
                vaultAssetAvailable = 0; // TODO consider assert(false) in this case
            }

            uint256 assetToTransfer = UsdnProtocolUtilsLibrary._calcAmountToWithdraw(
                amount, uint256(vaultAssetAvailable), usdn.totalShares(), usdnProtocol.getVaultFeeBps()
            );
            logValidateWithdrawal(withdrawalAction, amount, assetToTransfer, price);
            return (-int256(amount), assetToTransfer);
        } else if (action.action == Types.ProtocolAction.ValidateOpenPosition) {
            logValidateOpenPosition(usdn_, wsteth_);
            return (usdn_, wsteth_);
        } else if (action.action == Types.ProtocolAction.ValidateClosePosition) {
            Types.LongPendingAction memory longAction = usdnProtocol.i_toLongPendingAction(action);
            logValidateClosePosition(longAction);
            return (0, longAction.closeAmount);
        } else {
            logDefaultCase(usdn_, wsteth_);
            return (usdn_, wsteth_);
        }
    }

    function totalValue() internal view returns (uint256) {
        uint256 securityDepositValue = usdnProtocol.getSecurityDepositValue();
        /*NOTE: simplifying since we are using mock,
         *1 wei * updateData.length,
         *our data length is always 1, see createPythData()
         */
        return securityDepositValue + pythPrice;
    }

    function waitDelay() internal {
        vm.warp(block.timestamp + wstEthOracleMiddleware.getValidationDelay() + 1);
    }

    function waitForValidationDeadline() internal {
        vm.warp(block.timestamp + usdnProtocol.getLowLatencyValidatorDeadline() + 1);
    }

    function getLiquidationPrice(uint128 startPrice, uint256 leverage)
        internal
        pure
        returns (uint128 liquidationPrice)
    {
        require(leverage > 1e21, "Invalid leverage: must be greater than 1e21");
        uint256 numerator = uint256(startPrice) * (leverage - 1e21);
        uint256 liquidationPriceUint256 = numerator / leverage;
        require(liquidationPriceUint256 <= uint256(startPrice), "Invalid liquidation price: exceeds start price");
        liquidationPrice = uint128(liquidationPriceUint256);
    }

    function logInitiateOpenPositionParams(
        InitiateOpenPositionParams memory params,
        uint256 currentPrice,
        uint256 leverage
    ) internal view {
        console.log(StdStyle.green("-----------------------------------------------------------"));

        console.log(StdStyle.green("Amount ........................ %s"), params.amount);
        console.log(StdStyle.green("Min Leverage ............. %s"), usdnProtocol.getMinLeverage());
        console.log(StdStyle.green("User Max Leverage ............. %s"), usdnProtocol.getMaxLeverage());
        console.log(StdStyle.green("Current Price ................. %s"), currentPrice);
        console.log(StdStyle.green("Leverage ...................... %s"), leverage);
        console.log(StdStyle.green("Desired Liquidation Price ..... %s"), params.desiredLiqPrice);
        console.log(StdStyle.green("User Max Price ................ %s"), params.userMaxPrice);
        console.log(StdStyle.green("To ............................ %s"), params.to);
        console.log(StdStyle.green("Validator ..................... %s"), params.validator);
        console.log(StdStyle.green("Transaction Value ............. %s"), params.txValue);

        console.log(StdStyle.green("WSTETH Pending Actions ........ %s"), params.wstethPendingActions);

        // Summary logs
        console.log(StdStyle.green("Current Price ............... %s"), currentPrice);
        console.log(StdStyle.green("Desired Liquidation Price ... %s"), params.desiredLiqPrice);
        console.log(StdStyle.green("Leverage .................... x%s"), leverage / 1e18);

        console.log(StdStyle.green("-----------------------------------------------------------"));
    }

    function logValidateDeposit(Types.DepositPendingAction memory depositAction, uint256 usdnSharesExpected)
        internal
        pure
    {
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log(StdStyle.green("  Deposit Amount ................ %s"), depositAction.amount);
        console.log(StdStyle.green("  Asset Price ................... %s"), depositAction.assetPrice);
        console.log(StdStyle.green("  USDN Shares Expected .......... %s"), usdnSharesExpected);
        console.log(StdStyle.green("-----------------------------------------------------------"));
    }

    function logValidateWithdrawal(
        Types.WithdrawalPendingAction memory withdrawalAction,
        uint256 amount,
        uint256 assetToTransfer,
        uint256 price
    ) internal pure {
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log(StdStyle.green("  Shares LSB .................... %s"), withdrawalAction.sharesLSB);
        console.log(StdStyle.green("  Shares MSB .................... %s"), withdrawalAction.sharesMSB);
        console.log(StdStyle.green("  Merged Amount ................. %s"), amount);
        console.log(StdStyle.green("  Asset to Transfer ............. %s"), assetToTransfer);
        console.log(StdStyle.green("  Current Price ................. %s"), price);
        console.log(StdStyle.green("-----------------------------------------------------------"));
    }

    function logValidateOpenPosition(int256 usdn, uint256 wsteth) internal pure {
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log(StdStyle.green("  USDN .......................... %s"), usdn);
        console.log(StdStyle.green("  WstETH ........................ %s"), wsteth);
        console.log(StdStyle.green("-----------------------------------------------------------"));
    }

    function logValidateClosePosition(Types.LongPendingAction memory longAction) internal pure {
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log(StdStyle.green("  Close Amount .................. %s"), longAction.closeAmount);
        console.log(StdStyle.green("-----------------------------------------------------------"));
    }

    function logDefaultCase(int256 usdn, uint256 wsteth) internal pure {
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log(StdStyle.green("  USDN .......................... %s"), usdn);
        console.log(StdStyle.green("  WstETH ........................ %s"), wsteth);
        console.log(StdStyle.green("-----------------------------------------------------------"));
    }
    //only for timestamp based
    // function setActor(address targetUser) internal {
    // if (block.timestamp < 1524785992) {
    //     vm.warp(1524785992);
    // }
    // uint targetIndex;
    // bool found = false;
    // for (uint i = 0; i < USERS.length; i++) {
    //     if (USERS[i] == targetUser) {
    //         targetIndex = i;
    //         found = true;
    //         break;
    //     }
    // }
    // require(found, "Target user not found in USERS array");
    // uint currentMod = block.timestamp % USERS.length;
    // uint warpAmount;
    // if (currentMod <= targetIndex) {
    //     warpAmount = targetIndex - currentMod;
    // } else {
    //     warpAmount = USERS.length - (currentMod - targetIndex);
    // }
    // // Warp to the calculated timestamp
    // vm.warp(block.timestamp + warpAmount);
    // }

    function setActor(address targetUser) internal {
        require(USERS.length > 0, "Users array is empty");

        // Find target user index
        uint256 targetIndex;
        bool found = false;
        for (uint256 i = 0; i < USERS.length; i++) {
            if (USERS[i] == targetUser) {
                targetIndex = i;
                found = true;
                break;
            }
        }

        require(found, "Target user not found in USERS array");

        uint256 maxIterations = 100_000; //  prevent infinite loops
        uint256 currentIteration = iteration;
        bool iterationFound = false;

        for (uint256 i = 0; i < maxIterations; i++) {
            uint256 hash = uint256(keccak256(abi.encodePacked(currentIteration * PRIME + SEED)));
            uint256 index = hash % USERS.length;

            if (index == targetIndex) {
                iteration = currentIteration;
                iterationFound = true;
                break;
            }

            currentIteration++;
        }

        require(iterationFound, "User index not found by setter");
    }

    function toString(address value) internal pure returns (string memory str) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(value)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
