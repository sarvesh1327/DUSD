// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script{
    struct NetworkConfig{
        address wethUSDPriceFeed;
        address wbtcUSDPriceFeed;
        address wethAddress;
        address wbtcAddress;
        address ownerAddress;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000*1e8;
    int256 public constant BTC_USD_PRICE = 1000*1e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public constant DEFAULT_ANVIl_OWNER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public activeNetworkConfig;

    constructor(){
        if(block.chainid==11155111){
            activeNetworkConfig = getSepoliaEthConfig();
        }else{
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns(NetworkConfig memory){
        return NetworkConfig(
            {
                wethUSDPriceFeed:0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wbtcUSDPriceFeed:0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                wethAddress: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtcAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                ownerAddress: vm.envAddress("OWNER_ADDRESS"),
                deployerKey: vm.envUint("PRIV_KEY")
            }
        );
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory){
        if(activeNetworkConfig.wethUSDPriceFeed!=address(0)){
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();
        return NetworkConfig({
            wethUSDPriceFeed: address(wethPriceFeed),
            wbtcUSDPriceFeed: address(wbtcPriceFeed),
            wethAddress: address(weth),
            wbtcAddress: address(wbtc),
            ownerAddress: DEFAULT_ANVIl_OWNER_ADDRESS,
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }


}