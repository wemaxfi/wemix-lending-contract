// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/ComptrollerStorage.sol

import { CToken } from "./CToken.sol";
import { ControllerView } from "../views/ControllerView.sol";
import { WemixfiLendingOracle } from "../oracle/WemixfiLendingOracle.sol";

contract ControllerStorage {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        // Multiplier representing the most one can borrow against their collateral in this market.
        uint256 collateralFactorMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market is IncentiveToken market
        bool isIncentiveTokenMarket;
    }

    /// @notice Address of the price oracle contract
    WemixfiLendingOracle public priceOracle;

    /// @notice Address of the view contract for the contract
    ControllerView public controllerView;

    /// @notice The initial incentive token index for a market
    uint224 public constant incentiveTokenInitialIndex = 1e36;
    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant closeFactorMinMantissa = 0.05e18; // 0.05
    // closeFactorMantissa must not exceed this value
    uint256 internal constant closeFactorMaxMantissa = 0.9e18; // 0.9
    // No collateralFactorMantissa may exceed this value
    uint256 internal constant collateralFactorMaxMantissa = 1e18; // 1

    uint256 public constant NO_ERROR = 0;

    uint256 public constant expScale = 1e18;
    uint256 public constant doubleScale = 1e36;

    /// @notice master Administrator for this contract
    address public masterAdmin;
    /// @notice mapping of service Administrators for this contract
    mapping(address => bool) public isServiceAdmin;

    /// @notice Per-account mapping of "assets you are in"
    mapping(address => CToken[]) public accountAssets;

    /// @notice Official mapping of cTokens -> Market metadata
    /// @dev Used e.g. to determine if a market is supported
    mapping(address => Market) public markets;

    /// @notice address of ERC20 token registered as an incentive token
    address public INCENTIVE_TOKEN_ADDRESS;

    // Guardians
    /**
     * @notice is*Paused can pause certain actions as a safety machanism.
     * Actions which allow users to remove their owen assets cannot be paused.
     * each action can be paused by market.
     */
    mapping(address => bool) public isMintPaused;
    mapping(address => bool) public isBorrowPaused;
    mapping(address => bool) public isSeizePaused;
    mapping(address => bool) public isTransferPaused;
    mapping(address => bool) public isOraclePaused;

    /// @notice Multiplier representing the discount on collateral that a liquidator receives
    mapping(address => uint256) public liquidationIncentiveMantissa;

    /// @notice Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint256) public borrowCaps;

    /// @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
    uint256 public closeFactorMantissa;

    // Incentive Token
    struct IncentiveTokenMarketState {
        // The market's last updated incentiveTokenBorrowIndex or incentiveTokenSupplyIndex
        uint256 index;
        // The block number the index was last updated at
        uint256 block;
    }

    /// @notice A list of all markets
    CToken[] public allMarkets;

    /// @notice the amount of incentive tokens that each market receives, per block
    mapping(address => uint256) public incentiveTokenSpeeds;

    /// @notice the incentiveToken market supply state for each market
    mapping(address => IncentiveTokenMarketState) public incentiveTokenSupplyState;

    /// @notice the incentiveToken market borrow state for each market
    mapping(address => IncentiveTokenMarketState) public incentiveTokenBorrowState;

    /// @notice The incentiveToken supply index for each market for each supplier as of the last time they accrued incentiveToken
    mapping(address => mapping(address => uint256)) public incentiveTokenSupplierIndex;

    /// @notice The incentiveToken borrow index for each market for each borrower as of the last time they accrued incentiveToken
    mapping(address => mapping(address => uint256)) public incentiveTokenBorrowerIndex;

    /// @notice The incentiveToken accrued but not yet transferred to each user
    mapping(address => uint256) public incentiveTokenAccrued;

    /// @notice mapping that indicates each address is available of an unsecured loan (borrowing without collateral)
    /// @dev warning: if an address is registered as unsecuredBorrower, the address can borrow unlimited amount regardless of the amount of collateral the address deposited
    mapping(address => bool) public isUnsecuredBorrower;

    /// @notice list contains current serviceAdmin addresses
    /// @dev it is linked with isServiceAdmin mapping
    address[] public serviceAdminList;

    /// @notice storage gap for upgrading contract
    /// @dev warning: should reduce the appropriate number of slots when adding storage variables
    /// @dev resources: https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    uint256[50] private __gap;
}
