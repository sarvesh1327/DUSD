// SPDX-License-Identifier: MIT

//What are our invariants

// 1. Total value of DUSD should be less than total value of Collateral

// 2. Getter view function should never revert <- evergreen invariant

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDUSD} from "../../script/DeployDUSD.s.sol";
import {DUSD} from "../../src/DUSD.sol";
import {DUSDEngine} from "../../src/DUSDEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDUSD public deployer;
    DUSD public dUSDToken;
    DUSDEngine public dUSDEngine;
    HelperConfig public helperConfig;
    address public weth;
    address public wbtc;
    Handler public handler;

    function setUp() external{
        deployer = new DeployDUSD();
        (dUSDToken, dUSDEngine, helperConfig) = deployer.run();
        (,,weth, wbtc,,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dUSDEngine, dUSDToken);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralValueThanTotalSupply() public view{
        uint256 dUSDTotalSuppy = dUSDToken.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dUSDEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dUSDEngine));
        uint256 wethUSDValue = dUSDEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcUSDValue = dUSDEngine.getUsdValue(wbtc, totalWbtcDeposited);
        console.log(wethUSDValue, wbtcUSDValue, dUSDTotalSuppy);
        console.log("Times mint is called", handler.mintIScalled());
        assertGe( wethUSDValue+wbtcUSDValue, dUSDTotalSuppy );
    }


}