// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

import "./IERC20.sol";

import "../common/upgradeable/Initializable.sol";

interface ICEther {
    function repayBorrowHelper(address caller) external payable returns (uint256);

    function mintHelper(address caller) external payable returns (uint256);
}

interface ICErc20 {
    function repayBorrowHelper(address caller, uint256 repayAmount) external returns (uint256);

    function mintHelper(address caller, uint256 mintAmount) external returns (uint256);
}

interface ICToken {
    function borrowHelper(address caller, uint256 borrowAmount) external;
}

/// @notice Contract to handle multiple actions with CTokens in single transactions
contract TransactionHelper is Initializable {
    struct Market {
        address cTokenAddress;
        // zero address if isCEther true
        address underlyingTokenAddress;
        bool isCEther;
    }

    function initialize() public initializer {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Mint cToken from MintMarket and Borrow cToken from borrowMarket in single tx
     * @param mintMarket Market data to mint cToken
     * @param mintAmount underlying amount of mintMarket to deposit
     * @param borrowMarket Market data to borrow
     * @param borrowAmount underlying amount of borrowMarket to borrow
     */
    function singleMintAndBorrow(
        Market memory mintMarket,
        uint256 mintAmount,
        Market memory borrowMarket,
        uint256 borrowAmount
    ) external payable {
        if (mintMarket.isCEther == true) {
            ICEther(mintMarket.cTokenAddress).mintHelper{ value: mintAmount }(msg.sender);
        } else {
            ICErc20(mintMarket.cTokenAddress).mintHelper(msg.sender, mintAmount);
        }

        ICToken(borrowMarket.cTokenAddress).borrowHelper(msg.sender, borrowAmount);
    }
}
