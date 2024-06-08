// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DUSD} from "../src/DUSD.sol";
import {DUSDEngine} from "../src/DUSDEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDUSD is Script {
    address [] public tokenAddresses;
    address [] public priceFeedAddresses;

    function run() external returns (DUSD, DUSDEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethUSDPriceFeed,
            address wbtcUSDPriceFeed,
            address wethAddress,
            address wbtcAddress,
            address ownerAddress,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        tokenAddresses = [wethAddress, wbtcAddress];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];
        vm.startBroadcast(deployerKey);
        DUSD dUSD = new DUSD(ownerAddress);
        DUSDEngine dUSDEngine = new DUSDEngine(tokenAddresses, priceFeedAddresses, address(dUSD));
        dUSD.transferOwnership(address(dUSDEngine));
        vm.stopBroadcast();
        return(dUSD, dUSDEngine, helperConfig);
    }
}
