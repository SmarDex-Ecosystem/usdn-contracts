// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";

interface IVerifierFeeManager {
    function processFee(bytes calldata payload, bytes calldata parameterPayload, address subscriber) external payable;
}

interface IWERC20 {
    function deposit() external payable;
}

contract MockFeeManager is IERC165, IVerifierFeeManager {
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------------- */
    /*                                   STRUCTS                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The structure to hold a fee and reward to verify a report.
     * @param configDigest The digest linked to the fee and reward.
     * @param fee The fee paid to verify the report.
     * @param reward The reward paid upon verification.
     * @param appliedDiscount The discount applied to the reward.
     */
    struct FeeAndReward {
        bytes32 configDigest;
        IFeeManager.Asset fee;
        IFeeManager.Asset reward;
        uint256 appliedDiscount;
    }

    /**
     * @notice The structure to hold a fee payment notice.
     * @param poolId The poolId receiving the payment.
     * @param amount The amount being paid.
     */
    struct FeePayment {
        bytes32 poolId;
        uint192 amount;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   PRIVATE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice The total discount that can be applied to a fee, 1e18 = 100% discount.
    uint256 private constant PERCENTAGE_SCALAR = 1e18;

    /* -------------------------------------------------------------------------- */
    /*                                   PUBLIC                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The list of subscribers and their discounts subscriberDiscounts[subscriber][feedId][token].
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public s_subscriberDiscounts;

    /// @notice The native token address.
    address public constant i_nativeAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice The surcharge fee to be paid if paying in native.
    uint256 public s_nativeSurcharge;

    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The error thrown if the discount or surcharge is invalid.
    error InvalidSurcharge();

    /// @notice The error thrown if the discount is invalid.
    error InvalidDiscount();

    /// @notice The error thrown if the address is invalid.
    error InvalidAddress();

    /// @notice Thrown if msg.value is supplied with a bad quote.
    error InvalidDeposit();

    /// @notice Thrown if a report has expired.
    error ExpiredReport();

    /// @notice Thrown if a report has no quote.
    error InvalidQuote();

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted whenever a subscriber's discount is updated.
     * @param subscriber The address of the subscriber to update discounts for.
     * @param feedId Feed ID for the discount.
     * @param token Token address for the discount.
     * @param discount Discount to apply, in relation to the `PERCENTAGE_SCALAR`.
     */
    event SubscriberDiscountUpdated(
        address indexed subscriber, bytes32 indexed feedId, address indexed token, uint64 discount
    );

    /**
     * @notice Emitted when updating the native surcharge.
     * @param newSurcharge The surcharge amount to apply relative to `PERCENTAGE_SCALAR`.
     */
    event NativeSurchargeUpdated(uint64 newSurcharge);

    /**
     * @notice Emitted when a fee has been processed.
     * @param configDigest The config digest of the fee processed.
     * @param subscriber The address of the subscriber who paid the fee.
     * @param fee The fee paid.
     * @param reward The reward paid.
     * @param appliedDiscount The discount applied to the fee.
     */
    event DiscountApplied(
        bytes32 indexed configDigest,
        address indexed subscriber,
        IFeeManager.Asset fee,
        IFeeManager.Asset reward,
        uint256 appliedDiscount
    );

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == this.processFee.selector || interfaceId == this.processFeeBulk.selector;
    }

    /**
     * @notice Processes the fee and reward for a given payload.
     * @param payload The encoded data containing the report and other necessary information.
     * @param subscriber The address of the subscriber trying to verify.
     */
    function processFee(bytes calldata payload, bytes calldata, address subscriber) external payable {
        (IFeeManager.Asset memory fee, IFeeManager.Asset memory reward, uint256 appliedDiscount) =
            _processFee(payload, subscriber);

        if (fee.amount == 0) {
            _tryReturnChange(subscriber, msg.value);
            return;
        }

        FeeAndReward[] memory feeAndReward = new FeeAndReward[](1);
        feeAndReward[0] = FeeAndReward(bytes32(payload), fee, reward, appliedDiscount);

        _handleFeesAndRewards(subscriber, feeAndReward, 0, 1);
    }

    /**
     * @notice Processes fees and rewards for a batch of given payloads.
     * @param payloads An array of encoded data containing reports and other necessary information.
     * @param parameterPayload The additional parameter payload (not used in the current implementation).
     * @param subscriber The address of the subscriber trying to verify.
     */
    function processFeeBulk(bytes[] calldata payloads, bytes calldata parameterPayload, address subscriber)
        external
        payable
    { }

    /**
     * @notice Calculate the applied fee and reward from a report. If the sender is a subscriber, they will receive a
     * discount.
     * @param subscriber The address of the subscriber trying to verify.
     * @param report The report for which the fee and reward are calculated.
     * @param quoteAddress The address of the quote payment token.
     * @return fee_ The calculated fee data.
     * @return rewards_ The calculated reward data (currently not implemented, returns default value).
     * @return discount_ The current discount applied.
     */
    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        public
        view
        returns (IFeeManager.Asset memory fee_, IFeeManager.Asset memory rewards_, uint256 discount_)
    {
        // Get the feedId from the report
        bytes32 feedId = bytes32(report);

        // Verify the quote payload is a supported token
        if (quoteAddress != i_nativeAddress) {
            revert InvalidQuote();
        }

        // Decode the report depending on the version
        uint256 nativeQuantity;
        uint256 expiresAt;
        (,,, nativeQuantity,, expiresAt) = abi.decode(report, (bytes32, uint32, uint32, uint192, uint192, uint32));

        // Read the timestamp bytes from the report data and verify it has not expired
        if (expiresAt < block.timestamp) {
            revert ExpiredReport();
        }

        // Get the discount being applied
        discount_ = s_subscriberDiscounts[subscriber][feedId][quoteAddress];

        uint256 surchargedFee =
            Math.ceilDiv(nativeQuantity * (PERCENTAGE_SCALAR + s_nativeSurcharge), PERCENTAGE_SCALAR);

        fee_.assetAddress = quoteAddress;
        fee_.amount = Math.ceilDiv(surchargedFee * (PERCENTAGE_SCALAR - discount_), PERCENTAGE_SCALAR);

        return (fee_, rewards_, discount_);
    }

    /**
     * @notice Set the surcharge fee to be paid if paying in native.
     * @param surcharge The new surcharge fee value.
     */
    function setNativeSurcharge(uint64 surcharge) external {
        if (surcharge > PERCENTAGE_SCALAR) revert InvalidSurcharge();

        s_nativeSurcharge = surcharge;

        emit NativeSurchargeUpdated(surcharge);
    }

    /**
     * @notice Update the subscriber discount for a specific feed and token.
     * @param subscriber The address of the subscriber.
     * @param feedId The ID of the feed for which the discount is being updated.
     * @param token The address of the token (LINK or native).
     * @param discount The new discount value to be applied.
     */
    function updateSubscriberDiscount(address subscriber, bytes32 feedId, address token, uint64 discount) external {
        // Ensure the discount is not greater than the total discount that can be applied
        if (discount > PERCENTAGE_SCALAR) revert InvalidDiscount();
        // Ensure the token is either LINK or native
        if (token != i_nativeAddress) revert InvalidAddress();

        s_subscriberDiscounts[subscriber][feedId][token] = discount;

        emit SubscriberDiscountUpdated(subscriber, feedId, token, discount);
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Process a fee and reward for a given payload.
     * @param payload The encoded data containing the report and other necessary information.
     * @param subscriber The address of the subscriber trying to verify.
     * @return fee The calculated fee data.
     * @return reward The calculated reward data.
     * @return discount The current discount applied.
     */
    function _processFee(bytes calldata payload, address subscriber)
        internal
        view
        returns (IFeeManager.Asset memory, IFeeManager.Asset memory, uint256)
    {
        if (subscriber == address(this)) revert InvalidAddress();

        // Decode the report from the payload
        (, bytes memory report) = abi.decode(payload, (bytes32[3], bytes));

        return getFeeAndReward(subscriber, report, i_nativeAddress);
    }

    /**
     * @notice Handle fees and rewards for a given set of FeeAndReward structures.
     * @param subscriber The address of the subscriber trying to verify.
     * @param feesAndRewards An array containing FeeAndReward structures.
     * @param numberOfLinkFees The number of Link-based fees in the feesAndRewards array.
     * @param numberOfNativeFees The number of Native-based fees in the feesAndRewards array.
     */
    function _handleFeesAndRewards(
        address subscriber,
        FeeAndReward[] memory feesAndRewards,
        uint256 numberOfLinkFees,
        uint256 numberOfNativeFees
    ) internal {
        FeePayment[] memory nativeFeeLinkRewards = new FeePayment[](numberOfNativeFees);

        uint256 totalNativeFee;
        uint256 totalNativeFeeLinkValue;
        uint256 nativeFeeLinkRewardsIndex;

        uint256 totalNumberOfFees = numberOfLinkFees + numberOfNativeFees;
        for (uint256 i; i < totalNumberOfFees; ++i) {
            nativeFeeLinkRewards[nativeFeeLinkRewardsIndex++] =
                FeePayment(feesAndRewards[i].configDigest, uint192(feesAndRewards[i].reward.amount));
            totalNativeFee += feesAndRewards[i].fee.amount;
            totalNativeFeeLinkValue += feesAndRewards[i].reward.amount;

            if (feesAndRewards[i].appliedDiscount != 0) {
                emit DiscountApplied(
                    feesAndRewards[i].configDigest,
                    subscriber,
                    feesAndRewards[i].fee,
                    feesAndRewards[i].reward,
                    feesAndRewards[i].appliedDiscount
                );
            }
        }

        // Keep track of any change in case of over payment.
        uint256 change;

        if (msg.value != 0) {
            // Ensure there is enough value to cover the fee.
            if (totalNativeFee > msg.value) revert InvalidDeposit();

            // Wrap the amount required to pay the fee and approve as the subscriber paid in wrapped native.
            IWERC20(i_nativeAddress).deposit{ value: totalNativeFee }();

            unchecked {
                // msg.value is always >= to totalNativeFee.
                change = msg.value - totalNativeFee;
            }
        } else {
            if (totalNativeFee != 0) {
                // The subscriber has paid in wrapped native, so transfer the native to this contract.
                IERC20(i_nativeAddress).safeTransferFrom(subscriber, address(this), totalNativeFee);
            }
        }

        // A refund may be needed if the payee has paid in excess of the fee.
        _tryReturnChange(subscriber, change);
    }

    /**
     * @notice Try to return any excess payment to the subscriber.
     * @param subscriber The address of the subscriber to receive funds.
     * @param quantity The amount of native tokens to be returned.
     */
    function _tryReturnChange(address subscriber, uint256 quantity) internal {
        if (quantity != 0) {
            payable(subscriber).transfer(quantity);
        }
    }
}
