// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20 ;

import {Test} from "forge-std/Test.sol";
import {DeployDUSD} from "../../script/DeployDUSD.s.sol";
import {DUSD} from "../../src/DUSD.sol";
import {DUSDEngine} from "../../src/DUSDEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract DUSDEngineTest is Test{
    DeployDUSD public deployer;
    DUSD public dUSDtoken;
    DUSDEngine public dUSDEngine;
    HelperConfig public helperConfig;
    address weth;
    address ethToUsdPriceFeed;
    address public USER = makeAddr("USER");
    uint256 public constant INITIAL_GAS = 1 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_WETH_BALANCE = 10 ether;

    function setUp() public{
        deployer = new DeployDUSD();
       (dUSDtoken, dUSDEngine, helperConfig) = deployer.run();
       (ethToUsdPriceFeed,,weth,,,) = helperConfig.activeNetworkConfig();
       ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);
       vm.deal(USER, INITIAL_GAS);
    }


    ////////////////////
    //Price Feed test///
    ////////////////////

    function testGetUSDValue() public view  {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dUSDEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd,actualUsd);
    }

     ////////////////////////////
    //Deposit Collateral test///
   ////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dUSDEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DUSDEngine.DUSDEngine__MustBeMoreThanZero.selector);
        dUSDEngine.depositCollateral(weth, 0);
    }
}