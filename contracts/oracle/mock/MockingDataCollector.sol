// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./IMockingDataCollector.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract MockingDataCollector is IMockingDataCollector, Initializable {
    using AddressUpgradeable for address payable;
    address public aggregator;
    int256 public price;

    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Sender is not a aggregator");
        _;
    }

    function initialize() external initializer {
        // __Ownable_init();
        aggregator = msg.sender;
    }

    //get the latest epoch answer
    function latestAnswer() external view returns (int256) {
        return price;
    }

    //add the latest epoch aggregated data
    function addData(int256 answer) external onlyAggregator {
        // stored dsata is in a block ago
        price = answer;
    }
}
