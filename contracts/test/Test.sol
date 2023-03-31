
pragma solidity 0.8.11;

import "../common/upgradeable/Initializable.sol";

/// @notice this contract is for testing upgrade of upgradable contracts
contract Test is Initializable {
    bool public isImplementation;
    uint256 public year;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        isImplementation = true;
    }

    function version() public view returns (uint256) {
        return 1;
    }
}
