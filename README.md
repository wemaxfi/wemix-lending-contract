# Wemix-Lending-Contract
This repository contains the smart contracts for the [wemax.fi](https://wemax.fi/lending) Lend & Borrow protocol.

## Liquidation Guide
- for guide to interact with contracts for liquidation, see [`docs/liquidation.md`](docs/liquidation.md)
- for guide to interact with open API for liquidation, see [`docs/liquidation_api.md`](docs/liquidation_api.md)

---

## Oracle Guide

The below scripts are designed to fetch price data from an Oracle API, update the Oracle with the new prices, and perform additional actions via a multicall to a cToken contract.

### 1. Fetching and Updating Prices from the Oracle

1. Fetch raw data from the Oracle API.
2. Prepare the data and signatures for setting the price.
3. Set the price using the Oracle contract.
4. Retrieve and log the newly set price.

```javascript
async function getData() {
    const uri = `https://api.wemax.fi/v1/oracle_sig`;
    const response = await fetch(uri);
    const data = await response.json();
    return data;
}

const rawDatas = await getData();
const oracleParams = [];

for (let rawData of rawDatas) {
    const symbol = '0x' + rawData.hash;
    const data = {
        timestamp: rawData.ts,
        deadline: rawData.ts_deadline,
        price: rawData.price
    };
    const signature = '0x' + rawData.sig;

    oracleParams.push({hash: symbol, data, signature});

    const txSet = await oracle.setUnderlyingPrice(symbol, data, signature);
    await txSet.wait();
    console.log(`Price set successfully: ${txSet.hash}`);

    const priceResult = await oracle.getUnderlyingPrice(symbol);
    console.log(`Retrieved price: ${priceResult}`);
}
```

### 2. Performing Multicall for Oracle Update and Other Actions at once

The below script allows you to update multiple Oracle prices and perform additional actions on a `cToken` contract within a single transaction using multicall.

1. Encode each Oracle price update call.
2. Encode the desired action at `cToken` contract (specified by `METHOD` and `ARGS`).
3. Aggregate the encoded calls into a multicall transaction.
4. Send the transaction and wait for confirmation.

```javascript
let calls = [];
for (let oracleParam of oracleParams) {
    const priceUpdateCall = cToken.interface.encodeFunctionData(
        "addData",
        [oracleParam.hash, oracleParam.data, oracleParam.signature]
    );
    calls.push(priceUpdateCall);
}

const functionCall = cToken.interface.encodeFunctionData(
    METHOD,  // Ensure METHOD and ARGS are correctly defined in your context
    ARGS
);
calls.push(functionCall);

const tx = await cToken.multicall(calls);
await tx.wait();
console.log("Transaction hash:", tx.hash);
```
