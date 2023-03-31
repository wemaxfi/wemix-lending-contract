// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/Maximillion.sol

import "./CEther.sol";
import "./Error.sol";
import "../common/upgradeable/Initializable.sol";

/// @notice Contract used to repay in cEther market and refund excess balance from received
contract Maximillion is Initializable, TokenErrorReporter {
    /// @notice The default cEther market to repay in
    CEther public cEther;

    function initialize(CEther cEther_) public initializer {
        cEther = cEther_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice msg.sender sends Ether to repay an account's borrow in the cEther market
     * @dev The provided Ether is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     */
    function repayBehalf(address borrower) public payable {
        repayBehalfExplicit(borrower, cEther);
    }

    /**
     * @notice msg.sender sends Ether to repay an account's borrow in a cEther market
     * @dev The provided Ether is applied towards the borrow balance, any excess is refunded
     * @param borrower The address of the borrower account to repay on behalf of
     * @param cEther_ The address of the cEther contract to repay in
     */
    function repayBehalfExplicit(address borrower, CEther cEther_) public payable {
        uint256 received = msg.value;
        uint256 borrows = cEther_.borrowBalanceCurrent(borrower);
        if (received > borrows) {
            cEther_.repayBorrowBehalf{ value: borrows }(borrower);
            uint256 subResult = received - borrows;
            payable(msg.sender).transfer(subResult);
        } else {
            cEther_.repayBorrowBehalf{ value: received }(borrower);
        }
    }
}
