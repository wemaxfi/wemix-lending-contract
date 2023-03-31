// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterface.sol

import "./ControllerInterface.sol";
import "./InterestRateModel.sol";
import "./TransactionHelper.sol";

import "../views/ControllerView.sol";

/// @notice Contract that has storage variables and structs used in CToken.sol
/// @dev CTokenInterface inherits this contract for storage variables and structs
contract CTokenStorage {
    /// @notice Underlying asset for this CToken, ZERO_ADDRESS for Ether
    address public underlying;
    /// @notice Indicator that this is a CToken contract (for inspection)
    bool public constant isCToken = true;
    ///  @dev Guard variable for re-entrancy checks
    bool internal _notEntered;

    uint256 public constant NO_ERROR = 0;
    uint256 public constant expScale = 1e18;
    uint256 public constant doubleScale = 1e36;

    /// @notice EIP-20 token symbol of the underlying asset of the CToken
    bytes32 public underlyingSymbol;
    /// @notice EIP-20 token name for this token
    string public name;
    /// @notice EIP-20 token symbol for this token
    string public symbol;
    /// @notice EIP-20 token decimals for this token
    uint8 public decimals;

    /// @notice Total amount of outstanding borrows of the underlying in this market
    uint256 public totalBorrows;
    /// @notice Total number of tokens in circulation
    uint256 public totalSupply;

    /// @notice last block number that interest is accrued in this market
    uint256 public accrualBlockNumber;
    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint256 public borrowIndex;
    ///  @notice Total amount of reserves of the underlying held in this market
    uint256 public totalReserves;
    /// @notice Fraction of interest currently set aside for reserves
    uint256 public reserveFactorMantissa;
    // Initial exchange rate used when minting the first CTokens (used when totalSupply = 0)
    uint256 public initialExchangeRateMantissa;
    /// @notice Share of seized collateral that is added to reserves
    uint256 public protocolSeizeShareMantissa;

    // Maximum borrow rate that can ever be applied (.0005% / block)
    uint256 internal constant borrowRateMaxMantissa = 0.0005e16;
    // Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant reserveFactorMaxMantissa = 1e18;

    ControllerInterface public controller;
    InterestRateModel public interestRateModel;
    /// @dev Contract that has some view functions of controller logic - used to calculate seize tokens in liquidation at CToken
    ControllerView public controllerView;
    /// @dev Contract that interacts with CToken and enables multiple actions (ex. mint & borrow) in single transaction
    TransactionHelper public transactionHelper;

    // mapping

    /// @notice Official record of token balances for each account
    mapping(address => uint256) public accountBalances;
    /// @notice Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint256)) public transferAllowances;
    /// @notice Principal amount of underlying asset the account supplied
    mapping(address => uint256) public supplyPrincipal;
    /// @notice Principal amount of underlying asset the account borrowed
    mapping(address => uint256) public borrowPrincipal;
    // Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) internal accountBorrows;

    // structs
    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    struct MintLocalVars {
        uint256 exchangeRateMantissa;
        uint256 mintTokens;
        uint256 totalSupplyNew;
        uint256 accountBalancesNew;
        uint256 actualMintAmount;
        uint256 supplyPrincipalNew;
    }

    struct TransferLocalVars {
        uint256 exchangeRateMantissa;
        uint256 underlyingAmount;
        uint256 currentBalanceOfUnderlying;
        uint256 transferGap;
    }

    /// @notice storage gap for upgrading contract
    /// @dev warning: should reduce the appropriate number of slots when adding storage variables
    /// @dev resources: https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    uint256[50] private __gap;
}

/// @notice Contract that has basic function definitions and event definitions for CToken
/// @dev CToken inherits this contract for storage, structs, events and basic function definitions
abstract contract CTokenInterface is CTokenStorage {
    // functions
    function transfer(address recipient, uint256 amount) external virtual returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual returns (bool);

    function balanceOf(address owner) external view virtual returns (uint256);

    function approve(address spender, uint256 amount) external virtual returns (bool);

    function allowance(address owner, address spender) external view virtual returns (uint256);

    function accrueInterest() public virtual returns (uint256);

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external virtual returns (uint256);

    // events
    /// @notice Emitted when master admin address is changed
    event NewMasterAdmin(address newMasterAdmin);
    /// @notice Emitted when list of service admin is changed
    event ServiceAdminSetted(address serviceAdminAddr, bool state);
    /// @notice Emitted when tokens are minted
    event Mint(address minter, uint256 mintAmount, uint256 mintTokens, address underlying);
    /// @notice Emitted when a borrow is repaid
    event RepayBorrow(
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 accountBorrows,
        uint256 totalBorrows,
        address underlying
    );
    /// @notice Emitted when underlying is borrowed
    event Borrow(address borrower, uint256 borrowAmount, address underlying);
    /// @notice Emitted when tokens are redeemed
    event Redeem(address redeemer, uint256 redeemAmount, address underlying);
    /// @notice EIP20 Transfer event
    event Transfer(address indexed sender, address indexed recipient, uint256 amount);
    /// @notice EIP20 Approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    /// @notice Emitted when error occurs
    event Failure(uint256 error, uint256 info, uint256 detail);
    /// @notice Emitted when a borrow is liquidated
    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address cTokenCollateral,
        uint256 seizeTokens,
        address collateralUnderlying
    );
    /// @notice Emitted when interest is accrued
    event AccrueInterest(
        uint256 indexed accrualBlockNumber,
        uint256 interestAccumulated,
        uint256 borrowIndex,
        uint256 totalBorrows,
        uint256 totalReserves
    );
    /// @notice Emitted when reserve factor is changed
    event NewReserveFactor(uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa);
    /// @notice Emitted when reserves are added
    event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);
    /// @notice Emitted when reserves are reduced
    event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);
    /// @notice Emitted when Controller address is changed
    event NewController(ControllerInterface newController);
    /// @notice Emitted when ControllerView address is changed
    event NewControllerView(ControllerView newControllerView);
    /// @notice Emitted when InterestRateModel address is changed
    event NewTransactionHelper(TransactionHelper newTransactionHelper);
    /// @notice Emitted when InterestRateModel address is changed
    event NewInterestRateModel(InterestRateModel newInterestRateModel);
    /// @notice Emitted when protocolSeizeShare is changed
    event NewProtocolSeizeShare(uint256 oldProtocolSeizeShareMantissa, uint256 newProtocolSeizeShareMantissa);
}

/// @notice Contract that has function definitions only for CErc20
/// @dev CErc20 has some different function definitions with CEther for the functions in this contract
abstract contract CErc20Interface {
    function mint(uint256 mintAmount) external virtual returns (uint256);

    function repayBorrow(uint256 repayAmount) external payable virtual returns (uint256);

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        CTokenInterface cTokenCollateral
    ) external virtual returns (uint256);

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external virtual returns (uint256);

    /*** Admin Functions ***/
    function addReserves(uint256 addAmount) external virtual returns (uint256);
}
