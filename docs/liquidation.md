# Wemixfi Lend & Borrow 청산 가이드

WemixfiLendingView.sol 의 두 함수를 통해 쉽게 컨트랙을 통한 청산을 할 수 있습니다.

```solidity
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
```

## getLiquidationInfo

```solidity
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
```

- 해당 account 가 청산 대상자인지 여부 (`isLiquidateTarget`) 과 모든 listing 된 market의 청산 관련 정보를 반환합니다.
- 토큰 청산 관련 정보 (`TokenInfo` ) 는 아래와 같습니다.
    - `underlyingTokenAddr`: 해당 마켓의 자산 ex)WEMIX$ 의 주소 / WEMIX의 경우 ZERO_ADDRESS
    - `cTokenAddr`: 해당 마켓의 cToken 주소 ex) cWEMIX$의 주소
    - `isCollateralAsset`: 해당 마켓에 account가 예치한 담보가 있는지 여부 
    - `isBorrowAsset`: 해당 마켓에서 account가 대출한 수량이 있는지 여부
    - `price`: 해당 마켓 자산의 오라클 가격 (1e18 scaled)
    - `repayAmountMax`: 청산대상자일 경우, 해당 마켓의 대출을 한번에 청산할 수 있는 수량 (closeFactor가 반영된 값). scale은 자산의 decimal입니다.
    - `collateralUnderlyingTokenAmount`: 청산대상자일 경우, 해당 마켓에 담보로 예치된 총 수량. scaled은 자산의 decimal. 이 값과 `totalSeizeAmount` 를 비교하면 실제 청산시에 가져갈 담보가 충분한지 계산해 볼 수 있습니다.

- 청산하려는 사용자는 해당 함수를 호출해 봄으로써 청산 대상자를 걸러내고, 어떤 토큰 대출을 얼마나 한번에 대신 상환하고 어떤 토큰 담보를 가져갈지 파악할 수 있습니다.

## calculateLiquidatorSeizeAmount

- 대출자산, 담보자산, 대신 상환하는 대출자산 수량을 입력하면 ⇒ (청산자가 가져갈 담보자산 수량, 프로토콜이 가져가는 수량 포함한 전체 가져갈 담보자산 수량 )을 계산하여 반환합니다.
- 반환값 중 `liquidatorSeizeAmount`을 통해 `repayAmountMax` * `repay 자산 price` 와 `liquidatorSeizeAmount` * `seize 자산 price` 를 비교하여 청산시 수익을 계산할 수 있습니다.
- 반환값 중 `totalSeizeAmount` 를 통해 `collateralUnderlyingTokenAmount` 와 비교하여 repay할때 가져갈 담보가 충분한지 계산 할 수 있습니다.

# Example

- 예를 들어, account가 청산 대상자일 때,
    - WEMIX의 `isBorrowAsset` = true이고 repayAmountMax = 100 WEMIX 이면, 100 WEMIX를 한번에 대신 상환하여 청산할 수 있습니다.
    - 이 때 가져갈 담보자산은 `isCollateralAsset=true` 인 자산 중 선택할 수 있습니다. `collateralUnderlyingAmount` 를 통해 청산대상자가 예치한 담보의 총 수량을 알 수 있습니다.
    - 청산시에 청산자가 받는 담보자산 수량은 별도의 함수인 `calculateLiquidatorSeizeAmount`를 호출하여 알 수 있습니다.
    - `calculateLiquidatorSeizeAmount` 를 아래와 같이 호출하면 WEMIX를 repay했을때 청산자가 받을 수 있는 WEMIX$ 수량을 확인할 수 있습니다.
    
    ```tsx
    const cTokenBorrowed = WEMIX.address
    const cTokenCollateral = WEMIX$.address
    const actualRepayAmount = `getLiquidationInfo` 에서 읽어온 WEMIX의 repayAmountMax 값
    
    const [liquidatorSeizeAmount, totalSeizeAmount] = await WemixfiLendingView.calculateLiquidatorSeizeAmount(cTokenBorrowed, cTokenCollateral, actualRepayAmount);
    ```