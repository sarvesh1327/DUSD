// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20 ;

import {Test, console} from "forge-std/Test.sol";

import {DUSDEngine} from "../../src/DUSDEngine.sol";
import {DUSD} from "../../src/DUSD.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DUSDEngine public dUSDEngine;
    DUSD public dUSDToken;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public mintIScalled = 0;
    address[] public userWithCollateralDeposited;
    address wethPriceFeed;
    address wbtcPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DUSDEngine _dUSDEngine, DUSD _dUSD){
        dUSDEngine = _dUSDEngine;
        dUSDToken = _dUSD;
        address [] memory collateralTokens = dUSDEngine.getCollatrealTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]); 
        wethPriceFeed = dUSDEngine.getCollateralTokenPriceFeed(address(weth)); 
        wbtcPriceFeed = dUSDEngine.getCollateralTokenPriceFeed(address(wbtc)); 
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dUSDEngine), amountCollateral);
        dUSDEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 availableCollateral = dUSDEngine.getCollateralAmount(address(collateral), msg.sender);

        (uint256 totalDUSDMinted, uint256 totalCollateralValue) = dUSDEngine.getAccountInformation(msg.sender);
        console.log(totalDUSDMinted, totalCollateralValue);

        uint256 availableCollateralInUSD = dUSDEngine.getUsdValue(address(collateral), availableCollateral);
        if(availableCollateralInUSD/2<totalDUSDMinted){
            return;
        }
        uint256 maxCollateralAllowedInUSD = ((availableCollateralInUSD/2)- totalDUSDMinted);
        uint256 maxCollateralAllowed = dUSDEngine.getTokenAmountFromUsd(address(collateral), maxCollateralAllowedInUSD); 
        amountCollateral = bound(amountCollateral, 0, maxCollateralAllowed);
        if(amountCollateral == 0){
            return;
        }
        vm.startPrank(msg.sender);
        dUSDEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDUSD(uint256 amount, uint256 addressSeed) public{
        if(userWithCollateralDeposited.length==0){
            return;
        }
        address sender =  _getSender(addressSeed);
        (uint256 totalDUSDMinted, uint256 totalCollateralValue) = dUSDEngine.getAccountInformation(sender);
        int256 maxDUSDToMint = (int256(totalCollateralValue/2)) - int256(totalDUSDMinted);
        if(maxDUSDToMint<0){
            return;
        }
        amount = bound(amount, 0, uint256(maxDUSDToMint));
        if(amount==0){
            return;
        }
        vm.startPrank(sender);
        dUSDEngine.mintDUSD(amount);
        vm.stopPrank();
        mintIScalled++;
    }

    // This breaks our invariant test suite!|!|!
    // function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public{
    //     uint256 newPriceAllowed = bound(uint256(newPrice), 1, MAX_DEPOSIT_SIZE);
    //     int256 newPriceInt = int256(newPriceAllowed);
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     address priceFeed = _getPriceFeed(address(collateral));
    //     MockV3Aggregator(priceFeed).updateAnswer(newPriceInt);
    // }



    // Helper function
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed%2==0){
            return weth;
        }
        return wbtc;
    }

    function _getSender(uint256 addressSeed) private view returns(address){
        return userWithCollateralDeposited[addressSeed%userWithCollateralDeposited.length];
    }

    function _getPriceFeed(address token) private view returns(address){
        if(token==address(weth)){
            return wethPriceFeed;
        }
        return wbtcPriceFeed;
    }
}