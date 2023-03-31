// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

// Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/BaseJumpRateModelV2.sol

import "../common/upgradeable/Initializable.sol";
import "./ControllerInterface.sol";

contract InterestRateModel is Initializable {
    bool public constant isInterestRateModel = true;

    event NewInterestParams(
        uint256 baseRatePerBlock,
        uint256 multiplierPerBlock,
        uint256 jumpMultiplierPerBlock,
        uint256 kink
    );
    /// @notice Emitted when Controller address is changed
    event NewController(ControllerInterface newController);

    /// @notice average blocks mined per year (365 days)
    /// @dev WARNING: check this value based on deploying network
    uint256 public constant blocksPerYear = 31536000;

    /// @notice The multiplier of utilization rate that gives the slope of the interest rate, scaled by 1e18
    uint256 public multiplierPerBlock;

    /// @notice The base interest rate which is the y-intercept when utilization rate is 0, scaled by 1e18
    uint256 public baseRatePerBlock;

    /// @notice The multiplierPerBlock after hitting a specified utilization point, scaled by 1e18
    uint256 public jumpMultiplierPerBlock;

    /// @notice The utilization point at which the jump multiplier is applied, scaled by 1e18
    uint256 public kink;

    /// @notice Controller address to fetch admin info
    ControllerInterface public controller;

    /// @notice storage gap for upgrading contract
    /// @dev warning: should reduce the appropriate number of slots when adding storage variables
    /// @dev resources: https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    uint256[50] private __gap;

    modifier onlyMasterAdmin() {
        require(msg.sender == controller.getMasterAdmin(), "E1");
        _;
    }

    modifier onlyServiceAdmin() {
        require(controller.getIsServiceAdmin(msg.sender), "E1");
        _;
    }

    function initialize(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_,
        ControllerInterface controller_
    ) public initializer {
        require(address(controller_) != address(0), "E117");
        controller = controller_;
        emit NewController(controller_);

        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256) {
        return getBorrowRateInternal(cash, borrows, reserves);
    }

    function updateJumpRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) external onlyServiceAdmin {
        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    function getBorrowRateInternal(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) internal view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            return ((util * multiplierPerBlock) / 1e18) + baseRatePerBlock;
        } else {
            uint256 normalRate = (kink * multiplierPerBlock) / 1e18 + baseRatePerBlock;
            uint256 excessUtil = util - kink;
            return (excessUtil * jumpMultiplierPerBlock) / 1e18 + normalRate;
        }
    }

    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view returns (uint256) {
        uint256 oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRateInternal(cash, borrows, reserves);
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / 1e18;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / 1e18;
    }

    function updateJumpRateModelInternal(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink_
    ) internal {
        baseRatePerBlock = baseRatePerYear / blocksPerYear;
        multiplierPerBlock = (multiplierPerYear * 1e18) / (blocksPerYear * kink_);
        jumpMultiplierPerBlock = jumpMultiplierPerYear / blocksPerYear;
        kink = kink_;

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
    }

    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure returns (uint256) {
        if (borrows == 0) {
            return 0;
        }

        return (borrows * 1e18) / (cash + borrows - reserves);
    }

    /// @notice set new Controller address
    function setController(ControllerInterface newController) external onlyMasterAdmin {
        require(address(newController) != address(0), "E117");
        controller = newController;

        emit NewController(newController);
    }
}
