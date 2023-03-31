// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IDataCollector {
    struct DataForm {
        ///TODO change data form at future
        bytes data;
        uint256 createdAt;
        uint256 updatedAt;
        bytes32 hash;
    }

    struct AnswerDastaForm {
        uint256 epoch;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint256 answeredInEpoch;
    }

    //get the latest epoch data
    function latestEpochData() external view returns (AnswerDastaForm memory);

    //get the latest epoch answer
    function latestAnswer() external view returns (int256);

    //get a specific epoch data
    function getData(uint256 epoch) external view returns (AnswerDastaForm memory);

    //get the latest timestamp
    function latestTimestamp() external view returns (uint256);

    //get a speicific epoch timestamp
    function getCreatedTimestamp(uint256 epoch) external view returns (uint256);

    //get a speicific epoch timestamp
    function getUpdatedTimestamp(uint256 epoch) external view returns (uint256);

    //get the latest epoch number
    function latestEpoch() external view returns (uint256);

    //add the latest epoch aggregated data
    function addData(int256 answer) external;

    //add the speicific epoch aggregated data
    function addData(uint256 storedEpoch, int256 answer) external;

    //store data from feeder
    function storeData(bytes memory data) external;

    //get a speicific feeder and a specific epoch data
    function getFeederData(address feeder, uint256 epoch) external view returns (DataForm memory);

    //add feeder
    function addFeeder(address newFeeder) external;

    //set aggregator
    function setAggregator(address newAggregator) external;

    //set epoch period
    function setEpochPeriod(uint256 newEpochPeriod) external;

    //set aggregator public key
    function setAggregatorPublicKey(bytes memory publicKey) external;

    //set feeder public key
    function setFeederPublicKey(bytes memory publicKey) external;

    //get current epoch end timestamp
    function getTimeout() external view returns (uint256);
}
