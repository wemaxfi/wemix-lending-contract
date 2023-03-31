pragma solidity ^0.8.10;

import { CToken } from "../lending/CToken.sol";
import { Controller } from "../lending/Controller.sol";
import { WemixfiLendingOracle } from "../oracle/WemixfiLendingOracle.sol";

interface WemixfiLendingViewInterface {
    struct CTokenInfo {
        // cToken's underlying token's address
        address underlyingAssetAddress;
        // current exchange rate, scaled by 10^(18 + underlyingDecimals - decimals)
        uint256 exchangeRateCurrent;
        // token decimals of underlying token
        uint256 underlyingDecimals;
        // cToken's current balance of underlying token, scaled by underlyingDecimals
        uint256 poolBalance;
        // token symbol of underlying token
        bytes32 underlyingSymbol;
        // token symbol of cToken
        string symbol;
        // token decimals of cToken
        uint8 decimals;
        // contract(token) address of cToken
        address contractAddress;
        // current supply interest rate per block , scaled by 1e18
        uint256 supplyRatePerBlock;
        // current borrow interest rate per block , scaled by 1e18
        uint256 borrowRatePerBlock;
        // token total supply of cToken, scaled by cToken's decimals
        uint256 totalSupply;
        // total borrowed amount of underlying token, scaled by underlyingDecimals
        uint256 totalBorrows;
        // Multiplier representing the most one can borrow against their collateral in this market, scaled by 1e18
        uint256 collateralFactor;
        // oracle price of the cToken's underlying token, scaled by 1e18
        uint256 oraclePrice;
        // the amount of incentive tokens that each market receives per block, scaled by incentive token's decimals
        uint256 incentiveTokenSpeed;
        //  Total amount of reserves of the underlying held in this market, scaled by underlyingDecimals
        uint256 totalReserves;
        // cToken's current balance of underlying token, scaled by underlyingDecimals
        uint256 cash;
        // The block number the incentive token supply index was last updated at
        uint256 incentiveTokenSupplyBlock;
        // The block number the incentive token borrow index was last updated at
        uint256 incentiveTokenBorrowBlock;
        //  Fraction of interest currently set aside for reserves, scaled by 1e18
        uint256 reserveFactorMantissa;
        /* interest rate model info -- check Compound's interest rate model */
        // The multiplier of utilization rate that gives the slope of the interest rate, scaled by 1e18
        uint256 multiplierPerBlock;
        // The utilization point at which the jump multiplier is applied, scaled by 1e18
        uint256 kink;
        // The base interest rate which is the y-intercept when utilization rate is 0, scaled by 1e18
        uint256 baseRatePerBlock;
        // The multiplierPerBlock after hitting a specified utilization point, scaled by 1e18
        uint256 jumpMultiplierPerBlock;
        // Flag whether mint is allowed or paused
        bool isMintPaused;
        // Flag whether borrow is allowed or paused
        bool isBorrowPaused;
        // Flag whether seize is allowed or paused
        bool isSeizePaused;
        // Flag whether transfer is allowed or paused
        bool isTransferPaused;
        // Maximum amount that can be borrowed in the pool
        uint256 borrowCap;
        // Flag whether oracle is paused -- if true, stop redeem, borrow, liquidate
        bool isOraclePaused;
    }

    // account related info of each cToken
    struct AccountInfo {
        // account's deposited amount of underlying token, scaled by underlyingDecimals of cToken
        uint256 mySuppliedBalance;
        // account's borrowed amount of underlying token, scaled by underlyingDecimals of cToken
        uint256 myBorrowedBalance;
        // account's supplyPrincipal amount of underlying token, scaled by underlyingDecimals of cToken
        uint256 mySupplyPrincipalBalance;
        // account's borrowPrincipal amount of underlying token, scaled by underlyingDecimals of cToken
        uint256 myBorrowPrincipalBalance;
        // account's current balance of underlying token, scaled by underlyingDecimals of cToken
        uint256 myRealTokenBalance;
        // account's supplier index for incentiveToken in cToken, scaled by incentiveToken's decimals
        uint256 incentiveTokenSupplierIndex;
        // account's borrower index for incentiveToken in cToken, scaled by incentiveToken's decimals
        uint256 incentiveTokenBorrowerIndex;
    }

    struct CTokenMetaData {
        CTokenInfo cTokenInfo;
        AccountInfo accountInfo; // only used in cTokenMetaDataListAuth
    }

    struct LiquidationInfo {
        bool isLiquidateTarget;
        TokenInfo[] tokenInfo;
    }

    struct TokenInfo {
        address underlyingTokenAddr;
        address cTokenAddr;
        bool isCollateralAsset;
        bool isBorrowAsset;
        uint256 price;
        uint256 repayAmountMax;
        uint256 collateralUnderlyingTokenAmount;
    }

    /* events */
    /// @notice Emitted when controller address is changed by admin
    event NewController(address newController);
    /// @notice Emitted when price oracle address is changed by admin
    event NewPriceOracle(address newPriceOracle);

    /* view functions */
    /// @notice Return CTokenMetaData of all markets, without AccountInfo
    function cTokenMetaDataList() external view returns (CTokenMetaData[] memory);

    /// @notice Return CTokenMetaData of all markets, including AccountInfo
    /// @param account account address to fetch AccountInfo from all markets
    function cTokenMetaDataListAuth(address payable account) external view returns (CTokenMetaData[] memory);

    /// @notice Return CTokenInfo of the cToken
    function getCTokenInfo(CToken cToken) external view returns (CTokenInfo memory);

    /// @notice Return AccountInfo of the cToken
    function getAccountInfo(CToken cToken, address payable account) external view returns (AccountInfo memory);

    /// @notice Return cToken's underlying token's price from price oracle
    /// @param cToken cToken's address to fetch price of its underlying token
    /// @return Price of cTokens underying token, 1e18 scaled
    function getOraclePrice(CToken cToken) external view returns (uint256);

    /// @notice Return liquidation data of the account
    /// @param account account address to get liquidation data
    function getLiquidationInfo(address payable account) external view returns (LiquidationInfo memory);

    /// @notice Return amount of the token for liquidation
    /// @param cTokenBorrowed CToken address of the borrowed asset
    /// @param cTokenCollateral CToken address of the collateral asset
    /// @param actualRepayAmount repay amount for the liquidation
    function calculateLiquidatorSeizeAmount(
        CToken cTokenBorrowed,
        CToken cTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256);

    /* setters */
    /// @dev only admin
    function setController(Controller newController_) external;

    /// @dev only admin
    function setPriceOracle(WemixfiLendingOracle priceOracle_) external;
}
