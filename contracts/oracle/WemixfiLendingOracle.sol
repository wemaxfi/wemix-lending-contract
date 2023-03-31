// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.11;

import { IDataCollector } from "./common/IDataCollector.sol";
import { Initializable } from "../common/upgradeable/Initializable.sol";
import "../lending/ControllerInterface.sol";

/**
 * @notice Proxy Oracle Contract to manage and get prices from WM oracles
 */
contract WemixfiLendingOracle is Initializable {
    struct UnderlyingToken {
        // WM price oracle address per token
        address oracleAddress;
        // oracle decimal: 8, 18, ...
        uint256 oracleDecimal;
        // token decimal: 8, 18, ...
        uint256 tokenDecimal;
    }

    /// @notice mapping of Oracle Information by token symbol
    mapping(bytes32 => UnderlyingToken) public getOracle;

    /// @notice Controller contract address to get admin from
    ControllerInterface public controller;

    /// @notice Emitted when Oracle is added
    /// @param symbol underyling token symbol of the Market
    /// @param priceOracleAddress added WM oracle address of the market
    event OracleCreated(bytes32 indexed symbol, address priceOracleAddress);

    /// @notice Emitted when Oracle is removed
    /// @param symbol underyling token symbol of the Market
    /// @param priceOracleAddress removed WM oracle address of the market
    event OracleRemoved(bytes32 indexed symbol, address priceOracleAddress);

    /// @notice Emitted when Controller address is changed
    event NewController(ControllerInterface newController);

    modifier onlyMasterAdmin() {
        require(msg.sender == controller.getMasterAdmin(), "E1");
        _;
    }

    function initialize(ControllerInterface controller_) public initializer {
        require(address(controller_) != address(0), "E117");
        controller = controller_;
        emit NewController(controller_);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice set new Controller address
    function setController(ControllerInterface newController) external onlyMasterAdmin {
        require(address(newController) != address(0), "E117");
        controller = newController;

        emit NewController(newController);
    }

    /**
     * @notice get formatted underlying price of token from WM oracle
     * @param symbol token symbol to get price from WM oracle
     * @return Formatted Price with additional decimals to use in Controller and View contracts
     */
    function getUnderlyingPrice(bytes32 symbol) external view returns (uint256) {
        address priceOracle = getOracle[symbol].oracleAddress;
        require(priceOracle != address(0), "ERROR: No oracle exist.");

        uint256 oracleDecimal = getOracle[symbol].oracleDecimal;
        uint256 tokenDecimal = getOracle[symbol].tokenDecimal;
        require(oracleDecimal != 0 && tokenDecimal != 0, "ERROR: Decimal must be non-zero.");

        uint256 unformattedPrice = uint256(IDataCollector(priceOracle).latestAnswer());
        uint256 formattedDecimal = 36 - oracleDecimal - tokenDecimal;
        uint256 formattedPrice = unformattedPrice * 10**formattedDecimal;
        // 1e8 * formattedDecimal = 1e8 * (1e36 / (1e8 * 1e18)) = 1e8 * (1e36 / 1e26) = 1e8 * 1e10 = 1e18
        // 1e8 * formattedDecimal = 1e8 * (1e36 / (1e8 * 1e8)) = 1e8 * (1e36 / 1e16) = 1e8 * 1e20 = 1e28

        return formattedPrice;
    }

    function setOracle(
        bytes32 symbol,
        address priceOracleAddress,
        uint256 oracleDecimal,
        uint256 tokenDecimal
    ) external onlyMasterAdmin {
        UnderlyingToken memory underlyingTokenInfo;

        require(priceOracleAddress != address(0), "E117");
        underlyingTokenInfo.oracleAddress = priceOracleAddress;
        underlyingTokenInfo.oracleDecimal = oracleDecimal;
        underlyingTokenInfo.tokenDecimal = tokenDecimal;
        getOracle[symbol] = underlyingTokenInfo;

        emit OracleCreated(symbol, priceOracleAddress);
    }

    function removeOracle(bytes32 symbol) external onlyMasterAdmin {
        address priceOracleAddress = getOracle[symbol].oracleAddress;

        UnderlyingToken memory emptyUnderlyingTokenInfo;
        getOracle[symbol] = emptyUnderlyingTokenInfo;

        emit OracleRemoved(symbol, priceOracleAddress);
    }
}
