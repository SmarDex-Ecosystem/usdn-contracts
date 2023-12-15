// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocolStorage } from "src/UsdnProtocol/UsdnProtocolStorage.sol";
import { UsdnProtocolLong } from "src/UsdnProtocol/UsdnProtocolLong.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";

contract UsdnProtocol is UsdnProtocolLong, Ownable, Initializable {
    /**
     * @notice Constructor.
     * @param usdn The USDN ERC20 contract.
     * @param asset The asset ERC20 contract (wstETH).
     * @param oracleMiddleware The oracle middleware contract.
     * @param tickSpacing The positions tick spacing.
     */
    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        Ownable(msg.sender)
        UsdnProtocolStorage(usdn, asset, oracleMiddleware, tickSpacing)
    { }

    function initialize(uint256 depositAmount, uint128 longAmount, bytes calldata currentPriceData)
        external
        initializer
    {
        if (depositAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }
        if (longAmount == 0) {
            revert UsdnProtocolZeroAmount();
        }

        _balanceVault += depositAmount;

        // TODO: perform inclusion of a long position

        PendingAction memory pendingAction = PendingAction({
            action: ProtocolAction.InitiateWithdrawal,
            timestamp: uint40(block.timestamp),
            user: msg.sender,
            tick: 0, // unused
            amountOrIndex: depositAmount
        });

        _retrieveAssetsAndCheckBalance(msg.sender, depositAmount);
        emit InitiatedDeposit(msg.sender, depositAmount);
        _validateDepositWithAction(pendingAction, currentPriceData);
    }
}
