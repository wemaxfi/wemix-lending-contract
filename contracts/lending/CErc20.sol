// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CErc20.sol

import "./CToken.sol";

contract CErc20 is Initializable, CToken, CErc20Interface {
    function initialize(
        ControllerInterface controller_,
        InterestRateModel interestRateModel_,
        ControllerView controllerView_,
        TransactionHelper transactionHelper_,
        uint256 initialExchangeRateMantissa_,
        address underlying_,
        string memory name_,
        string memory symbol_,
        bytes32 underlyingSymbol_,
        uint8 decimals_
    ) public initializer {
        initializeCToken(
            controller_,
            interestRateModel_,
            controllerView_,
            transactionHelper_,
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            underlyingSymbol_,
            decimals_,
            underlying_
        );
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice User supplies assets into the market and receives cTokens in exchange
     * @param mintAmount The amount of the underlying asset to supply
     * @return actualMintAmount The actual supplied amount of the underlying asset
     */
    function mint(uint256 mintAmount) external override returns (uint256 actualMintAmount) {
        return mintFresh(msg.sender, mintAmount);
    }

    /**
     * @notice User supplies assets into the market and receives cTokens in exchange through TransactionHelper
     * @dev only TransactionHelper contract can call this function
     * @param caller user address who mints cToken
     * @param mintAmount The amount of the underlying asset to supply
     * @return actualMintAmount The actual supplied amount of the underlying asset
     */
    function mintHelper(address caller, uint256 mintAmount) external returns (uint256 actualMintAmount) {
        require(msg.sender == address(transactionHelper), "CTokenError: ACCESS_DENIED");
        return mintFresh(caller, mintAmount);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        CTokenInterface cTokenCollateral
    ) external override returns (uint256) {
        liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
        return NO_ERROR;
    }

    /**
     * @notice caller repays their own borrow by TransactionHelper
     * @dev only TransactionHelper can call this function
     * @param caller user address who repays the borrow
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrowHelper(address caller, uint256 repayAmount) external returns (uint256) {
        require(msg.sender == address(transactionHelper), "E1");
        accrueInterest();
        repayBorrowHelperInternal(caller, repayAmount);
        return NO_ERROR;
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrow(uint256 repayAmount) external payable override returns (uint256) {
        accrueInterest();
        repayBorrowInternal(repayAmount);
        return NO_ERROR;
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external override returns (uint256) {
        repayBorrowBehalfInternal(borrower, repayAmount);
        return NO_ERROR;
    }

    function doTransferIn(address sender, uint256 amount) internal override returns (uint256) {
        IERC20 token = IERC20(underlying);

        uint256 balanceBeforeTransfer = IERC20(underlying).balanceOf(address(this));
        token.transferFrom(sender, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "E79");

        uint256 balanceAfterTransfer = IERC20(underlying).balanceOf(address(this));
        require(balanceAfterTransfer >= balanceBeforeTransfer, "E80");

        return balanceAfterTransfer - balanceBeforeTransfer;
    }

    function doTransferOut(address payable recipient, uint256 amount) internal override returns (uint256) {
        IERC20 token = IERC20(underlying);
        token.transfer(recipient, amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a complaint ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "E81");
        return amount;
    }

    function getCashPrior() internal view override returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /**
     * @notice add underlying asset to totalReserves
     * @param addAmount underlying asset amount to add to totalReserves
     */
    function addReserves(uint256 addAmount) external override returns (uint256) {
        return addReservesInternal(addAmount);
    }
}
