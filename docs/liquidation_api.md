# Liquidation Open API
청산은 외부 참여자들에게 모두 오픈되어 있습니다. 아래 2단계를 통해 모두가 직접 청산에 참여할 수 있습니다. 본 문서에는 청산을 위한 사용자의 정보를 확인하는 openAPI를 제공하며, 대출 이력이 있는 사용자 정보를 가져오는 liquidation_users와 그 중 청산 대상자를 필터하는 liquidation_filtered_users를 제공합니다. openAPI를 통해 가져온 정보를 바탕으로 스마트 컨트랙트를 통해 조회하고 청산을 진행할 수 있습니다.

## liquidation_users
대출 이력이 있으며 부채가 남아있는 모든 사용자의 주소를 확인할 수 있습니다.
청산 대상자의 여부와 상관 없이 필터링 되지 않은 전체 리스트 입니다.

### Request URL
https://openapi.wemix.fi/lending/lendingLiquidation/liquidation_users



### Response
```typescript
{
type: "success",
message: "success",
data:
[
"0x09EC691f61eE39d95732a49183b31fFa1ED7E1e4",
"0x2ecfBEfFaBE93CA1458d3897f32fCa30E4151b1f",
"0x2fdBE7eA4f14022CfEd6Bf45b88bFC4eF16949Fd",
"0x36A1bD127100d2c43a6C6E37219f1E32D29591D5",
"0x41234176FB779a4487823EBADac514Dbe5E7f3c0",
"0x476Dd9810Fd9f8ba7E1e57e6D9916b862E633375",
"0x5aA72e699A718FEb5e1681965e37f59c40b8dC76",
"0x5d96bD8eE589CD08f403B687303F733000De21F3",
"0x5dAeEd9e0963047B2d0B0Df145A035137232CB30",
"0x688a44d0DB9aA9e7e19e65E7C0F6304B4EaED2A7",
"0x715c4bbd149c4f359C8355f56F83c6862962463D",
"0x75d6A9970A2eB7b029849A3ee6EB40787BAc13cB",
"0x81BB40ea8B60906598C4024ed11429977C3C2729",
"0x91486Fb83b6064Cf4eA587A2E4519ba0457fdF9f",
"0x9e108d4CF8ca1d20463e23AeC9413fFff5a6180a",
"0xA3859F96d4476c60B6e9ef94C130a545b5F08C9e",
"0xB6C726ceA47aC32f03593242937981096c6F5e1C",
"0xC350dBd716806c45ceB00Ca5b3f2CeEa5C51068c",
"0xCd7c5Dd6330A8E563B777473AbEdf78594F143D0",
"0xF6b142Ca41D0ee1C06e1563Eb318C677112a7B3d",
"0xFD35d296C2bEe14c4A2De0dc5Fe8dbd8429735c8",
"0xab26Cd5F0c458E3Cc66bfA254e0A73d79Cf8510D",
"0xd49A05cFdFb1056884FCF011d18B82ab3Ca6Ab11",
"0xdBFcba4d3CD1fD3B350FF7Ade72fc093B8e98E10",
"0xdedC2189FaE91049dd1fec9A02088E2335646299",
"0xe58A5782e7FCb39Eca107d7CBf32Be12DEdEB491",
"0xe79ff297CA183e10521E3c7836dFDa42588eed12",
"0xeC1180e29B39Ec37A70488c02f88EC22921C215E",
"0xfA4363Dcf1f277b2f42fa44090360a14C0ebB2dF"
]
}
```

- address : 대출을 하고 전체 상환을 하지 않은 주소를 모두 리턴합니다.
- 전체 상환을 하더라도 대출을 다시 할 경우 리스트에 다시 추가되게 됩니다.


## liquidation_filterd_users
청산 마켓에 참여한 유저들의 정보를 모두 가져옵니다. 유저가 참여한 마켓에 대한 정보를 모두 표시하여 청산 대상자 리스트를 각자 조건에 맞게 추려내는데 필요한 정보로 사용할 수 있습니다.


### Request URL 
https://openapi.wemix.fi/lending/lendingLiquidation/liquidation_filterd_users



### Response
```typescript
{
type: "success",
message: "success",
data:
[
{
address: "0x056a5C0Ae61bb4620435F17b2E0212E47DBd14fA",
liquidInfos:
[
{
token_name: "CWemixDollar",
price: "1",
collateralFactor: 0.85,
Mint_Redeem: "0",
Mint_Redeem_Collateral: "0",
Borrow_Repay: 0
}
]
},
{
address: "0x09EC691f61eE39d95732a49183b31fFa1ED7E1e4",
liquidInfos:
[
{
token_name: "CUSDC",
price: "0.99974989",
collateralFactor: 0.85,
Mint_Redeem: "2001.49927978",
Mint_Redeem_Collateral: "1701.274387813",
Borrow_Repay: 0
},
{
token_name: "CWemix",
price: "0.31351824",
collateralFactor: 0.75,
Mint_Redeem: "3182.2101360000006",
Mint_Redeem_Collateral: "2386.657602",
Borrow_Repay: "286.56731185037097"
},
{
token_name: "CWemixDollar",
price: "1",
collateralFactor: 0.85,
Mint_Redeem: "1000.0000000000001",
Mint_Redeem_Collateral: "850.0000000000001",
Borrow_Repay: "2753.8106224381786"
}
]
},
…
]
}
]
}
```

- data : 전체 참여자에 대한 주소와 각 주소에 대한 liquid_infos를 나타냅니다.
- address : 랜딩 마켓에 참여한 대상 지갑 주소를 의미합니다.
liquidInfos
- token_name : 해당 지갑 주소가 참여한 대출 토큰의 이름
- price : 해당 자산의 위믹스 달라 기준 현재 가격
- collateralFactor: 전체 예치한 자산 중 담보물로 인정되는 비율
- Mint_Redeem: 사용자의 전체 cToken예치량에서 인출한 값을 뺀 수치로 대략적인 담보량
- Mint_Redeem_Collateral: Mint_Redeem에서 collateralFactor를 곱한 실질적으로 인정되는 담보량
- Borrow_Repay: 대출을 한 총량에서 상환한 총량을 차감한 값
- Mint_Redeem, Mint_Redeem_Collateral, Borrow_Repay 에서 수치의 단위는 위믹스 달러 기준으로 환산한 해당 자산의 가치입니다. (100일시 100 위믹스 달러만큼의 가치를 의미)
- 위의 수치들은 컨트랙트의 이벤트를 바탕으로 계산한 값으로 이벤트에 기록되지 않는 cToken 자체의 이동이나 이자율은 반영되어 있지 않는 대략적인 수치만 나옵니다. 따라서 해당 API로는 대략적인 필터링을 진행한 후 청산 트랜잭션 실행 전 정확한 수치는 컨트랙트 호출로 확인하셔야 합니다. (컨트랙트 호출 글자에 메셔측 컨트랙트 제작 예시링크 걸면 될 것 같습니다.)
- 현재는 cToken을 예치하는 대신 따로 전송받는 경우 대출 가능한 담보물로 잡히지 않아 청산 대상에서는 제외하고 계산해야 합니다. 이에 따라 해당 api는 cToken 전송에 대한 예외 케이스에 대해서는 다루지 않습니다.
- Mint_Redeem에서 Borrow_Reapy를 나누게 되면 청산 위험도가 대략적으로 도출되게 됩니다. 이를 활용하여 원하는 조건으로 청산 대상자 주소들을 필터링을 할 수 있습니다.


## liquidationUsersFilterd
대출 이력과 부채를 가진 모든 사용자 중 Status Monitor 수치가 70%를 초과하는 경우를 보여줍니다.


### Request URL
https://openapi.wemix.fi/lending/lendingLiquidation/liquidation_users_filterd



### Response
```typescript
{
type: "success",
message: "success",
data:
[
"0x217EB4b15FEa2Ae5628a68D45e8F0e992FE9cF89",
"0x688a44d0DB9aA9e7e19e65E7C0F6304B4EaED2A7",
"0x70B54029bECE4ed85f5c7ac271C4c1cA4c3CC646",
"0x715c4bbd149c4f359C8355f56F83c6862962463D",
"0x75d6A9970A2eB7b029849A3ee6EB40787BAc13cB",
"0x81BB40ea8B60906598C4024ed11429977C3C2729",
"0x91486Fb83b6064Cf4eA587A2E4519ba0457fdF9f",
"0xA3859F96d4476c60B6e9ef94C130a545b5F08C9e",
"0xab26Cd5F0c458E3Cc66bfA254e0A73d79Cf8510D",
"0xBb5019E44A6710b96Bc39224FAc087cE6228F56F",
"0xC350dBd716806c45ceB00Ca5b3f2CeEa5C51068c",
"0xC8e3E583E3537B6363Fe3d7D3F42d7DAC01E7780",
"0xd49A05cFdFb1056884FCF011d18B82ab3Ca6Ab11",
"0xdBFcba4d3CD1fD3B350FF7Ade72fc093B8e98E10",
"0xe58A5782e7FCb39Eca107d7CBf32Be12DEdEB491",
"0xEFc5Fc50Cf5293ba1Eb29f2a4f2E6fA0A79C1260",
"0xfA4363Dcf1f277b2f42fa44090360a14C0ebB2dF"
]
}
```

- address : 대출을 하고 전체 상환을 하지 않은 주소를 모두 리턴합니다.
- liquidation_filtered_users를 활용하여 자체적으로 필터링을 한 내용입니다. 실제 청산은 위험도가 70%여도 일어나지 않으나 위험도가 매우 안전한 청산 대상자들을 필터링해 주어서 1차적으로 청산대상자 목록을 줄이는 작업에 활용이 가능합니다.
