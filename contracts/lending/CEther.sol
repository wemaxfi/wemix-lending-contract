// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CEther.sol

import "./CToken.sol";

contract CEther is Initializable, CToken {
    function initialize(
        ControllerInterface controller_,
        InterestRateModel interestRateModel_,
        ControllerView controllerView_,
        TransactionHelper transactionHelper_,
        uint256 initialExchangeRateMantissa_,
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
            address(0)
        );
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        mintFresh(msg.sender, msg.value);
    }

    /**
     * @notice User supplies assets into the market and receives cTokens in exchange
     * @dev for cEther, mintAmount == msg.value
     * @return actualMintAmount The actual supplied amount of the underlying asset
     */
    function mint() external payable returns (uint256 actualMintAmount) {
        return mintFresh(msg.sender, msg.value);
    }

    /**
     * @notice User supplies assets into the market and receives cTokens in exchange through TransactionHelper
     * @dev only TransactionHelper contract can call this function
     *  for cEther, mintAmount == msg.value
     * @param caller user address who mints cToken
     * @return actualMintAmount The actual supplied amount of the underlying asset
     */
    function mintHelper(address caller) external payable returns (uint256 actualMintAmount) {
        require(msg.sender == address(transactionHelper), "E1");
        return mintFresh(caller, msg.value);
    }

    /**
     * @notice caller repays their own borrow by TransactionHelper
     * @dev only TransactionHelper can call this function
     *  for cEther, repayAmount == msg.sender
     * @param caller user address who repays the borrow
     */
    function repayBorrowHelper(address caller) external payable returns (uint256) {
        require(msg.sender == address(transactionHelper), "E1");
        accrueInterest();
        repayBorrowHelperInternal(caller, msg.value);
        return NO_ERROR;
    }

    /**
     * @notice Sender repays their own borrow
     * @dev for cEther, repayAmount == msg.value
     */
    function repayBorrow() external payable returns (uint256, uint256) {
        accrueInterest();
        repayBorrowInternal(msg.value);
    }

    /**
     * @notice Sender repays their own borrow
     * @param borrower the account with the debt being payed off
     * @dev for cEther, repayAmount == msg.value
     */
    function repayBorrowBehalf(address borrower) external payable {
        repayBorrowBehalfInternal(borrower, msg.value);
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @dev for cEther, repayAmount == msg.value
     * @param borrower The borrower of this cToken to be liquidated
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrow(address borrower, CToken cTokenCollateral) external payable {
        liquidateBorrowInternal(borrower, msg.value, cTokenCollateral);
    }

    function getCashPrior() internal view override returns (uint256) {
        uint256 startingBalance = address(this).balance - msg.value;
        return startingBalance;
    }

    function doTransferIn(address sender, uint256 amount) internal override returns (uint256) {
        require(msg.sender == sender || msg.sender == address(transactionHelper), "E77");
        require(msg.value == amount, "E78");

        return amount;
    }

    function doTransferOut(address payable recipient, uint256 amount) internal override returns (uint256) {
        recipient.transfer(amount);

        return amount;
    }

    /**
     * @notice add underlying asset to totalReserves
     * @dev for cEther, addAmount == msg.value
     */
    function addReserves() external payable returns (uint256) {
        return addReservesInternal(msg.value);
    }
}
