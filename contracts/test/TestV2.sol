
pragma solidity 0.8.11;

import "../common/upgradeable/Initializable.sol";

/// @notice this contract is for testing upgrade of upgradable contracts
contract TestV2 is Initializable {
    bool public isImplementation;
    bool public isNew;
    uint256 public year;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {}

    function version() public view returns (uint256) {
        return 2;
    }
}
