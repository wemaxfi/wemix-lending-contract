// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IMockingDataCollector {
    //get the latest epoch answer
    function latestAnswer() external view returns (int256);

    //add the latest epoch aggregated data
    function addData(int256 answer) external;
}
