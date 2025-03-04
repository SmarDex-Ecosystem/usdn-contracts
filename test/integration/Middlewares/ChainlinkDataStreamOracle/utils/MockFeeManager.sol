// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { console } from "forge-std/Test.sol";

import { IFeeManager } from "../../../../../src/interfaces/OracleMiddleware/IFeeManager.sol";

interface IWERC20 {
    function deposit() external payable;
}

contract MockFeeManager is IERC165 {
    using SafeERC20 for IERC20;

    /**
     * @notice The structure to hold a fee and reward to verify a report
     * @param digest the digest linked to the fee and reward
     * @param fee the fee paid to verify the report
     * @param reward the reward paid upon verification
     * @param appliedDiscount the discount applied to the reward
     */
    struct FeeAndReward {
        bytes32 configDigest;
        IFeeManager.Asset fee;
        IFeeManager.Asset reward;
        uint256 appliedDiscount;
    }

    /**
     * @notice The structure to hold a fee payment notice
     * @param poolId the poolId receiving the payment
     * @param amount the amount being paid
     */
    struct FeePayment {
        bytes32 poolId;
        uint192 amount;
    }

    /// @notice list of subscribers and their discounts subscriberDiscounts[subscriber][feedId][token]
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public s_subscriberDiscounts;

    /// @notice the total discount that can be applied to a fee, 1e18 = 100% discount
    uint64 private constant PERCENTAGE_SCALAR = 1e18;

    /// @notice the native token address
    address public constant i_nativeAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice the surcharge fee to be paid if paying in native
    uint256 public s_nativeSurcharge;

    /// @notice the error thrown if the discount or surcharge is invalid
    error InvalidSurcharge();

    /// @notice the error thrown if the discount is invalid
    error InvalidDiscount();

    /// @notice the error thrown if the address is invalid
    error InvalidAddress();

    /// @notice thrown if msg.value is supplied with a bad quote
    error InvalidDeposit();

    /// @notice thrown if a report has expired
    error ExpiredReport();

    /// @notice thrown if a report has no quote
    error InvalidQuote();

    /// @notice Emitted whenever a subscriber's discount is updated
    /// @param subscriber address of the subscriber to update discounts for
    /// @param feedId Feed ID for the discount
    /// @param token Token address for the discount
    /// @param discount Discount to apply, in relation to the PERCENTAGE_SCALAR
    event SubscriberDiscountUpdated(address indexed subscriber, bytes32 indexed feedId, address token, uint64 discount);

    /// @notice Emitted when updating the native surcharge
    /// @param newSurcharge Surcharge amount to apply relative to PERCENTAGE_SCALAR
    event NativeSurchargeUpdated(uint64 newSurcharge);

    /// @notice Emitted when funds are withdrawn
    /// @param adminAddress Address of the admin
    /// @param recipient Address of the recipient
    /// @param assetAddress Address of the asset withdrawn
    /// @param quantity Amount of the asset withdrawn
    event Withdraw(address adminAddress, address recipient, address assetAddress, uint192 quantity);

    /// @notice Emits when a fee has been processed
    /// @param configDigest Config digest of the fee processed
    /// @param subscriber Address of the subscriber who paid the fee
    /// @param fee Fee paid
    /// @param reward Reward paid
    /// @param appliedDiscount Discount applied to the fee
    event DiscountApplied(
        bytes32 indexed configDigest,
        address indexed subscriber,
        IFeeManager.Asset fee,
        IFeeManager.Asset reward,
        uint256 appliedDiscount
    );

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == this.processFee.selector || interfaceId == this.processFeeBulk.selector;
    }

    function processFee(bytes calldata payload, bytes calldata, address subscriber) external payable {
        (IFeeManager.Asset memory fee, IFeeManager.Asset memory reward, uint256 appliedDiscount) =
            _processFee(payload, subscriber);
        console.log("fee.amount", fee.amount);

        if (fee.amount == 0) {
            _tryReturnChange(subscriber, msg.value);
            return;
        }

        FeeAndReward[] memory feeAndReward = new FeeAndReward[](1);
        feeAndReward[0] = FeeAndReward(bytes32(payload), fee, reward, appliedDiscount);

        _handleFeesAndRewards(subscriber, feeAndReward, 0, 1);
    }

    function processFeeBulk(bytes[] calldata payloads, bytes calldata parameterPayload, address subscriber)
        external
        payable
    { }

    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        public
        view
        returns (IFeeManager.Asset memory fee_, IFeeManager.Asset memory rewards_, uint256 discount_)
    {
        // get the feedId from the report
        bytes32 feedId = bytes32(report);

        // verify the quote payload is a supported token
        if (quoteAddress != i_nativeAddress) {
            revert InvalidQuote();
        }

        //decode the report depending on the version
        uint256 nativeQuantity;
        uint256 expiresAt;
        (,,, nativeQuantity,, expiresAt) = abi.decode(report, (bytes32, uint32, uint32, uint192, uint192, uint32));

        //read the timestamp bytes from the report data and verify it has not expired
        if (expiresAt < block.timestamp) {
            revert ExpiredReport();
        }

        //get the discount being applied
        discount_ = s_subscriberDiscounts[subscriber][feedId][quoteAddress];

        uint256 surchargedFee =
            Math.ceilDiv(nativeQuantity * (PERCENTAGE_SCALAR + s_nativeSurcharge), PERCENTAGE_SCALAR);

        fee_.assetAddress = quoteAddress;
        fee_.amount = Math.ceilDiv(surchargedFee * (PERCENTAGE_SCALAR - discount_), PERCENTAGE_SCALAR);

        console.log("fee_.assetAddress", fee_.assetAddress);
        console.log("fee_.amount", fee_.amount);

        return (fee_, rewards_, discount_);
    }

    function setNativeSurcharge(uint64 surcharge) external {
        if (surcharge > PERCENTAGE_SCALAR) revert InvalidSurcharge();

        s_nativeSurcharge = surcharge;

        emit NativeSurchargeUpdated(surcharge);
    }

    function updateSubscriberDiscount(address subscriber, bytes32 feedId, address token, uint64 discount) external {
        //make sure the discount is not greater than the total discount that can be applied
        if (discount > PERCENTAGE_SCALAR) revert InvalidDiscount();
        //make sure the token is either LINK or native
        if (token != i_nativeAddress) revert InvalidAddress();

        s_subscriberDiscounts[subscriber][feedId][token] = discount;

        emit SubscriberDiscountUpdated(subscriber, feedId, token, discount);
    }

    function _processFee(bytes calldata payload, address subscriber)
        internal
        view
        returns (IFeeManager.Asset memory, IFeeManager.Asset memory, uint256)
    {
        if (subscriber == address(this)) revert InvalidAddress();

        //decode the report from the payload
        (, bytes memory report) = abi.decode(payload, (bytes32[3], bytes));

        return getFeeAndReward(subscriber, report, i_nativeAddress);
    }

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

        //keep track of change in case of any over payment
        uint256 change;

        if (msg.value != 0) {
            //there must be enough to cover the fee
            if (totalNativeFee > msg.value) revert InvalidDeposit();

            //wrap the amount required to pay the fee & approve as the subscriber paid in wrapped native
            IWERC20(i_nativeAddress).deposit{ value: totalNativeFee }();

            unchecked {
                //msg.value is always >= to fee.amount
                change = msg.value - totalNativeFee;
            }
        } else {
            if (totalNativeFee != 0) {
                //subscriber has paid in wrapped native, so transfer the native to this contract
                IERC20(i_nativeAddress).safeTransferFrom(subscriber, address(this), totalNativeFee);
            }
        }

        // a refund may be needed if the payee has paid in excess of the fee
        _tryReturnChange(subscriber, change);
    }

    function _tryReturnChange(address subscriber, uint256 quantity) internal {
        if (quantity != 0) {
            payable(subscriber).transfer(quantity);
        }
    }
}
