// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RewardsToken is ERC20
{
    constructor() ERC20("RewardsToken", "TTT")
    { _mint(msg.sender, 1000000); } 
}