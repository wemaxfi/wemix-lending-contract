// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/ComptrollerInterface.sol

import "./CToken.sol";
import { WemixfiLendingOracle } from "../oracle/WemixfiLendingOracle.sol";
import { ControllerView } from "../views/ControllerView.sol";

abstract contract ControllerInterface {
    /// @notice Indicator that this is a Controller contract (for inspection)
    bool public constant isController = true;

    /// @notice returns master admin address
    function getMasterAdmin() external view virtual returns (address);

    /// @notice returns boolean indicates whether the address is serviceAdmin
    function getIsServiceAdmin(address serviceAdmin) external view virtual returns (bool);

    function exitMarket(address account) external virtual returns (uint256);

    /*** Policy Hooks ***/
    function mintAllowed(address cToken, address minter) external virtual returns (uint256);

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemAmount
    ) external virtual returns (uint256);

    function redeemVerify(uint256 redeemAmount, uint256 redeemTokens) external virtual;

    function borrowAllowed(
        address cToken,
        address payable borrower,
        uint256 borrowAmount
    ) external virtual returns (uint256);

    function repayBorrowAllowed(address cToken, address borrower) external virtual returns (uint256);

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        address liquidator,
        uint256 repayAmount
    ) external virtual returns (uint256);

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external virtual returns (uint256);

    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external virtual returns (uint256);

    // events
    /// @notice Emitted when an admin supports a market
    event MarketListed(CToken cToken);
    /// @notice Emitted when an account enters a market
    event MarketEntered(CToken cToken, address account);
    /// @notice Emitted when an account exits a market
    event MarketExited(CToken cToken, address account);
    /// @notice Emitted when an action is paused on a market
    event ActionPaused(CToken cToken, string action, bool pauseState);
    /// @notice Emitted when masterAdmin address is changed
    event NewMasterAdmin(address newMasterAdmin);
    /// @notice Emitted when serviceAdmin address state is changed
    event ServiceAdminSetted(address serviceAdminAddr, bool state);
    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(WemixfiLendingOracle newPriceOracle);
    /// @notice Emitted when ControllerView address is changed
    event NewControllerView(ControllerView newControllerView);
    /// @notice Emitted when incentive token address is changed
    event NewIncentiveToken(address newIncentiveTokenAddr);
    /// @notice Emitted when incentive token speed of a market is changed
    event IncentiveTokenSpeedUpdated(CToken indexed cToken, uint256 newSpeed);
    /// @notice Emitted when a state whether an address can borrow without collateral is changed
    event NewIsUnsecuredBorrower(address indexed borrower, bool newIsUnsecuredBorrower);
    /// @notice Emitted when liquidation incentive of the market is changed
    event NewLiquidationIncentive(CToken indexed cToken, uint256 newLiquidationIncentiveMantissa);
    /// @notice Emitted when borrow cap of the market is changed
    event NewBorrowCap(CToken indexed cToken, uint256 newBorrowCap);
    /// @notice Emitted when collateral factor of the market is changed
    event NewCollateralFactor(CToken cToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);
    /// @notice Emitted when close factor is changed globally
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);
    /// @notice Emitted when the market's incentiveToken supply index is updated
    event UpdateIncentiveTokenSupplyIndex(CToken indexed cToken, uint256 index, uint256 block);
    /// @notice Emitted when the market's incentiveToken borrow index is updated
    event UpdateIncentiveTokenBorrowIndex(
        CToken indexed cToken,
        uint256 marketBorrowIndex,
        uint256 index,
        uint256 block
    );
    /// @notice Emitted when incentive token is distributed to a supplier
    event DistributeSupplierIncentiveToken(
        CToken indexed cToken,
        address indexed supplier,
        uint256 incentiveTokenDelta,
        uint256 incentiveTokenSupplyIndex
    );
    /// @notice Emitted when incentive token is distributed to a borrower
    event DistributeBorrowerIncentiveToken(
        CToken indexed cToken,
        address indexed borrower,
        uint256 incentiveTokenDelta,
        uint256 incentiveTokenBorrowIndex
    );
    /// @notice Emitted when incentive token is claimed for the holder
    event ClaimIncentiveToken(
        address indexed holder,
        CToken indexed cToken,
        bool isBorrowerIncentive,
        uint256 incentiveTokenAccrued
    );
    /// @notice Emitted when incentive token is granted by admin
    event GrantIncentiveToken(address indexed recipient, uint256 amount);

    /// @notice Emitted when serviceAdmin is added
    event AddServiceAdmin(address newServiceAdmin);

    /// @notice Emitted when serviceAdmin is deleted
    event DeleteServiceAdmin(address previousServiceAdmin);
}
