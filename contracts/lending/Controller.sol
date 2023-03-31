// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/Comptroller.sol

import "./CToken.sol";
import "./ControllerInterface.sol";
import "./ControllerStorage.sol";
import "./Error.sol";
import "./IERC20.sol";

contract Controller is Initializable, ControllerInterface, ControllerStorage, ControllerErrorReport {
    //////////////////////////////////////////////////////////////////////////////////
    /// Initializer 및 컨트랙트 setter 함수
    //////////////////////////////////////////////////////////////////////////////////

    // Initializer
    function initialize(address masterAdmin_) public initializer {
        require(masterAdmin_ != address(0), "E117");

        masterAdmin = masterAdmin_;
        addServiceAdmin(masterAdmin_);

        emit NewMasterAdmin(masterAdmin_);
    }


    function getServiceAdminList() public view returns(address[] memory) {
        uint len = serviceAdminList.length;
        address[] memory result = new address[](len);

        for(uint i = 0; i < len; i += 1) {
            address serviceAdmin = serviceAdminList[i];
            result[i] = serviceAdmin;
        }

        return result;
    } 

    function addServiceAdmin(address newServiceAdmin) internal {
        require(newServiceAdmin != address(0), "E117");


        require(isServiceAdmin[newServiceAdmin] == false, 'Already ServiceAdmin');

        serviceAdminList.push(newServiceAdmin);
        isServiceAdmin[newServiceAdmin] = true;

        emit AddServiceAdmin(newServiceAdmin);
    }

    function deleteServiceAdmin(address previousServiceAdmin) internal {
        require(previousServiceAdmin != address(0), "E117");

        require(isServiceAdmin[previousServiceAdmin] == true, "Not ServiceAdmin");

        uint len = serviceAdminList.length;

        uint idx = len;

        require(len > 0);

        for (uint i = 0; i < len; i++) {
            if(previousServiceAdmin == serviceAdminList[i]) {
                idx = i;
                break;
            }
        }

        require(idx < len);

        serviceAdminList[idx] = serviceAdminList[len - 1];

        serviceAdminList.pop();

        isServiceAdmin[previousServiceAdmin] = false;

        emit DeleteServiceAdmin(previousServiceAdmin);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev only masterAdmin can set controllerView
     *  controllerView is used for getHypotheticalAccountLiquidity function here
     * @param controllerView_ new contract address to set as controllerView
     */
    function setControllerView(ControllerView controllerView_) external {
        require(msg.sender == masterAdmin, "E1");
        require(address(controllerView_) != address(0), "E117");
        controllerView = controllerView_;
        emit NewControllerView(controllerView_);
    }

    /**
     * @dev only serviceAdmin can set incentive token
     * @param incentiveTokenAddr new address to set as INCENTIVE_TOKEN_ADDRESS
     */
    function setIncentiveToken(address incentiveTokenAddr) external {
        require(isServiceAdmin[msg.sender], "E1");
        require(incentiveTokenAddr != address(0), "E117");
        INCENTIVE_TOKEN_ADDRESS = incentiveTokenAddr;
        emit NewIncentiveToken(incentiveTokenAddr);
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// MasterAdmin, ServiceAdmin 관련 함수
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice MasterAdmin Setter
     * @dev only masterAdmin can set masterAdmin
     * @param newMasterAdmin new address to set as masterAdmin
     */
    function setMasterAdmin(address newMasterAdmin) external {
        require(msg.sender == masterAdmin, "E1");
        require(newMasterAdmin != address(0), "E117");

        masterAdmin = newMasterAdmin;

        // MasterAdmin 설정 시 자동으로 ServiceAdmin이 되도록 설정
        if(isServiceAdmin[newMasterAdmin] == false) {
            addServiceAdmin(newMasterAdmin);
        }

        emit NewMasterAdmin(masterAdmin);
    }

    /**
     * @dev only masterAdmin can set serviceAdmin
     * @param serviceAdminAddr address to change isServiceAdmin
     * @param state new boolean state that indicates the address is serviceAdmin
     */
    function setServiceAdmin(address serviceAdminAddr, bool state) external {
        require(msg.sender == masterAdmin, "E1");

        if(state == true) {
            addServiceAdmin(serviceAdminAddr);
        } else {
            deleteServiceAdmin(serviceAdminAddr);
        }      
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 담보 자산 등록 관련 함수
    //////////////////////////////////////////////////////////////////////////////////

    /// @notice Add assets to be included in account liquidity calculation
    /// @param cToken the market to enter
    /// @param account the address of the account to modify
    function enterMarkets(address cToken, address account) internal returns (uint256) {
        CToken asset = CToken(cToken);
        return uint256(enterMarketsInternal(asset, account));
    }

    function enterMarketsInternal(CToken cToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(cToken)];

        if (!marketToJoin.isListed) {
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower]) {
            return Error.NO_ERROR;
        }

        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(cToken);

        emit MarketEntered(cToken, borrower);

        return Error.NO_ERROR;
    }

    /// @notice Removes sender asset from the account's liquidity calculation
    /// @dev CToken contract should call the function
    /// @param account account of liquidity that the sender asset should be removed from
    /// @return Whether or not the account successfully exited the market
    function exitMarket(address account) external override returns (uint256) {
        CToken cToken = CToken(msg.sender);
        (uint256 oErr, uint256 tokensHeld, uint256 amountOwed, ) = cToken.getAccountSnapshot(account);

        require(oErr == 0, "E82");

        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        uint256 allowed = redeemAllowedInternal(address(msg.sender), account, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(cToken)];

        if (!marketToExit.accountMembership[account]) return NO_ERROR;

        delete marketToExit.accountMembership[account];

        CToken[] memory userAssetList = accountAssets[account];
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i = 0; i < len; i++) {
            if (userAssetList[i] == cToken) {
                assetIndex = i;
                break;
            }
        }

        // require나 revert로 바꾸는 논의 필요
        assert(assetIndex < len);

        CToken[] storage storedList = accountAssets[account];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(cToken, account);

        return NO_ERROR;
    }

    /// @notice Add the market to the markets mapping and set is as listed
    /// @dev only service admin
    /// @param cToken the address of the market to list
    /// @return 0=success, otherwise a failure
    function supportMarket(CToken cToken) external returns (uint256) {
        if (isServiceAdmin[msg.sender] != true) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(cToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        cToken.isCToken();

        Market storage newMarket = markets[address(cToken)];
        newMarket.isListed = true;
        newMarket.isIncentiveTokenMarket = false;
        newMarket.collateralFactorMantissa = 0;

        supportMarketInternal(address(cToken));

        emit MarketListed(cToken);

        return uint256(Error.NO_ERROR);
    }

    function supportMarketInternal(address cToken) internal {
        for (uint256 i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != CToken(cToken), "E83");
        }
        allMarkets.push(CToken(cToken));
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 유저 액션 조건 검사 관련 함수 => 예치, 출금, 대출, 상환, 청산, 전송
    //////////////////////////////////////////////////////////////////////////////////

    // 예치 조건 확인
    /// @notice Checks if the account should be allowed to mint tokens in the given market
    /// @param cToken The market to verify the mint against
    /// @param minter The account which would get the minted tokens
    /// @return 0 if the mint is allowed, otherwise a error code
    function mintAllowed(address cToken, address minter) external override returns (uint256) {
        require(!isMintPaused[cToken], "E88");
        require(markets[cToken].isListed, "E86");
        uint256 enteredMarket = enterMarkets(cToken, minter);
        require(enteredMarket == uint256(Error.NO_ERROR), "E89");

        updateIncentiveTokenSupplyIndex(cToken);
        distributeSupplierIncentiveToken(cToken, minter);

        return uint256(Error.NO_ERROR);
    }

    // 출금 조건 확인
    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemAmount The number of cTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See Error.sol)
     */
    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemAmount
    ) external override returns (uint256) {
        require(!isOraclePaused[cToken], "E85");
        uint256 allowed = redeemAllowedInternal(cToken, redeemer, redeemAmount);
        require(allowed == uint256(Error.NO_ERROR), "E40");

        updateIncentiveTokenSupplyIndex(cToken);
        distributeSupplierIncentiveToken(cToken, redeemer);

        return uint256(Error.NO_ERROR);
    }

    function redeemAllowedInternal(
        address cToken,
        address redeemer,
        uint256 redeemAmount
    ) internal view returns (uint256) {
        require(markets[cToken].isListed, "E86");

        if (!markets[cToken].accountMembership[redeemer]) {
            return uint256(Error.NO_ERROR);
        }

        (Error err, , uint256 shortfall) = controllerView.getHypotheticalAccountLiquidity(
            redeemer,
            CToken(cToken),
            redeemAmount,
            0
        );
        if (err != Error.NO_ERROR) {
            return uint256(err);
        }

        // whitelist 된 주소는 shortfall 무시 -- 예치한 담보가치 이상 대출된 상태에서도 예치자산 인출 가능
        require(shortfall <= 0 || isUnsecuredBorrower[redeemer], "E100");

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection.
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(uint256 redeemAmount, uint256 redeemTokens) external override {
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    // 대출 조건 확인
    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See Error.sol)
     */
    function borrowAllowed(
        address cToken,
        address payable borrower,
        uint256 borrowAmount
    ) external override returns (uint256) {
        require(!isOraclePaused[cToken], "E90");
        require(!isBorrowPaused[cToken], "E91");
        require(markets[cToken].isListed, "E86");

        if (!markets[cToken].accountMembership[borrower]) {
            require(msg.sender == cToken, "E1");

            Error err = enterMarketsInternal(CToken(cToken), borrower);
            if (err != Error.NO_ERROR) {
                return uint256(err);
            }

            require(markets[cToken].accountMembership[borrower], "E89");
        }

        {
            uint256 borrowCap = borrowCaps[cToken];
            if (borrowCap != 0) {
                uint256 totalBorrows = CToken(cToken).totalBorrows();
                uint256 nextTotalBorrows = totalBorrows + borrowAmount;
                require(nextTotalBorrows < borrowCap, "E92");
            }
        }

        (Error err, , uint256 shortfall) = controllerView.getHypotheticalAccountLiquidity(
            borrower,
            CToken(cToken),
            0,
            borrowAmount
        );

        if (err != Error.NO_ERROR) {
            return uint256(err);
        }

        // whitelist 된 주소는 담보가치 shortfall 무시하고 대출 가능
        require(shortfall <= 0 || isUnsecuredBorrower[borrower], "E100");

        uint256 borrowIndex = CToken(cToken).borrowIndex();
        updateIncentiveTokenBorrowIndex(cToken, borrowIndex);
        distributeBorrowerIncentiveToken(cToken, borrower, borrowIndex);

        return uint256(Error.NO_ERROR);
    }

    // 상환 조건 확인
    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param borrower The account which have borrowed the asset
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See Error.sol)
     */
    function repayBorrowAllowed(address cToken, address borrower) external override returns (uint256) {
        require(markets[cToken].isListed, "E86");

        uint256 borrowIndex = CToken(cToken).borrowIndex();
        updateIncentiveTokenBorrowIndex(cToken, borrowIndex);
        distributeBorrowerIncentiveToken(cToken, borrower, borrowIndex);

        return uint256(Error.NO_ERROR);
    }

    // 청산 상환 조건 확인
    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower
    ) external override returns (uint256) {
        require(!isSeizePaused[cTokenCollateral], "E98");
        require(markets[cTokenCollateral].isListed, "E86");
        require(markets[cTokenBorrowed].isListed, "E86");
        require(CToken(cTokenCollateral).controller() == CToken(cTokenBorrowed).controller(), "E93");

        updateIncentiveTokenSupplyIndex(cTokenCollateral);
        distributeSupplierIncentiveToken(cTokenCollateral, borrower);
        distributeSupplierIncentiveToken(cTokenCollateral, liquidator);

        return NO_ERROR;
    }

    // 전송 조건 확인
    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param cToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See Error.sol)
     */
    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external override returns (uint256) {
        require(!isTransferPaused[cToken], "E87");

        uint256 allowed = redeemAllowedInternal(cToken, src, transferTokens);
        if (allowed != uint256(Error.NO_ERROR)) {
            return allowed;
        }

        updateIncentiveTokenSupplyIndex(cToken);
        distributeSupplierIncentiveToken(cToken, src);
        distributeSupplierIncentiveToken(cToken, dst);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        address liquidator,
        uint256 repayAmount
    ) external override returns (uint256) {
        if (!markets[cTokenBorrowed].isListed || !markets[cTokenCollateral].isListed) {
            return uint256(Error.MARKET_NOT_LISTED);
        }

        uint256 enteredMarket = enterMarkets(cTokenCollateral, liquidator);
        require(enteredMarket == uint256(Error.NO_ERROR), "E89");

        require(!isOraclePaused[cTokenCollateral] && !isOraclePaused[cTokenBorrowed], "E97");

        (Error err, , uint256 shortfall) = controllerView.getHypotheticalAccountLiquidity(
            borrower,
            CToken(address(0)),
            0,
            0
        );
        if (err != Error.NO_ERROR) {
            return uint256(err);
        }

        if (shortfall == 0) {
            return uint256(Error.INSUFFICIENT_SHORTFALL);
        }
        // whitelist 된 주소는 청산이 불가능
        if (isUnsecuredBorrower[borrower]) {
            return uint256(Error.WHITELISTED);
        }

        uint256 borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);

        uint256 maxClose = (closeFactorMantissa * borrowBalance) / expScale;

        if (repayAmount > maxClose) {
            return uint256(Error.TOO_MUCH_REPAY);
        }
        return uint256(Error.NO_ERROR);
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 서비스 정책(값) 수정 기능 => Service Admin이 실행 가능
    //////////////////////////////////////////////////////////////////////////////////

    // 청산 할인율(인센티브) 설정
    /**
     * @notice Sets liquidationIncentive
     * @dev only service admin can set liquidation incentive
     * @param cTokens array of cTokens to modify
     * @param newLiquidationIncentiveMantissas array of New liquidationIncentive scaled by 1e18
     * @return 0=success, otherwise a failure. (See Error.sol for details)
     */
    function setLiquidationIncentive(CToken[] calldata cTokens, uint256[] calldata newLiquidationIncentiveMantissas)
        external
        returns (uint256)
    {
        require(isServiceAdmin[msg.sender] == true, "E1");
        require(cTokens.length == newLiquidationIncentiveMantissas.length, "E115");

        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            liquidationIncentiveMantissa[address(cTokens[i])] = newLiquidationIncentiveMantissas[i];
            emit NewLiquidationIncentive(cTokens[i], newLiquidationIncentiveMantissas[i]);
        }

        return uint256(Error.NO_ERROR);
    }

    // Borrow cap 설정
    /**
     * @notice Sets BorrowCap
     * @dev only service admin can set borrow caps
     * @param cTokens array of cTokens to modify
     * @param newBorrowCaps array of New borrowCap scaled by cToken's underlying decimals
     */
    function setMarketBorrowCaps(CToken[] calldata cTokens, uint256[] calldata newBorrowCaps) external {
        require(isServiceAdmin[msg.sender] == true, "E1");
        require(cTokens.length == newBorrowCaps.length, "E115");

        uint256 numMarkets = cTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "E84");

        for (uint256 i = 0; i < numMarkets; i++) {
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
        }
    }

    // Price oracle 주소 설정
    /**
     * @notice Sets price oracle
     * @dev only service admin can set PriceOracle
     * @param newOracle new PriceOracle contract address
     * @return 0=success, otherwise a failure. (See Error.sol for details)
     */
    function setPriceOracle(WemixfiLendingOracle newOracle) public returns (uint256) {
        require(isServiceAdmin[msg.sender] == true, "E1");
        require(address(newOracle) != address(0), "E117");
        priceOracle = newOracle;

        emit NewPriceOracle(newOracle);

        return uint256(Error.NO_ERROR);
    }

    // 무담보 대출이 가능한 주소 설정
    /**
     * @notice modify isUnsecuredBorrower mapping
     * @dev only service admin can set isUnsecuredBorrower
     * @param borrower target address to modify isUnsecuredBorrower state
     * @param newIsUnsecuredBorrower  boolean to indicate that the borrower is available of unsecured borrowing
     */
    function setIsUnsecuredBorrower(address borrower, bool newIsUnsecuredBorrower) external {
        require(msg.sender == masterAdmin, "E1");
        isUnsecuredBorrower[borrower] = newIsUnsecuredBorrower;
        emit NewIsUnsecuredBorrower(borrower, newIsUnsecuredBorrower);
    }

    // Close Factor 설정
    /**
     * @notice Sets close factor
     * @dev only service admin can set closeFactor
     * @param newCloseFactorMantissa new close factor, scaled by 1e18
     * @return 0=success, otherwise a failure. (See Error.sol for details)
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external returns (uint256) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    // Collateral Factor 설정
    /**
     * @notice Sets collateral factor
     * @dev only service admin can set collateralFactor
     * @param cToken address of market to set collateral factor
     * @param newCollateralFactorMantissa new collateral factor, scaled by 1e18
     * @return 0=success, otherwise a failure. (See Error.sol for details)
     */
    function setCollateralFactor(CToken cToken, uint256 newCollateralFactorMantissa) external returns (uint256) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        Market storage market = markets[address(cToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        if (collateralFactorMaxMantissa < newCollateralFactorMantissa) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        if (newCollateralFactorMantissa != 0 && priceOracle.getUnderlyingPrice(cToken.underlyingSymbol()) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        emit NewCollateralFactor(cToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint256(Error.NO_ERROR);
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 서비스 중단 기능 (예치, 대출, 청산 상환, 전송, 오라클) => Service Admin이 실행 가능
    //////////////////////////////////////////////////////////////////////////////////
    /**
     * @notice Admin functions to change the Pause Guardian
     * @param cTokens The array of market addresses to modify paused state
     * @param state true = action paused
     * @return state modified state of action paused ex)true
     */

    function setMintPaused(CToken[] calldata cTokens, bool state) external returns (bool) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            require(markets[address(cTokens[i])].isListed, "E86");
            isMintPaused[address(cTokens[i])] = state;

            emit ActionPaused(cTokens[i], "Mint", state);
        }

        return state;
    }

    function setBorrowPaused(CToken[] calldata cTokens, bool state) external returns (bool) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            require(markets[address(cTokens[i])].isListed, "E86");
            isBorrowPaused[address(cTokens[i])] = state;

            emit ActionPaused(cTokens[i], "Borrow", state);
        }

        return state;
    }

    function setSeizePaused(CToken[] calldata cTokens, bool state) external returns (bool) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            require(markets[address(cTokens[i])].isListed, "E86");
            isSeizePaused[address(cTokens[i])] = state;

            emit ActionPaused(cTokens[i], "Seize", state);
        }

        return state;
    }

    function setTransferPaused(CToken[] calldata cTokens, bool state) external returns (bool) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            require(markets[address(cTokens[i])].isListed, "E86");
            isTransferPaused[address(cTokens[i])] = state;

            emit ActionPaused(cTokens[i], "Transfer", state);
        }

        return state;
    }

    function setOraclePaused(CToken[] calldata cTokens, bool state) external returns (bool) {
        require(isServiceAdmin[msg.sender] == true, "E1");

        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            require(markets[address(cTokens[i])].isListed, "E86");
            isOraclePaused[address(cTokens[i])] = state;

            emit ActionPaused(cTokens[i], "Oracle", state);
        }

        return state;
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 거버넌스 토큰 관련 기능(Wemixfi에서는 현재 사용하지 않음)
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Accrue incentive token to the market by updating the supply index
     * @param cToken The market whose supply index to update
     * @dev Index is a cumulative sum of the incentive token per cToken accrued.
     */
    function updateIncentiveTokenSupplyIndex(address cToken) internal {
        IncentiveTokenMarketState storage supplyState = incentiveTokenSupplyState[cToken];

        uint256 supplySpeed = incentiveTokenSpeeds[cToken];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = blockNumber - supplyState.block;

        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = CToken(cToken).totalSupply();
            uint256 incentiveTokenAccrued = deltaBlocks * supplySpeed;

            uint256 ratio = supplyTokens > 0 ? (incentiveTokenAccrued * doubleScale) / supplyTokens : 0;

            supplyState.index = supplyState.index + ratio;
            supplyState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }

        emit UpdateIncentiveTokenSupplyIndex(CToken(cToken), supplyState.index, supplyState.block);
    }

    /**
     * @notice Accrue incentive token to the market by updating the borrow index
     * @param cToken The market whose borrow index to update
     * @dev Index is a cumulative sum of the incentive token per cToken accrued.
     */
    function updateIncentiveTokenBorrowIndex(address cToken, uint256 marketBorrowIndex) internal {
        IncentiveTokenMarketState storage borrowState = incentiveTokenBorrowState[cToken];

        uint256 borrowSpeed = incentiveTokenSpeeds[cToken];
        uint256 blockNumber = getBlockNumber();
        uint256 deltaBlocks = blockNumber - borrowState.block;

        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = (CToken(cToken).totalBorrows() * expScale) / marketBorrowIndex;
            uint256 incentiveTokenAccrued = deltaBlocks * borrowSpeed;

            uint256 ratio = borrowAmount > 0 ? (incentiveTokenAccrued * doubleScale) / borrowAmount : 0;

            borrowState.index = borrowState.index + ratio;
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }

        emit UpdateIncentiveTokenBorrowIndex(CToken(cToken), marketBorrowIndex, borrowState.index, borrowState.block);
    }

    /**
     * @notice Calculate incentive token accrued by a supplier and add it to supplier's incentiveTokenAccrued
     * @param cToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute incentive token to
     */
    function distributeSupplierIncentiveToken(address cToken, address supplier) internal {
        IncentiveTokenMarketState storage supplyState = incentiveTokenSupplyState[cToken];

        uint256 supplyIndex = supplyState.index;
        uint256 supplierIndex = incentiveTokenSupplierIndex[cToken][supplier];

        incentiveTokenSupplierIndex[cToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= incentiveTokenInitialIndex) {
            supplierIndex = incentiveTokenInitialIndex;
        }

        uint256 deltaIndex = supplyIndex - supplierIndex;

        uint256 supplierTokens = CToken(cToken).balanceOf(supplier);
        uint256 supplierDelta = (supplierTokens * deltaIndex) / doubleScale;

        uint256 supplierAccrued = incentiveTokenAccrued[supplier] + supplierDelta;
        incentiveTokenAccrued[supplier] = supplierAccrued;

        emit DistributeSupplierIncentiveToken(CToken(cToken), supplier, supplierDelta, supplyIndex);
    }

    /**
     * @notice Claim all the incentive token accrued by holder in all markets
     * @param holder The address to claim incentive token for
     */
    function claimIncentiveToken(address holder) public {
        return claimIncentiveToken(holder, allMarkets);
    }

    /**
     * @notice Claim all the incentive token accrued by holder in the specified markets
     * @param holder The address to claim incentive token for
     * @param cTokens The list of markets to claim incentive token in
     */
    function claimIncentiveToken(address holder, CToken[] memory cTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimIncentiveToken(holders, cTokens, true, true);
    }

    /**
     * @notice Claim all incentive token accrued by the holders
     * @param holders The addresses to claim incentive token for
     * @param cTokens The list of markets to claim incentive token in
     * @param borrowers Whether or not to claim incentive token earned by borrowing
     * @param suppliers Whether or not to claim incentive token earned by supplying
     */
    function claimIncentiveToken(
        address[] memory holders,
        CToken[] memory cTokens,
        bool borrowers,
        bool suppliers
    ) public {
        for (uint256 i = 0; i < cTokens.length; i++) {
            CToken cToken = cTokens[i];
            require(markets[address(cToken)].isListed, "E86");
            if (borrowers) {
                uint256 borrowIndex = cToken.borrowIndex();
                updateIncentiveTokenBorrowIndex(address(cToken), borrowIndex);
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeBorrowerIncentiveToken(address(cToken), holders[j], borrowIndex);
                    incentiveTokenAccrued[holders[j]] = grantIncentiveTokenInternal(
                        holders[j],
                        incentiveTokenAccrued[holders[j]]
                    );
                    emit ClaimIncentiveToken(holders[j], cToken, true, incentiveTokenAccrued[holders[j]]);
                }
            }
            if (suppliers) {
                updateIncentiveTokenSupplyIndex(address(cToken));
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeSupplierIncentiveToken(address(cToken), holders[j]);
                    incentiveTokenAccrued[holders[j]] = grantIncentiveTokenInternal(
                        holders[j],
                        incentiveTokenAccrued[holders[j]]
                    );
                    emit ClaimIncentiveToken(holders[j], cToken, false, incentiveTokenAccrued[holders[j]]);
                }
            }
        }
    }

    /**
     * @notice Calculate incentive token accrued by a borrower and add it to borrower's incentiveTokenAccrued
     * @param cToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute incentive token to
     * @param marketBorrowIndex  borrow index of the market (cToken)
     */
    function distributeBorrowerIncentiveToken(
        address cToken,
        address borrower,
        uint256 marketBorrowIndex
    ) internal {
        IncentiveTokenMarketState storage borrowState = incentiveTokenBorrowState[cToken];

        uint256 borrowIndex = borrowState.index;
        uint256 borrowerIndex = incentiveTokenBorrowerIndex[cToken][borrower];

        incentiveTokenBorrowerIndex[cToken][borrower] = borrowIndex;

        if (borrowerIndex > 0) {
            uint256 deltaIndex = borrowIndex - borrowerIndex;
            uint256 borrowerAmount = (CToken(cToken).borrowBalanceStored(borrower) * expScale) / marketBorrowIndex;

            uint256 borrowerDelta = (borrowerAmount * deltaIndex) / doubleScale;
            uint256 borrowerAccrued = incentiveTokenAccrued[borrower] + borrowerDelta;
            incentiveTokenAccrued[borrower] = borrowerAccrued;

            emit DistributeBorrowerIncentiveToken(CToken(cToken), borrower, borrowerDelta, borrowIndex);
        }
    }

    function grantIncentiveTokenInternal(address user, uint256 amount) internal returns (uint256) {
        IERC20 incentiveToken = IERC20(INCENTIVE_TOKEN_ADDRESS);
        uint256 incentiveTokenRemaining = incentiveToken.balanceOf(address(this));
        if (amount > 0 && amount <= incentiveTokenRemaining) {
            incentiveToken.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 거버넌스 토큰 관련 관리자 기능(Wemixfi에서는 현재 사용하지 않음)
    //////////////////////////////////////////////////////////////////////////////////
    /**
     * @notice Transfer incentive token to the recipient
     * @dev Note: If there is not enough incentiveToken, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer incentiveToken to
     * @param amount The amount of incentiveToken to (possibly) transfer
     */
    function grantIncentiveToken(address recipient, uint256 amount) public {
        require(isServiceAdmin[msg.sender] == true, "E1");
        uint256 amountLeft = grantIncentiveTokenInternal(recipient, amount);
        require(amountLeft == 0, "E96");

        emit GrantIncentiveToken(recipient, amount);
    }

    /**
     * @notice Set incentive token speed of markets
     * @dev only service admin can set incentive token speeds
     * @param cTokens array of markets to modify
     * @param incentiveTokenSpeeds array of incentiveTokenSpeeds
     * incentive token speed == amount of incentive tokens to distribute to the market per block
     */
    function setIncentiveTokenSpeed(CToken[] memory cTokens, uint256[] memory incentiveTokenSpeeds) public {
        require(isServiceAdmin[msg.sender] == true, "E1");
        uint256 len = cTokens.length;
        for (uint256 i = 0; i < len; i += 1) {
            setIncentiveTokenSpeedInternal(cTokens[i], incentiveTokenSpeeds[i]);
        }
    }

    function setIncentiveTokenSpeedInternal(CToken cToken, uint256 incentiveTokenSpeed) internal {
        uint256 currentIncentiveTokenSpeed = incentiveTokenSpeeds[address(cToken)];
        if (currentIncentiveTokenSpeed != 0) {
            uint256 borrowIndex = cToken.borrowIndex();
            updateIncentiveTokenSupplyIndex(address(cToken));
            updateIncentiveTokenBorrowIndex(address(cToken), borrowIndex);
        } else if (incentiveTokenSpeed != 0) {
            Market storage market = markets[address(cToken)];
            require(market.isListed, "E86");

            if (
                incentiveTokenSupplyState[address(cToken)].index == 0 &&
                incentiveTokenSupplyState[address(cToken)].block == 0
            ) {
                incentiveTokenSupplyState[address(cToken)] = IncentiveTokenMarketState({
                    index: incentiveTokenInitialIndex,
                    block: getBlockNumber()
                });
            }

            if (
                incentiveTokenBorrowState[address(cToken)].index == 0 &&
                incentiveTokenBorrowState[address(cToken)].block == 0
            ) {
                incentiveTokenBorrowState[address(cToken)] = IncentiveTokenMarketState({
                    index: incentiveTokenInitialIndex,
                    block: getBlockNumber()
                });
            }
        }

        if (currentIncentiveTokenSpeed != incentiveTokenSpeed) {
            incentiveTokenSpeeds[address(cToken)] = incentiveTokenSpeed;
            emit IncentiveTokenSpeedUpdated(cToken, incentiveTokenSpeed);
        }
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// Getter 함수
    //////////////////////////////////////////////////////////////////////////////////

    function getBlockNumber() public view returns (uint256) {
        return block.number;
    }

    /// @notice Return all of the markets
    /// @return The list of market addresses
    function getAllMarkets() external view returns (CToken[] memory) {
        return allMarkets;
    }

    /// @notice Return collateralFactor of the market
    /// @param asset underlying asset address of the market
    function getMarketCollateralFactor(address asset) external view returns (uint256) {
        return markets[asset].collateralFactorMantissa;
    }

    /// @notice Return list of markets which user entered
    /// @param account user address to get accountAssets
    function getAccountAssets(address account) external view returns (CToken[] memory) {
        return accountAssets[account];
    }

    /// @notice Return masterAdmin's address
    function getMasterAdmin() public view override returns (address) {
        return masterAdmin;
    }

    /// @notice Return whether the address is serviceAdmin or not
    function getIsServiceAdmin(address serviceAdmin) public view override returns (bool) {
        return isServiceAdmin[serviceAdmin];
    }
}