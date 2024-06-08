// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DUSD-decentralized Stable coin
 * @author Sarvesh Agarwal (sarveshagl1327@gmail.com) github- sarvesh1327
 * Collateral: Exogenous ETH &BTC
 * Minting: Algorithmic
 * This contract is meant to be governed by DUSDEngine.
 * @notice
 */
contract DUSD is ERC20Burnable, Ownable {
    error DUSD__MustBeMoreThanZero();
    error DUSD__BurnAmountMustExceedBalance();
    error DUSD__NotZeroAddress();

    constructor(address _owner) ERC20("DecentralizedUSD", "DUSD") Ownable(_owner) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DUSD__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DUSD__BurnAmountMustExceedBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DUSD__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DUSD__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
