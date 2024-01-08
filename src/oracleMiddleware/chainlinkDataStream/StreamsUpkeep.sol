// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { StreamsLookupCompatibleInterface } from
    "@chainlink/contracts/src/v0.8/automation/interfaces/StreamsLookupCompatibleInterface.sol";
import { ILogAutomation, Log } from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import { IERC20 } from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/interfaces/IERC20.sol";

import { Common } from "src/oracleMiddleware/chainlinkDataStream/externalLibraries/Common.sol";
import { IRewardManager } from "src/oracleMiddleware/chainlinkDataStream/externalLibraries/IRewardManager.sol";
import { IStreamUpkeep, IVerifierProxy, IFeeManager } from "src/oracleMiddleware/chainlinkDataStream/IStreamUpkeep.sol";

/**
 * @title StreamsUpkeep contract
 * @author Yashiru
 * @notice This contract is used to get the price of an asset from Chainlink Data Streams.
 *         It is used by the USDN protocol to get the price of the USDN underlying asset.
 */
contract StreamsUpkeep is IStreamUpkeep, ILogAutomation, StreamsLookupCompatibleInterface {
    event PriceUpdate(int192 indexed price);

    IVerifierProxy public _verifier;

    // WETH fee address
    string public constant DATASTREAMS_FEEDLABEL = "feedIDs";
    string public constant DATASTREAMS_QUERYLABEL = "timestamp";
    int192 public _last_retrieved_price;
    address public _feeAddress;

    string[] public _feedIds;

    constructor(address verifier, address feeAddress, string[] memory feedIds) {
        _verifier = IVerifierProxy(verifier);
        _feedIds = feedIds;
        _feeAddress = feeAddress;
    }

    /**
     * @notice This function uses revert to convey call information.
     *         See https://eips.ethereum.org/EIPS/eip-3668#rationale for details.
     * @dev This function is intended to be simulated off-chain for gas efficiency.
     * @param log The log emitted by the oracle contract.
     * @return success True if the log is valid and the extraData is correct.
     * @return extraData The data to be passed to checkCallback.
     */
    function checkLog(Log calldata log, bytes memory) external view returns (bool, bytes memory) {
        revert StreamsLookup(DATASTREAMS_FEEDLABEL, _feedIds, DATASTREAMS_QUERYLABEL, log.timestamp, "");
    }

    /**
     * @notice The Data Streams report bytes is passed here.
     *         extraData is context data from feed lookup process.
     *         This method is intended only to be simulated off-chain by Automation.
     *         The data returned will then be passed by Automation into performUpkeep
     * @param values The values returned by the lookup.
     * @param extraData The context data returned by the lookup.
     * @return success True if the callback succeeded.
     * @return performData The data to be passed to performUpkeep.
     */
    function checkCallback(bytes[] calldata values, bytes calldata extraData)
        external
        pure
        returns (bool, bytes memory)
    {
        return (true, abi.encode(values, extraData));
    }

    /**
     * @notice This function is called by CL Automation to perform upkeep on the contract.
     * @param performData The data returned by checkCallback.
     */
    function performUpkeep(bytes calldata performData) external {
        // Decode the performData bytes passed in by CL Automation.
        // This contains the data returned by your implementation in checkCallback().
        (bytes[] memory signedReports, bytes memory extraData) = abi.decode(performData, (bytes[], bytes));

        bytes memory unverifiedReport = signedReports[0];

        (, /* bytes32[3] reportContextData */ bytes memory reportData) =
            abi.decode(unverifiedReport, (bytes32[3], bytes));

        // Report verification fees
        IFeeManager feeManager = IFeeManager(address(_verifier.s_feeManager()));
        IRewardManager rewardManager = IRewardManager(address(feeManager.i_rewardManager()));

        address feeTokenAddress = feeManager.i_linkAddress();
        (Common.Asset memory fee,,) = feeManager.getFeeAndReward(address(this), reportData, feeTokenAddress);

        // Approve rewardManager to spend this contract's balance in fees
        IERC20(feeTokenAddress).approve(address(rewardManager), fee.amount);

        // Verify the report
        bytes memory verifiedReportData = _verifier.verify(unverifiedReport, abi.encode(feeTokenAddress));

        // Decode verified report data into BasicReport struct
        BasicReport memory verifiedReport = abi.decode(verifiedReportData, (BasicReport));

        // Log price from report
        emit PriceUpdate(verifiedReport.price);

        // Store the price from the report
        _last_retrieved_price = verifiedReport.price;
    }

    fallback() external payable { }

    receive() external payable { }
}
