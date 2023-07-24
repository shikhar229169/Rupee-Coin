// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RupeeCoin is ERC20Burnable, Ownable {
    error RupeeCoin__amountMustBeMoreThanZero();
    error RupeeCoin__amountCantBeMoreThanBalance();
    error RupeeCoin__addressCantBeNull();

    constructor() ERC20("Rupee Coin", "RC") {

    }

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (amount == 0) {
            revert RupeeCoin__amountMustBeMoreThanZero();
        }

        if (amount > balance) {
            revert RupeeCoin__amountCantBeMoreThanBalance();
        }

        super.burn(amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount == 0) {
            revert RupeeCoin__amountMustBeMoreThanZero();
        }

        if (_to == address(0)) {
            revert RupeeCoin__addressCantBeNull();
        }

        _mint(_to, _amount);

        return true;
    }
}