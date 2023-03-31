
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

import { CErc20 } from "../lending/CErc20.sol";
import { CToken } from "../lending/CToken.sol";
import { IERC20 } from "../lending/IERC20.sol";
import { Controller } from "../lending/Controller.sol";
import { InterestRateModel } from "../lending/InterestRateModel.sol";
import { WemixfiLendingOracle } from "../oracle/WemixfiLendingOracle.sol";
import { ControllerView } from "./ControllerView.sol";
import { Initializable } from "../common/upgradeable/Initializable.sol";
import "./WemixfiLendingViewInterface.sol";

contract WemixfiLendingView is Initializable, WemixfiLendingViewInterface {
    Controller public controller;
    WemixfiLendingOracle public priceOracle;

    string public constant mainSymbol = "WEMIX";
    string public constant mainCTokenSymbol = "cWEMIX";

    modifier onlyMasterAdmin() {
        require(msg.sender == controller.getMasterAdmin(), "E1");
        _;
    }

    modifier onlyServiceAdmin() {
        require(controller.getIsServiceAdmin(msg.sender), "E1");
        _;
    }

    function initialize(Controller controller_, WemixfiLendingOracle priceOracle_) public initializer {
        require(address(controller_) != address(0), "E117");
        require(address(priceOracle_) != address(0), "E117");
        controller = controller_;
        priceOracle = priceOracle_;
        emit NewController(address(controller_));
        emit NewPriceOracle(address(priceOracle_));
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* setters */
    function setController(Controller newController_) external onlyMasterAdmin {
        require(address(newController_) != address(0), "E117");
        controller = newController_;
        emit NewController(address(newController_));
    }

    function setPriceOracle(WemixfiLendingOracle priceOracle_) external onlyServiceAdmin {
        require(address(priceOracle_) != address(0), "E117");
        priceOracle = priceOracle_;
        emit NewPriceOracle(address(priceOracle_));
    }

    // returns CTokenInfo
    function getCTokenInfo(CToken cToken) public view returns (CTokenInfo memory) {
        address underlyingAssetAddress;
        uint256 underlyingDecimals;
        bool isWEMIX = compareStrings(cToken.symbol(), mainCTokenSymbol);
        CTokenInfo memory cTokenInfo;

        if (isWEMIX) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            underlyingAssetAddress = cErc20.underlying();
            underlyingDecimals = IERC20(cErc20.underlying()).decimals();
        }

        address contractAddress = address(cToken);

        cTokenInfo.underlyingAssetAddress = underlyingAssetAddress;
        cTokenInfo.underlyingDecimals = underlyingDecimals;
        cTokenInfo.contractAddress = contractAddress;
        cTokenInfo.poolBalance = isWEMIX
            ? contractAddress.balance
            : IERC20(underlyingAssetAddress).balanceOf(contractAddress);
        cTokenInfo.underlyingSymbol = cToken.underlyingSymbol();
        cTokenInfo.symbol = cToken.symbol();
        cTokenInfo.decimals = cToken.decimals();
        cTokenInfo.supplyRatePerBlock = cToken.supplyRatePerBlock();
        cTokenInfo.borrowRatePerBlock = cToken.borrowRatePerBlock();
        cTokenInfo.totalSupply = cToken.totalSupply();
        cTokenInfo.totalBorrows = cToken.totalBorrows();
        (, cTokenInfo.collateralFactor, ) = controller.markets(contractAddress);

        cTokenInfo.oraclePrice = getOraclePrice(cToken);

        cTokenInfo.incentiveTokenSpeed = controller.incentiveTokenSpeeds(contractAddress);
        cTokenInfo.totalReserves = cToken.totalReserves();
        cTokenInfo.cash = cToken.getCash();
        (, cTokenInfo.incentiveTokenSupplyBlock) = controller.incentiveTokenSupplyState(contractAddress);
        (, cTokenInfo.incentiveTokenBorrowBlock) = controller.incentiveTokenBorrowState(contractAddress);
        cTokenInfo.reserveFactorMantissa = cToken.reserveFactorMantissa();
        cTokenInfo.exchangeRateCurrent = cToken.exchangeRateCurrent();

        InterestRateModel interestRateModel = cToken.interestRateModel();

        cTokenInfo.multiplierPerBlock = interestRateModel.multiplierPerBlock();
        cTokenInfo.kink = interestRateModel.kink();
        cTokenInfo.baseRatePerBlock = interestRateModel.baseRatePerBlock();
        cTokenInfo.jumpMultiplierPerBlock = interestRateModel.jumpMultiplierPerBlock();

        cTokenInfo.isMintPaused = controller.isMintPaused(contractAddress);
        cTokenInfo.isBorrowPaused = controller.isBorrowPaused(contractAddress);
        cTokenInfo.isSeizePaused = controller.isSeizePaused(contractAddress);
        cTokenInfo.isTransferPaused = controller.isTransferPaused(contractAddress);
        cTokenInfo.isOraclePaused = controller.isOraclePaused(contractAddress);

        cTokenInfo.borrowCap = controller.borrowCaps(contractAddress);

        return cTokenInfo;
    }

    // returns AccountInfo
    function getAccountInfo(CToken cToken, address payable account) public view returns (AccountInfo memory) {
        AccountInfo memory accountInfo;

        address underlyingAssetAddress;
        address contractAddress = address(cToken);

        bool isWEMIX = compareStrings(cToken.symbol(), mainCTokenSymbol);
        if (isWEMIX) {
            underlyingAssetAddress = address(0);
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            underlyingAssetAddress = cErc20.underlying();
        }

        accountInfo.mySuppliedBalance = cToken.balanceOfUnderlying(account);
        accountInfo.myBorrowedBalance = cToken.borrowBalanceCurrent(account);
        accountInfo.mySupplyPrincipalBalance = cToken.supplyPrincipal(account);
        accountInfo.myBorrowPrincipalBalance = cToken.borrowPrincipal(account);
        accountInfo.myRealTokenBalance = isWEMIX ? account.balance : IERC20(underlyingAssetAddress).balanceOf(account);
        accountInfo.incentiveTokenSupplierIndex = controller.incentiveTokenSupplierIndex(contractAddress, account);
        accountInfo.incentiveTokenBorrowerIndex = controller.incentiveTokenBorrowerIndex(contractAddress, account);

        return accountInfo;
    }

    // get cToken's underlying price
    function getOraclePrice(CToken cToken) public view returns (uint256) {
        bool isWEMIX = compareStrings(cToken.symbol(), mainCTokenSymbol);
        uint8 decimals = uint8(18);
        if (!isWEMIX) {
            decimals = IERC20(CErc20(address(cToken)).underlying()).decimals();
            require(decimals <= uint8(18), "E118");
        }
        uint256 priceMantissa = priceOracle.getUnderlyingPrice(cToken.underlyingSymbol());

        if (decimals == uint8(18)) return priceMantissa;

        uint256 additionalDecimals = 18 - uint256(decimals);
        return priceMantissa / (10 ** additionalDecimals);
    }

    function cTokenMetaDataList() external view returns (CTokenMetaData[] memory) {
        CToken[] memory allMarkets = controller.getAllMarkets();
        CTokenMetaData[] memory result = new CTokenMetaData[](allMarkets.length);

        for (uint256 i = 0; i < allMarkets.length; i++) {
            result[i].cTokenInfo = getCTokenInfo(allMarkets[i]);
        }
        return result;
    }

    function cTokenMetaDataListAuth(address payable account) external view returns (CTokenMetaData[] memory) {
        CToken[] memory allMarkets = controller.getAllMarkets();
        CTokenMetaData[] memory result = new CTokenMetaData[](allMarkets.length);

        for (uint256 i = 0; i < allMarkets.length; i++) {
            result[i].cTokenInfo = getCTokenInfo(allMarkets[i]);
            result[i].accountInfo = getAccountInfo(allMarkets[i], account);
        }
        return result;
    }

    function getLiquidationInfo(address payable account) external view returns (LiquidationInfo memory) {
        LiquidationInfo memory liquidationInfo;

        ControllerView controllerView = controller.controllerView();
        (, , uint256 shortfall) = controllerView.getAccountLiquidity(account);

        // 청산 대상 여부 기록
        if (shortfall > 0) {
            liquidationInfo.isLiquidateTarget = true;
        } else {
            liquidationInfo.isLiquidateTarget = false;
        }

        CToken[] memory allMarkets = controller.getAllMarkets();
        liquidationInfo.tokenInfo = new TokenInfo[](allMarkets.length);

        uint256 closeFactor = controller.closeFactorMantissa();

        for (uint256 i = 0; i < allMarkets.length; i++) {
            liquidationInfo.tokenInfo[i].underlyingTokenAddr = allMarkets[i].underlying();
            liquidationInfo.tokenInfo[i].cTokenAddr = address(allMarkets[i]);
            liquidationInfo.tokenInfo[i].price = getOraclePrice(allMarkets[i]);

            // 대출 자산인지 여부 확인
            uint256 borrowAmount = allMarkets[i].borrowBalanceStored(account);
            if (borrowAmount > 0) liquidationInfo.tokenInfo[i].isBorrowAsset = true;

            // 담보 자산인지 여부 확인
            uint256 collateralAmount = allMarkets[i].balanceOfUnderlying(account);
            if (collateralAmount > 0) {
                liquidationInfo.tokenInfo[i].isCollateralAsset = true;
            }

            // account가 청산 대상일 경우
            if (shortfall > 0) {
                liquidationInfo.tokenInfo[i].repayAmountMax = (borrowAmount * closeFactor) / 1e18;
                if (collateralAmount > 0) {
                    liquidationInfo.tokenInfo[i].collateralUnderlyingTokenAmount = collateralAmount;
                }
            }
        }

        return liquidationInfo;
    }

    function calculateLiquidatorSeizeAmount(
        CToken cTokenBorrowed,
        CToken cTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256) {
        ControllerView controllerView = controller.controllerView();
        (, uint256 totalSeizeTokens) = controllerView.liquidateCalculateSeizeTokens(
            address(cTokenBorrowed),
            address(cTokenCollateral),
            actualRepayAmount
        );

        uint256 protocolSeizeShare = cTokenCollateral.protocolSeizeShareMantissa();
        uint256 protocolSeizeTokens = (totalSeizeTokens * protocolSeizeShare) / 1e18;
        uint256 liquidatorSeizeTokens = totalSeizeTokens - protocolSeizeTokens;
        uint256 exchangeRateMantissa = cTokenCollateral.exchangeRateStored();
        uint256 liquidatorSeizeAmount = (exchangeRateMantissa * liquidatorSeizeTokens) / 1e18;
        uint256 totalSeizeAmount = (exchangeRateMantissa * totalSeizeTokens) / 1e18;

        return (liquidatorSeizeAmount, totalSeizeAmount);
    }

    /* internal functions  */
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
