// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol

import "./ControllerInterface.sol";
import "./CTokenInterface.sol";
import "./InterestRateModel.sol";
import "./Error.sol";
import "./IERC20.sol";
import { TransactionHelper } from "./TransactionHelper.sol";

import "../common/ExponentialNoError.sol";

import "../views/ControllerView.sol";

abstract contract CToken is CTokenInterface {
    // modifier
    modifier nonReentrant() {
        require(_notEntered, "E67");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }

    modifier nonZero(uint256 input) {
        require(input != 0, "E122");
        _;
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// Initializer 및 컨트랙트 setter 함수
    //////////////////////////////////////////////////////////////////////////////////

    // Initializer
    /**
     * @notice Initialize the money market
     * @param controller_ The address of the Controller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ EIP-20 name of this token
     * @param symbol_ EIP-20 symbol of this token
     * @param underlyingSymbol_ bytes32, EIP-20 symbol of this token's underlying asset
     * @param decimals_ EIP-20 decimal precision of this token
     */
    function initializeCToken(
        ControllerInterface controller_,
        InterestRateModel interestRateModel_,
        ControllerView controllerView_,
        TransactionHelper transactionHelper_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        bytes32 underlyingSymbol_,
        uint8 decimals_,
        address underlying_
    ) internal {
        // require(msg.sender == ControllerInterface(controller_).getMasterAdmin(), "E1");
        require(accrualBlockNumber == 0 && borrowIndex == 0, "E2");
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        require(initialExchangeRateMantissa > 0, "E3");

        controller = controller_;
        controllerView = controllerView_;
        transactionHelper = transactionHelper_;

        accrualBlockNumber = block.number;
        borrowIndex = expScale;

        uint256 err = setInterestRateModelFresh(interestRateModel_);
        require(err == NO_ERROR, "E4");

        name = name_;
        symbol = symbol_;
        underlyingSymbol = underlyingSymbol_;
        decimals = decimals_;
        underlying = underlying_;

        _notEntered = true;
    }

    /// @notice set new Controller address
    function setController(ControllerInterface newController) external {
        require(msg.sender == getMasterAdmin(), "E1");
        require(address(newController) != address(0), "E117");
        controller = newController;

        emit NewController(newController);
    }

    /// @notice set new ControllerView address
    /// @dev ControllerView is used in calulation of seize tokens for liquidation
    function setControllerView(ControllerView controllerView_) external {
        require(msg.sender == getMasterAdmin(), "E1");
        require(address(controllerView_) != address(0), "E117");
        controllerView = controllerView_;
        emit NewControllerView(controllerView_);
    }

    /// @notice set new TransactionHelper address
    function setTransactionHelper(TransactionHelper transactionHelper_) external {
        require(msg.sender == getMasterAdmin(), "E1");
        require(address(transactionHelper_) != address(0), "E117");
        transactionHelper = transactionHelper_;
        emit NewTransactionHelper(transactionHelper_);
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// ERC-20, 토큰 전송 관련 함수 (ERC20 functions, transfer functions)
    //////////////////////////////////////////////////////////////////////////////////

    function balanceOf(address owner) external view override returns (uint256) {
        return accountBalances[owner];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        address sender = msg.sender;
        require(spender != address(0), "E116");

        transferAllowances[sender][spender] = amount;

        emit Approval(sender, spender, amount);

        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return transferAllowances[owner][spender];
    }

    function doTransferIn(address sender, uint256 amount) internal virtual returns (uint256);

    function doTransferOut(address payable recipient, uint256 amount) internal virtual returns (uint256);

    function transfer(address recipient, uint256 amount) external override nonReentrant returns (bool) {
        return transferTokens(msg.sender, msg.sender, recipient, amount) == NO_ERROR;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override nonReentrant returns (bool) {
        return transferTokens(msg.sender, sender, recipient, amount) == NO_ERROR;
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return 0 if the transfer succeeded, else revert
     */
    function transferTokens(
        address spender,
        address src,
        address dst,
        uint256 amount
    ) internal returns (uint256) {
        uint256 allowed = controller.transferAllowed(address(this), src, dst, amount);
        require(allowed == 0, "E6");
        require(src != dst, "E114");

        uint256 startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = transferAllowances[src][spender];
        }

        // src에서는 전송 수량 * 원금 / (원금 + 이자) 를 차감,
        // dst에서는 전송 수량을 더함
        {
            TransferLocalVars memory vars;

            vars.exchangeRateMantissa = exchangeRateStoredInternal();

            vars.underlyingAmount = (vars.exchangeRateMantissa * amount) / expScale;
            vars.currentBalanceOfUnderlying = (accountBalances[src] * vars.exchangeRateMantissa) / expScale;

            vars.transferGap = (vars.underlyingAmount * supplyPrincipal[src]) / vars.currentBalanceOfUnderlying;

            if (vars.transferGap > supplyPrincipal[src]) {
                // Truncation Error에 대한 예외처리
                supplyPrincipal[src] = 0;
            } else {
                supplyPrincipal[src] = supplyPrincipal[src] - vars.transferGap;
            }

            supplyPrincipal[dst] = supplyPrincipal[dst] + vars.underlyingAmount;
        }

        uint256 allowanceNew = startingAllowance - amount;
        uint256 srcTokensNew = accountBalances[src] - amount;
        uint256 dstTokensNew = accountBalances[dst] + amount;

        accountBalances[src] = srcTokensNew;
        accountBalances[dst] = dstTokensNew;

        if (startingAllowance != type(uint256).max) {
            transferAllowances[src][spender] = allowanceNew;
        }

        emit Transfer(src, dst, amount);

        return NO_ERROR;
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 유저 액션 실행 관련 함수 => 예치, 출금, 대출, 상환, 청산
    //////////////////////////////////////////////////////////////////////////////////

    // 예치
    /**
     * @notice User supplies assets into the market and receives cTokens in exchange
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     */
    function mintFresh(address minter, uint256 mintAmount) internal nonReentrant nonZero(mintAmount) returns (uint256) {
        accrueInterest();

        uint256 allowed = controller.mintAllowed(address(this), minter);

        require(allowed == 0, "E10");
        require(accrualBlockNumber == block.number, "E18");

        MintLocalVars memory vars;

        vars.exchangeRateMantissa = exchangeRateStoredInternal();
        vars.actualMintAmount = doTransferIn(minter, mintAmount);

        vars.mintTokens = (vars.actualMintAmount * expScale) / vars.exchangeRateMantissa;

        supplyPrincipal[minter] = supplyPrincipal[minter] + vars.actualMintAmount;

        totalSupply = totalSupply + vars.mintTokens;

        accountBalances[minter] = accountBalances[minter] + vars.mintTokens;

        emit Mint(minter, vars.actualMintAmount, vars.mintTokens, underlying);
        emit Transfer(address(this), minter, vars.mintTokens);

        return vars.actualMintAmount;
    }

    // 출금
    /**
     * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
     * @param redeemUnderlyingAmount The amount of underlying to receive from redeeming cTokens
     */
    function redeemUnderlying(uint256 redeemUnderlyingAmount) external {
        accrueInterest();

        require(accrualBlockNumber == block.number, "E33");

        uint256 borrowBalance = borrowBalanceStoredInternal(msg.sender);
        uint256 exchangeRateMantissa = exchangeRateStoredInternal();
        uint256 currentBalanceOfUnderlying = (accountBalances[msg.sender] * exchangeRateMantissa) / expScale;

        if (borrowBalance == 0 && redeemUnderlyingAmount == currentBalanceOfUnderlying) {
            uint256 exited = controller.exitMarket(msg.sender);
            require(exited == NO_ERROR, "E73");
        }
        return redeemFresh(payable(msg.sender), redeemUnderlyingAmount);
    }

    /**
     * @notice Sender redeems all cTokens the sender has in exchange for a underlying asset
     */
    function redeemUnderlyingMax() external {
        accrueInterest();
        require(accrualBlockNumber == block.number, "E33");
        uint256 result = borrowBalanceStoredInternal(msg.sender);
        if (result == 0) {
            uint256 exited = controller.exitMarket(msg.sender);
            require(exited == NO_ERROR, "E73");
        }
        return redeemFresh(payable(msg.sender), type(uint256).max);
    }

    struct RedeemLocalVars {
        uint256 exchangeRateMantissa;
        uint256 allowed;
        uint256 redeemTokens;
        uint256 redeemAmount;
        uint256 totalSupplyNew;
        uint256 accountBalancesNew;
        uint256 supplyPrincipalNew;
        uint256 incomeUnderlying;
        uint256 redeemGap;
        uint256 balanceOfUnderlying;
        uint256 actualRedeemAmount;
    }

    /**
     * @notice User redeems cTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current block
     * @param redeemer The address of the account which is redeeming the tokens
     * @param redeemUnderlyingIn The number of underlying tokens to receive from redeeming cTokens(redeem all if this value is type(uint256).max)
     */
    function redeemFresh(address payable redeemer, uint256 redeemUnderlyingIn)
        internal
        nonReentrant
        nonZero(redeemUnderlyingIn)
    {
        require(redeemUnderlyingIn != 0, "E34");

        RedeemLocalVars memory vars;

        vars.exchangeRateMantissa = exchangeRateStoredInternal();

        uint256 currentBalanceOfUnderlying = (accountBalances[redeemer] * vars.exchangeRateMantissa) / expScale;

        /* If redeemUnderlyingIn == -1, redeemAmount = balanceOfUnderlying */
        if (redeemUnderlyingIn == type(uint256).max) {
            vars.redeemAmount = currentBalanceOfUnderlying;
            vars.redeemTokens = accountBalances[redeemer];
        } else {
            vars.redeemAmount = redeemUnderlyingIn;
            vars.redeemTokens = (redeemUnderlyingIn * expScale) / vars.exchangeRateMantissa;
        }

        // unsecuredLoanBorrower에 등록된 주소가 예치 자산 이상 redeem 불가능하도록 체크
        require(vars.redeemAmount <= currentBalanceOfUnderlying, "E121");
        vars.redeemGap = (vars.redeemAmount * supplyPrincipal[redeemer]) / currentBalanceOfUnderlying;

        if (vars.redeemGap > supplyPrincipal[redeemer]) {
            // Truncation Error에 대한 예외처리
            supplyPrincipal[redeemer] = 0;
        } else {
            supplyPrincipal[redeemer] = supplyPrincipal[redeemer] - vars.redeemGap;
        }

        vars.allowed = controller.redeemAllowed(address(this), redeemer, vars.redeemTokens);
        require(vars.allowed == 0, "E40");

        vars.totalSupplyNew = totalSupply - vars.redeemTokens;
        vars.accountBalancesNew = accountBalances[redeemer] - vars.redeemTokens;

        require(getCashPrior() >= vars.redeemAmount, "E43");

        vars.actualRedeemAmount = doTransferOut(redeemer, vars.redeemAmount);
        emit Transfer(redeemer, address(this), vars.redeemTokens);

        totalSupply = vars.totalSupplyNew;
        accountBalances[redeemer] = vars.accountBalancesNew;
        emit Redeem(redeemer, vars.actualRedeemAmount, underlying);

        controller.redeemVerify(vars.actualRedeemAmount, vars.redeemTokens);
    }

    // 대출
    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrow(uint256 borrowAmount) external {
        borrowInternal(borrowAmount);
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowInternal(uint256 borrowAmount) internal nonReentrant {
        accrueInterest();
        return borrowFresh(payable(msg.sender), borrowAmount);
    }

    /**
     * @notice Users borrow assets from the protocol by TransactionHelper
     * @param caller The address of the borrower
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowHelper(address caller, uint256 borrowAmount) external nonReentrant {
        require(msg.sender == address(transactionHelper), "CTokenError: ACCESS_DENIED");
        accrueInterest();
        return borrowFresh(payable(caller), borrowAmount);
    }

    struct BorrowLocalVars {
        uint256 accountBorrows;
        uint256 accountBorrowsNew;
        uint256 totalBorrowsNew;
        uint256 actualBorrowAmount;
        uint256 borrowPrincipalNew;
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrower account that is borrowing underlying asset
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowFresh(address payable borrower, uint256 borrowAmount) internal nonZero(borrowAmount) {
        uint256 allowed = controller.borrowAllowed(address(this), borrower, borrowAmount);
        require(allowed == 0, "E21");

        require(accrualBlockNumber == block.number, "E22");
        require(getCashPrior() >= borrowAmount, "E23");

        BorrowLocalVars memory vars;

        vars.accountBorrows = borrowBalanceStoredInternal(borrower);

        vars.accountBorrowsNew = vars.accountBorrows + borrowAmount;

        vars.totalBorrowsNew = totalBorrows + borrowAmount;

        vars.actualBorrowAmount = doTransferOut(borrower, borrowAmount);

        vars.borrowPrincipalNew;

        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;

        vars.borrowPrincipalNew = borrowPrincipal[borrower] + vars.actualBorrowAmount;
        borrowPrincipal[borrower] = vars.borrowPrincipalNew;

        emit Borrow(borrower, vars.actualBorrowAmount, underlying);
    }

    // 상환
    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrowInternal(uint256 repayAmount) internal nonReentrant {
        repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @notice Sender repays their own borrow by TransactionHelper contract
     * @param caller The account of the caller
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrowHelperInternal(address caller, uint256 repayAmount) internal nonReentrant {
        repayBorrowFresh(caller, caller, repayAmount);
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     */
    function repayBorrowBehalfInternal(address borrower, uint256 repayAmount) internal nonReentrant {
        accrueInterest();
        repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    struct RepayBorrowLocalVars {
        uint256 repayAmount;
        uint256 borrowerIndex;
        uint256 accountBorrows;
        uint256 accountBorrowsNew;
        uint256 actualRepayAmount;
        uint256 borrowPrincipalGap;
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of underlying tokens being returned, or type(uint256).max for the full outstanding amount
     * @return (uint) the actual repayment amount.
     */
    function repayBorrowFresh(
        address payer,
        address borrower,
        uint256 repayAmount
    ) internal nonZero(repayAmount) returns (uint256) {
        uint256 allowed = controller.repayBorrowAllowed(address(this), borrower);

        require(accrualBlockNumber == block.number, "E28");
        require(allowed == 0, "E29");

        RepayBorrowLocalVars memory vars;

        vars.borrowerIndex = accountBorrows[borrower].interestIndex;

        vars.accountBorrows = borrowBalanceStoredInternal(borrower);

        // CErc20에 한정
        if (repayAmount == type(uint256).max) {
            vars.repayAmount = vars.accountBorrows;
        } else {
            vars.repayAmount = repayAmount;
        }

        vars.actualRepayAmount = doTransferIn(payer, vars.repayAmount);

        // must be accountBorrows > actualRepayAmount
        vars.borrowPrincipalGap = (vars.actualRepayAmount * borrowPrincipal[borrower]) / vars.accountBorrows;

        if (vars.borrowPrincipalGap > borrowPrincipal[borrower]) {
            // Truncation Error에 대한 예외처리
            borrowPrincipal[borrower] = 0;
        } else {
            borrowPrincipal[borrower] = borrowPrincipal[borrower] - vars.borrowPrincipalGap;
        }

        vars.accountBorrowsNew = vars.accountBorrows - vars.actualRepayAmount;

        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrows - vars.actualRepayAmount;

        if (vars.accountBorrowsNew == 0) {
            if (accountBalances[borrower] == 0) {
                uint256 exited = controller.exitMarket(borrower);
                require(exited == NO_ERROR, "E73");
            }
        }

        emit RepayBorrow(payer, borrower, vars.actualRepayAmount, vars.accountBorrowsNew, totalBorrows, underlying);

        return vars.actualRepayAmount;
    }

    // 청산
    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrowInternal(
        address borrower,
        uint256 repayAmount,
        CTokenInterface cTokenCollateral
    ) internal nonReentrant {
        accrueInterest();
        uint256 error = cTokenCollateral.accrueInterest();
        require(error == NO_ERROR, "E5");

        liquidateBorrowFresh(msg.sender, borrower, repayAmount, cTokenCollateral);
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        CTokenInterface cTokenCollateral
    ) internal {
        uint256 allowed = controller.liquidateBorrowAllowed(
            address(this),
            address(cTokenCollateral),
            borrower,
            liquidator,
            repayAmount
        );

        require(allowed == 0, "E49");
        require(accrualBlockNumber == block.number, "E7");
        require(cTokenCollateral.accrualBlockNumber() == block.number, "E7");
        require(borrower != liquidator, "E50");
        require(repayAmount != 0, "E51");
        require(repayAmount != type(uint256).max, "E52");

        uint256 actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

        (uint256 amountSeizeError, uint256 seizeTokens) = controllerView.liquidateCalculateSeizeTokens(
            address(this),
            address(cTokenCollateral),
            actualRepayAmount
        );
        require(amountSeizeError == NO_ERROR, "E54");
        require(cTokenCollateral.balanceOf(borrower) >= seizeTokens, "E55");

        {
            uint256 seizeError;

            if (address(cTokenCollateral) == address(this)) {
                seizeError = seizeInternal(address(this), liquidator, borrower, seizeTokens);
            } else {
                seizeError = cTokenCollateral.seize(liquidator, borrower, seizeTokens);
            }
            require(seizeError == NO_ERROR, "E56");
        }

        emit LiquidateBorrow(
            liquidator,
            borrower,
            actualRepayAmount,
            address(cTokenCollateral),
            seizeTokens,
            cTokenCollateral.underlying()
        );
    }

    // 청산 상환
    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of cTokens to seize
     * @return uint 0=success, otherwise a failure (see Error.sol for details)
     */
    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override nonReentrant returns (uint256) {
        return seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    struct SeizeLocalVars {
        uint256 borrowerBalanceOfUnderlying;
        uint256 borrowerIncomeUnderlying;
        uint256 borrowerReduce;
        uint256 liquidatorIncrease;
        uint256 seizeGap;
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed cToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of cTokens to seize
     */
    function seizeInternal(
        address seizerToken,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) internal returns (uint256) {
        uint256 allowed = controller.seizeAllowed(address(this), seizerToken, liquidator, borrower);
        require(allowed == 0, "E57");

        require(borrower != liquidator, "E50");

        uint256 protocolSeizeTokens = (seizeTokens * protocolSeizeShareMantissa) / expScale;
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;
        uint256 exchangeRateMantissa = exchangeRateStoredInternal();

        uint256 protocolSeizeAmount = (exchangeRateMantissa * protocolSeizeTokens) / expScale;

        totalReserves = totalReserves + protocolSeizeAmount;

        totalSupply = totalSupply - protocolSeizeTokens;

        // 원금+이자 고려하여 원금수량 조정
        {
            SeizeLocalVars memory vars;

            vars.borrowerBalanceOfUnderlying = (accountBalances[borrower] * exchangeRateMantissa) / expScale;
            vars.borrowerReduce = (exchangeRateMantissa * seizeTokens) / expScale;

            // check borrwerBalanceOfUnderlying > borrowerReduce, in line 561
            vars.seizeGap = (vars.borrowerReduce * supplyPrincipal[borrower]) / vars.borrowerBalanceOfUnderlying;

            if (vars.seizeGap > supplyPrincipal[borrower]) {
                // Truncation Error에 대한 예외처리
                supplyPrincipal[borrower] = 0;
            } else {
                supplyPrincipal[borrower] = supplyPrincipal[borrower] - vars.seizeGap;
            }

            vars.liquidatorIncrease = (exchangeRateMantissa * liquidatorSeizeTokens) / expScale;
            supplyPrincipal[liquidator] = supplyPrincipal[liquidator] + vars.liquidatorIncrease;
        }

        // 실제 cToken 수량 조정
        accountBalances[borrower] = accountBalances[borrower] - seizeTokens;
        accountBalances[liquidator] = accountBalances[liquidator] + liquidatorSeizeTokens;

        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(address(this), protocolSeizeAmount, totalReserves);

        return NO_ERROR;
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 프로토콜 및 유저 상태값 확인 관련 함수
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function exchangeRateStoredInternal() internal view returns (uint256) {
        uint256 _totalSupply = totalSupply;

        if (_totalSupply == 0) {
            return initialExchangeRateMantissa;
        } else {
            uint256 totalCash = getCashPrior();
            uint256 cashPlusBorrowsMinusReserves = totalCash + totalBorrows - totalReserves;
            uint256 exchangeRate = (cashPlusBorrowsMinusReserves * expScale) / _totalSupply;

            return exchangeRate;
        }
    }

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by controller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 cTokenBalance = accountBalances[account];

        uint256 borrowBalance = borrowBalanceStoredInternal(account);
        uint256 exchangeRateMantissa = exchangeRateStoredInternal();

        return (uint256(TokenErrorReporter.Error.NO_ERROR), cTokenBalance, borrowBalance, exchangeRateMantissa);
    }

    /**
     * @notice Get cash balance of this cToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view returns (uint256) {
        return getCashPrior();
    }

    function getCashPrior() internal view virtual returns (uint256);

    /**
     * @notice Get supply interest rate of this cToken
     * @return Current supply interest rate per block scaled by 1e18
     */
    function supplyRatePerBlock() external view returns (uint256) {
        return interestRateModel.getSupplyRate(getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa);
    }

    /**
     * @notice Get borrow interest rate of this cToken
     * @return Current borrow interest rate per block scaled by 1e18
     */
    function borrowRatePerBlock() public view returns (uint256) {
        return interestRateModel.getBorrowRate(getCashPrior(), totalBorrows, totalReserves);
    }

    /// @return Stored exchangeRate scaled by 1e18
    function exchangeRateStored() public view returns (uint256) {
        uint256 result = exchangeRateStoredInternal();
        return result;
    }

    function getBlockDelta() public view returns (uint256) {
        uint256 currentBlockNumber = block.number;
        uint256 accrualBlockNumberPrior = accrualBlockNumber;

        return currentBlockNumber - accrualBlockNumberPrior;
    }

    function getSimpleInterestFactorCurrent() public view returns (uint256) {
        uint256 blockDelta = getBlockDelta();
        uint256 borrowRateMantissa = borrowRatePerBlock();
        return borrowRateMantissa * blockDelta;
    }

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() public view returns (uint256) {
        uint256 simpleInterestFactor = getSimpleInterestFactorCurrent();

        uint256 interestAccumulated = (simpleInterestFactor * totalBorrows) / expScale;

        uint256 totalBorrowsNew = interestAccumulated + totalBorrows;
        uint256 totalReservesNew = ((reserveFactorMantissa * interestAccumulated) / expScale) + totalReserves;

        if (totalSupply == 0) {
            return initialExchangeRateMantissa;
        } else {
            uint256 totalCash = getCashPrior();
            uint256 cashPlusBorrowsMinusReserves = totalCash + totalBorrowsNew - totalReservesNew;
            return (cashPlusBorrowsMinusReserves * expScale) / totalSupply;
        }
    }

    /**
     * @notice Return up-to-date borrow balance by hypothetically accruing interest
     * @param account The address whose balance should be calculated with up-to-date borrowIndex without updating the index
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address account) public view returns (uint256) {
        uint256 simpleInterestFactor = getSimpleInterestFactorCurrent();

        uint256 borrowIndexNew = ((simpleInterestFactor * borrowIndex) / expScale) + borrowIndex;

        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        return (borrowSnapshot.principal * borrowIndexNew) / borrowSnapshot.interestIndex;
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address account) public view returns (uint256) {
        uint256 result = borrowBalanceStoredInternal(account);
        return result;
    }

    function borrowBalanceStoredInternal(address account) internal view returns (uint256) {
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        uint256 principalTimesIndex = borrowSnapshot.principal * borrowIndex;

        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    /// @notice Return the balance of underlying asset based on up-to-date exchange rate
    /// @param owner account to calculate current balance of underlying asset
    function balanceOfUnderlying(address owner) external view returns (uint256) {
        uint256 exchangeRate = exchangeRateCurrent();
        uint256 balance = (exchangeRate * accountBalances[owner]) / expScale;
        return balance;
    }

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public override returns (uint256) {
        uint256 currentBlockNumber = block.number;
        uint256 accrualBlockNumberPrior = accrualBlockNumber;

        if (accrualBlockNumberPrior == currentBlockNumber) return NO_ERROR;

        uint256 cashPrior = getCashPrior();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        uint256 borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
        require(borrowRateMantissa <= borrowRateMaxMantissa, "E60");

        uint256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

        uint256 simpleInterestFactor = borrowRateMantissa * blockDelta;
        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) / expScale;
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;

        uint256 totalReservesNew = ((reserveFactorMantissa * interestAccumulated) / expScale) + reservesPrior;
        uint256 borrowIndexNew = ((simpleInterestFactor * borrowIndexPrior) / expScale) + borrowIndexPrior;

        accrualBlockNumber = currentBlockNumber;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        emit AccrueInterest(accrualBlockNumber, interestAccumulated, borrowIndex, totalBorrows, totalReserves);
        return NO_ERROR;
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// 서비스 정책(값) 수정 기능 => Service Admin이 실행 가능
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev only service admin can set protocolSeizeShareMantissa
     * @param newProtocolSeizeShareMantissa new value to set as protocolSeizeShareMantissa
     */
    function setProtocolSeizeShareMantissa(uint256 newProtocolSeizeShareMantissa) external {
        require(getIsServiceAdmin(msg.sender), "E1");
        emit NewProtocolSeizeShare(protocolSeizeShareMantissa, newProtocolSeizeShareMantissa);
        protocolSeizeShareMantissa = newProtocolSeizeShareMantissa;
    }

    /**
     * @dev only service admin can set reserveFactorcMantissa
     * @param newReserveFactorMantissa new value to set as reserveFactorMantissa
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external nonReentrant returns (uint256) {
        accrueInterest();
        // setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        return setReserveFactorFresh(newReserveFactorMantissa);
    }

    function setReserveFactorFresh(uint256 newReserveFactorMantissa) internal returns (uint256) {
        require(getIsServiceAdmin(msg.sender) == true, "E1");
        require(accrualBlockNumber == block.number, "E7");
        require(newReserveFactorMantissa <= reserveFactorMaxMantissa, "E44");

        uint256 oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);

        return NO_ERROR;
    }

    /**
     * @dev only service admin can set interestRateModel
     * @param newInterestRateModel new contract address to set as interestRateModel
     */
    function setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint256) {
        require(getIsServiceAdmin(msg.sender) == true, "E1");
        accrueInterest();
        return setInterestRateModelFresh(newInterestRateModel);
    }

    function setInterestRateModelFresh(InterestRateModel newInterestRateModel) internal returns (uint256) {
        InterestRateModel oldInterestRateModel;

        require(accrualBlockNumber == block.number, "E7");

        oldInterestRateModel = interestRateModel;

        require(newInterestRateModel.isInterestRateModel(), "E45");

        interestRateModel = newInterestRateModel;

        emit NewInterestRateModel(newInterestRateModel);

        return NO_ERROR;
    }

    function addReservesInternal(uint256 addAmount) internal nonReentrant returns (uint256) {
        accrueInterest();
        addReservesFresh(addAmount);
        return NO_ERROR;
    }

    function addReservesFresh(uint256 addAmount) internal returns (uint256) {
        uint256 totalReservesNew;
        uint256 actualAddAmount;

        require(accrualBlockNumber == block.number, "E7");

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        totalReservesNew = totalReserves + actualAddAmount;

        require(totalReservesNew >= totalReserves, "E46");

        totalReserves = totalReservesNew;

        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);

        return actualAddAmount;
    }

    /**
     * @notice reduce specific amount of underlying asset from totalReserves
     * @dev only masterAdmin can reduceReserves
     * @param reduceAmount underlyingAsset amount to reduce from totalReserves
     */
    function reduceReserves(uint256 reduceAmount) external {
        accrueInterest();
        return reduceReservesFresh(reduceAmount);
    }

    function reduceReservesFresh(uint256 reduceAmount) internal {
        uint256 totalReservesNew;

        require(getMasterAdmin() == msg.sender, "E1");
        require(accrualBlockNumber == block.number, "E7");

        require(getCashPrior() >= reduceAmount, "E21");
        require(reduceAmount <= totalReserves, "E47");

        totalReservesNew = totalReserves - reduceAmount;
        require(totalReservesNew <= totalReserves, "E48");

        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        uint256 actualReduceAmount = doTransferOut(payable(msg.sender), reduceAmount);

        emit ReservesReduced(msg.sender, actualReduceAmount, totalReservesNew);
    }

    //////////////////////////////////////////////////////////////////////////////////
    /// Getter 함수
    //////////////////////////////////////////////////////////////////////////////////

    /// @dev CToken uses master admin of the controller contract
    function getMasterAdmin() public view returns (address) {
        return controller.getMasterAdmin();
    }

    /// @dev CToken uses the list of service admin of the controller contract
    function getIsServiceAdmin(address serviceAdmin) public view returns (bool) {
        return controller.getIsServiceAdmin(serviceAdmin);
    }
}
