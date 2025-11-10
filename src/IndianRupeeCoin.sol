// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title DecentralizedStableCoin
* @author 0xAnvesaka , POISON
* Collateral: Exogenous (ETH & BTC)
* Mintiing: Algorithmic
* Relative Stability: Pegged to USD
*
* THis is the contract meant to be governed by DSCEngine. This contract is just ERC20
 implementation of our stablecoin system.
*/

contract IndianRupeeCoin is ERC20Burnable, Ownable {
    error IndianRupeeCoin__MustBeMoreThanZero();
    error IndianRupeeCoin__BurnAmountExceedsBalance();
    error IndianRupeeCoin__NotZeroAddress();

    constructor(address initialOwner) ERC20("Indian Rupee Tether", "IRT") Ownable(initialOwner) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert IndianRupeeCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert IndianRupeeCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert IndianRupeeCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert IndianRupeeCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
