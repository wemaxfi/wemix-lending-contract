pragma solidity ^0.8.10;

interface IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool success);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool success);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}
