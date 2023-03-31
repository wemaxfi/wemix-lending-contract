// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.11;

import "./IERC20.sol";

/// @notice deposit default unredeemable amount of asset in markets
/// @dev Team should mint small default amount of cTokens from all markets after deployment
///  resolves audit issue CTL-05
contract TeamMinter {
    /// @notice Emitted when cToken is minted by team through this contract
    /// @param minter address who minted cToken
    /// @param cTokenAddress address of cToken minted
    /// @param mintAmount deposited amount of underlying asset
    event TeamMint(address minter, address cTokenAddress, uint256 mintAmount);

    /// @notice only address which can mint cToken through this contract
    address public admin;

    // Selector for external call
    bytes4 private constant CETHER_SELECTOR = bytes4(keccak256(bytes("mint()")));
    bytes4 private constant CERC20_SELECTOR = bytes4(keccak256(bytes("mint(uint256)")));

    constructor() {
        admin = msg.sender;
    }

    receive() external payable {}

    /// @notice CEther 풀 고정 물량 세팅을 위한 Mint 함수
    /// @notice mintAmount 이상의 balance가 있어야한다.
    /// @dev 함수 실행 전 관리자가 해당 컨트랙트로 토큰 전송 필요
    /// @param cEtherAddress CEther 컨트랙 주소
    /// @param mintAmount 풀 초기 고정 물량으로 공급할 ETH 수량
    function unredeemableCEtherMint(address cEtherAddress, uint256 mintAmount) external payable {
        require(msg.sender == admin, "E1");
        require(address(this).balance >= mintAmount, "Balance is not enough");

        (bool success, bytes memory data) = cEtherAddress.call{ value: mintAmount }(
            abi.encodeWithSelector(CETHER_SELECTOR)
        );

        require(success && abi.decode(data, (uint256)) == mintAmount, "E120");

        emit TeamMint(msg.sender, cEtherAddress, mintAmount);
    }

    /// @notice CErc20 풀 고정 물량 세팅을 위한 Mint 함수
    /// @notice mintAmount 이상의 balance가 있어야한다.
    /// @dev 함수 실행 전 관리자가 해당 컨트랙트로 토큰 전송 필요
    /// @param cErc20Address: CERC20 컨트랙 주소
    /// @param underlyingTokenAddress: CERC20 의 underlying token 주소
    /// @param mintAmount 풀 초기 고정 물량으로 공급할 underlying token 수량
    function unredeemableCErc20Mint(
        address cErc20Address,
        address underlyingTokenAddress,
        uint256 mintAmount
    ) external {
        require(msg.sender == admin, "E1");
        require(IERC20(underlyingTokenAddress).balanceOf(address(this)) >= mintAmount, "Balance is not enough");

        IERC20(underlyingTokenAddress).approve(cErc20Address, mintAmount);

        (bool success, bytes memory data) = cErc20Address.call(abi.encodeWithSelector(CERC20_SELECTOR, mintAmount));
        require(success && abi.decode(data, (uint256)) == mintAmount, "E120");

        emit TeamMint(msg.sender, cErc20Address, mintAmount);
    }
}
