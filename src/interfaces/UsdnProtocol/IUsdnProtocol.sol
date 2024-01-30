// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol.
 */
interface IUsdnProtocol is IUsdnProtocolEvents, IUsdnProtocolErrors { }
