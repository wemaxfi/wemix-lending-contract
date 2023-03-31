// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./IDataCollector.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract DataCollector is IDataCollector, OwnableUpgradeable {
    using AddressUpgradeable for address payable;

    mapping(uint256 => mapping(address => DataForm)) /* epoch */ /* feeder */
        public feederData;

    mapping(uint256 => AnswerDastaForm) /* epoch */
        public aggregatedData;

    uint256 public feederLength;

    address[] public feeders;
    mapping(address => bool) /* feeder */ /* check */
        public isFeeder;

    address public aggregator;

    uint256 public lastUpdatedTime;
    uint256 public lastUpdatedEpoch;
    mapping(address => uint256) /* feeder */ /* epoch */
        public feederLastUpdatedEpoch;

    // epoch = block.timestamp / epochPeriod
    uint256 public epochPeriod;

    bytes public aggregatorPublicKey;
    mapping(address => bytes) /* feeder */ /* publicKey */
        public feedersPublicKey;
    uint256 public startTimestamp;
    uint256 public updatedEpoch;
    // uint256 public epochEndTimestamp;
    mapping(uint256 => uint256) /* epoch */ /* storeNumber */
        public currentStoredDataNumber;
    mapping(uint256 => mapping(address => bool)) /* epoch */ /* feeder */ /* isStored */
        public isFeederStored;
    mapping(uint256 => uint256) /* epoch */ /* feederNumber */
        public feederStoreNumber;
    uint256 public quorum;

    event StoreFeederData(address indexed feeder, bytes data, bytes32 hash, uint256 currentEpoch, bool isUpdate);
    event StoreAllFeederData(uint256 currentEpoch, uint256 feederNum);
    event StoreAggregatedData(address indexed agg, int256 answer, uint256 currentEpoch);

    event SetFeeder(address indexed newFeeder, uint256 currentTime);
    event SetAggregator(address indexed newAggregator, uint256 currentTime);

    event SetEpochPeriod(uint256 newEpochPereiod, uint256 currentTime);

    event SetQuorum(uint256 indexed newQuorum, uint256 currentTime);
    event AddFeeder(address indexed account, uint256 currentTime);
    event SetAggregatorPublicKey(bytes indexed publicKey, uint256 currentTime);
    event SetFeederPublicKey(bytes indexed publicKey, uint256 currentTime);

    event Penalize(address feeder);

    modifier onlyFeeder() {
        require(isFeeder[msg.sender], "Sender is not a feeder");
        _;
    }

    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Sender is not a aggregator");
        _;
    }

    function initialize() external initializer {
        __Ownable_init();
        epochPeriod = 60;
        aggregator = msg.sender;
        startTimestamp = block.timestamp;
        updatedEpoch = 1;
        quorum = 3;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //set epoch period
    function setEpochPeriod(uint256 newEpochPeriod) external onlyOwner {
        require(newEpochPeriod != 0, "epoch period can not be 0");
        epochPeriod = newEpochPeriod;
        updatedEpoch = (block.timestamp - startTimestamp) / epochPeriod + updatedEpoch; // currentEpoch
        startTimestamp = block.timestamp;
        emit SetEpochPeriod(epochPeriod, block.timestamp);
    }

    //set aggregator
    function setAggregator(address newAggregator) external onlyOwner {
        require(newAggregator != address(0), "Aggregator cannot be zero");
        aggregator = newAggregator;
        emit SetAggregator(newAggregator, block.timestamp);
    }

    //set quorum
    function setQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum < feederLength && newQuorum > 0, "Wrong quorum");
        quorum = newQuorum;
        emit SetQuorum(newQuorum, block.timestamp);
    }

    //get the latest epoch data
    function latestEpochData() external view returns (AnswerDastaForm memory) {
        return aggregatedData[lastUpdatedEpoch];
    }

    //get the latest epoch answer
    function latestAnswer() external view returns (int256) {
        return aggregatedData[lastUpdatedEpoch].answer;
    }

    //get a specific epoch data
    function getData(uint256 epoch) external view returns (AnswerDastaForm memory) {
        return aggregatedData[epoch];
    }

    //get the latest timestamp
    function latestTimestamp() external view returns (uint256) {
        return lastUpdatedTime;
    }

    //get a speicific epoch timestamp
    function getCreatedTimestamp(uint256 epoch) external view returns (uint256) {
        return aggregatedData[epoch].startedAt;
    }

    //get a speicific epoch timestamp
    function getUpdatedTimestamp(uint256 epoch) external view returns (uint256) {
        return aggregatedData[epoch].updatedAt;
    }

    //get the latest epoch number
    function latestEpoch() external view returns (uint256) {
        return lastUpdatedEpoch;
    }

    //add the latest epoch aggregated data
    function addData(int256 answer) external onlyAggregator {
        // stored dsata is in a block ago
        uint256 storedEpoch = (block.timestamp - startTimestamp) / epochPeriod + updatedEpoch - 1;
        require(feederStoreNumber[storedEpoch] >= quorum, "Not enough quorum");
        lastUpdatedTime = block.timestamp;
        lastUpdatedEpoch = storedEpoch;

        if (aggregatedData[storedEpoch].startedAt == 0) {
            AnswerDastaForm memory dataForm = AnswerDastaForm(
                storedEpoch,
                answer,
                lastUpdatedTime,
                lastUpdatedTime,
                storedEpoch
            );
            aggregatedData[lastUpdatedEpoch] = dataForm;
        } else {
            aggregatedData[storedEpoch].updatedAt = lastUpdatedTime;
            aggregatedData[storedEpoch].answer = answer;
            aggregatedData[storedEpoch].answeredInEpoch = storedEpoch;
        }
        if (feederStoreNumber[storedEpoch] < feederLength) {
            unchecked {
                for (uint256 i = 0; i < feederLength; i++) {
                    if (!isFeederStored[storedEpoch][feeders[i]]) {
                        penalize(feeders[i]);
                    }
                }
            }
        }

        emit StoreAggregatedData(msg.sender, answer, lastUpdatedEpoch);
    }

    //add the latest epoch aggregated data
    function addData(uint256 storedEpoch, int256 answer) external onlyAggregator {
        // stored dsata is in a block ago
        require(feederStoreNumber[storedEpoch] >= quorum, "Not enough quorum");
        lastUpdatedTime = block.timestamp;
        if (lastUpdatedEpoch < storedEpoch) lastUpdatedEpoch = storedEpoch;

        if (aggregatedData[storedEpoch].startedAt == 0) {
            AnswerDastaForm memory dataForm = AnswerDastaForm(
                lastUpdatedEpoch,
                answer,
                lastUpdatedTime,
                lastUpdatedTime,
                storedEpoch
            );
            aggregatedData[lastUpdatedEpoch] = dataForm;
        } else {
            aggregatedData[storedEpoch].updatedAt = lastUpdatedTime;
            aggregatedData[storedEpoch].answer = answer;
            aggregatedData[storedEpoch].answeredInEpoch = storedEpoch;
        }
        if (feederStoreNumber[storedEpoch] < feederLength) {
            unchecked {
                for (uint256 i = 0; i < feederLength; i++) {
                    if (!isFeederStored[storedEpoch][feeders[i]]) {
                        penalize(feeders[i]);
                    }
                }
            }
        }

        emit StoreAggregatedData(msg.sender, answer, lastUpdatedEpoch);
    }

    //store data from feeder
    function storeData(bytes memory data) external onlyFeeder {
        uint256 currentEpoch = (block.timestamp - startTimestamp) / epochPeriod + updatedEpoch;
        if (feederLastUpdatedEpoch[msg.sender] == currentEpoch) {
            feederData[currentEpoch][msg.sender].data = data;
            feederData[currentEpoch][msg.sender].updatedAt = block.timestamp;
            feederData[currentEpoch][msg.sender].hash = keccak256(data);
        } else {
            DataForm memory dataForm = DataForm(data, block.timestamp, block.timestamp, keccak256(data));
            feederData[currentEpoch][msg.sender] = dataForm;
            feederLastUpdatedEpoch[msg.sender] = currentEpoch;
        }

        currentStoredDataNumber[currentEpoch]++;
        if (!isFeederStored[currentEpoch][msg.sender]) {
            feederStoreNumber[currentEpoch]++;
            isFeederStored[currentEpoch][msg.sender] = true;
        }
        if (feederStoreNumber[currentEpoch] == feederLength) {
            emit StoreAllFeederData(currentEpoch, feederLength);
        }

        emit StoreFeederData(
            msg.sender,
            data,
            feederData[currentEpoch][msg.sender].hash,
            currentEpoch,
            feederLastUpdatedEpoch[msg.sender] != currentEpoch
        );
    }

    ///TODO penalize
    function penalize(address feeder) internal {
        emit Penalize(feeder);
    }

    //get a speicific feeder and a specific epoch data
    function getFeederData(address feeder, uint256 epoch) external view returns (DataForm memory) {
        return feederData[epoch][feeder];
    }

    function getAllFeederData(uint256 epoch)
        external
        view
        returns (DataForm[] memory data, address[] memory resFeeders)
    {
        data = new DataForm[](feederLength);
        resFeeders = feeders;
        unchecked {
            for (uint256 i = 0; i < feederLength; i++) {
                data[i] = feederData[epoch][feeders[i]];
            }
        }
    }

    //add feeder
    //only owner access
    ///TODO feeder can be anyone
    function addFeeder(address newFeeder) external onlyOwner {
        require(!isFeeder[newFeeder], "Already Feeder");
        feeders.push(newFeeder);
        isFeeder[newFeeder] = true;
        feederLength = feeders.length;
        emit AddFeeder(newFeeder, block.timestamp);
    }

    function getFeeders() external view returns (address[] memory) {
        return feeders;
    }

    function setAggregatorPublicKey(bytes memory publicKey) external onlyAggregator {
        aggregatorPublicKey = publicKey;
        emit SetAggregatorPublicKey(publicKey, block.timestamp);
    }

    function setFeederPublicKey(bytes memory publicKey) external onlyFeeder {
        feedersPublicKey[msg.sender] = publicKey;
        emit SetFeederPublicKey(publicKey, block.timestamp);
    }

    function getTimeout() external view returns (uint256) {
        uint256 currentEpoch = (block.timestamp - startTimestamp) / epochPeriod + updatedEpoch;
        return (currentEpoch + 1 - updatedEpoch) * epochPeriod + startTimestamp;
    }
}
