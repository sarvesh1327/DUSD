// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDUSD} from "../../script/DeployDUSD.s.sol";
import {DUSD} from "../../src/DUSD.sol";
import {DUSDEngine} from "../../src/DUSDEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DUSDEngineTest is Test {
    DeployDUSD public deployer;
    DUSD public dUSDtoken;
    DUSDEngine public dUSDEngine;
    HelperConfig public helperConfig;
    address weth;
    address ethToUsdPriceFeed;
    address btcToUsdPriceFeed;
    address public USER = makeAddr("USER");
    uint256 public constant INITIAL_GAS = 1 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_WETH_BALANCE = 100 ether;
    uint256 public constant MINT_DUSD_STARTING = 10000 ether;
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");

    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 indexed amount);

    function setUp() public {
        deployer = new DeployDUSD();
        (dUSDtoken, dUSDEngine, helperConfig) = deployer.run();
        (ethToUsdPriceFeed, btcToUsdPriceFeed, weth,,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_WETH_BALANCE);
        vm.deal(USER, INITIAL_GAS);
        vm.deal(LIQUIDATOR, INITIAL_GAS);
    }

    ////////////////////
    //Constructor Test//
    ////////////////////

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethToUsdPriceFeed);
        priceFeedAddresses.push(btcToUsdPriceFeed);

        vm.expectRevert(DUSDEngine.DUSDEngine__TokenAddressedAndPriceFeedAddressesLengthMustBeSame.selector);
        new DUSDEngine(tokenAddresses, priceFeedAddresses, address(dUSDtoken));
    }

    ////////////////////
    //Price Feed test///
    ////////////////////

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dUSDEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dUSDEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
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

    function testRevertIfNotAllowedToken() public {
        address erc20 = makeAddr("MockErc20");
        vm.prank(USER);
        vm.expectRevert(DUSDEngine.DUSDEngine__TokenNotAllowed.selector);
        dUSDEngine.depositCollateral(erc20, 100);
    }

    function depositCollateralMultiplier(address user, uint256 times, uint256 amountCollateral) public {
        vm.startPrank(user);
        for (uint256 i = 0; i < times; i++) {
            ERC20Mock(weth).approve(address(dUSDEngine), amountCollateral);
            dUSDEngine.depositCollateral(weth, amountCollateral);
        }
        vm.stopPrank();
    }

    function mintDUSDMultiplier(address user, uint256 times, uint256 mintAmount) public {
        vm.startPrank(user);
        for (uint256 i = 0; i < times; i++) {
            dUSDEngine.mintDUSD(mintAmount);
        }
        vm.stopPrank();
    }

    modifier depositCollateral(address user, uint256 times, uint256 amountCollateral) {
        depositCollateralMultiplier(user, times, amountCollateral);
        _;
    }

    modifier mintDUSD(address user, uint256 times, uint256 mintAmount) {
        mintDUSDMultiplier(user, times, mintAmount);
        _;
    }

    function testDepositCollateralShouldIncreaseTheCollateralOfUser()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
    {
        (uint256 totalDUSDMinted, uint256 totalCollateralValueInUsd) = dUSDEngine.getAccountInformation(USER);
        uint256 expectedTotalDUSDMinted = 0;
        uint256 expectedTotalCollateralValue = dUSDEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assertEq(totalDUSDMinted, expectedTotalDUSDMinted);
        assertEq(expectedTotalCollateralValue, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dUSDEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dUSDEngine));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dUSDEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /////////////////////
    // Mint DUSD test ///
    /////////////////////

    function testRevertIfMintAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DUSDEngine.DUSDEngine__MustBeMoreThanZero.selector);
        dUSDEngine.mintDUSD(0);
    }

    function testRevertMintIfNoepositOfCollateral() public {
        uint256 initialMintAmount = 3 ether;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DUSDEngine.DUSDEngine__HealthFactorIsBroken.selector, 0));
        dUSDEngine.mintDUSD(initialMintAmount);
    }

    function testRevertMintIfHealthFactorTooLow() public depositCollateral(USER, 1, AMOUNT_COLLATERAL) {
        uint256 initialMintAmount = 20000 ether;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DUSDEngine.DUSDEngine__HealthFactorIsBroken.selector, 5e17));
        dUSDEngine.mintDUSD(initialMintAmount);
    }

    function testUserShouldBeAbleToMintDUSDIfTheirHealthFactorIsGood()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
    {
        uint256 initialMintAmount = 8000 ether;
        vm.prank(USER);
        dUSDEngine.mintDUSD(initialMintAmount);
        (uint256 totalDUSDMinted,) = dUSDEngine.getAccountInformation(USER);
        console.log(dUSDEngine.getHealthFactor(USER));
        assertEq(totalDUSDMinted, initialMintAmount);
    }

    function testUserShouldBeAbleToDepositCollateralAndMintDUSDInOneTransaction() public {
        uint256 initialMintAmount = 8000 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dUSDEngine), AMOUNT_COLLATERAL);
        dUSDEngine.depositCollateralAndMintDUSD(weth, AMOUNT_COLLATERAL, initialMintAmount);
        vm.stopPrank();

        (uint256 totalDUSDMinted, uint256 totalCollateralValueInUsd) = dUSDEngine.getAccountInformation(USER);
        uint256 expectedTotalCollateralValue = dUSDEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);

        assertEq(totalDUSDMinted, initialMintAmount);
        assertEq(expectedTotalCollateralValue, AMOUNT_COLLATERAL);
    }

    //////////////////////////////
    /// Redeem Collateral Test ///
    //////////////////////////////

    function testRedeemCollateralShouldRevertIfRedeemValueIsZero()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
    {
        vm.startPrank(USER);
        vm.expectRevert(DUSDEngine.DUSDEngine__MustBeMoreThanZero.selector);
        dUSDEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralShouldRevertIfTokenForRedeemIsNotAllowed() public {
        address NonWethToken = makeAddr("NoneWethToken");
        vm.startPrank(USER);
        vm.expectRevert(DUSDEngine.DUSDEngine__TokenNotAllowed.selector);
        dUSDEngine.redeemCollateral(NonWethToken, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralShouldRevertIfHealthFactorBreaks()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        uint256 redeemCollateralAmount = 1 ether;

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DUSDEngine.DUSDEngine__HealthFactorIsBroken.selector, 9e17));
        dUSDEngine.redeemCollateral(weth, redeemCollateralAmount);
        vm.stopPrank();
    }

    function testRedeemCollateralShouldWorkIfHealthFactorDoesntBreak()
        public
        depositCollateral(USER, 2, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        uint256 redeemCollateralAmount = 5 ether;

        vm.startPrank(USER);
        dUSDEngine.redeemCollateral(weth, redeemCollateralAmount);
        vm.stopPrank();

        (uint256 totalDUSDMinted, uint256 totalCollateralValueInUsd) = dUSDEngine.getAccountInformation(USER);
        uint256 expectedTotalCollateralValue = dUSDEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);

        assertEq(totalDUSDMinted, MINT_DUSD_STARTING);
        assertEq(expectedTotalCollateralValue, 2 * AMOUNT_COLLATERAL - redeemCollateralAmount);
    }

    /////////////////////////
    //// Burn DUSD tests ////
    /////////////////////////

    function testBurnDUSDShouldRevertIfAmountIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DUSDEngine.DUSDEngine__MustBeMoreThanZero.selector);
        dUSDEngine.burnDUSD(0);
    }

    function testBurnDUSDShouldWorkIfAppropiateAmountIsAskedToBurn()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        uint256 amountToBurn = 5000 ether;

        vm.startPrank(USER);
        dUSDtoken.approve(address(dUSDEngine), amountToBurn);
        dUSDEngine.burnDUSD(amountToBurn);
        vm.stopPrank();

        (uint256 totalDUSDMinted, uint256 totalCollateralValueInUsd) = dUSDEngine.getAccountInformation(USER);
        uint256 expectedTotalCollateralValue = dUSDEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);

        assertEq(totalDUSDMinted, MINT_DUSD_STARTING - amountToBurn);
        assertEq(expectedTotalCollateralValue, AMOUNT_COLLATERAL);
    }

    function testBurnDUSDShouldFailIfMoreAmountIsBurnedThanMinted()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        uint256 amountToBurn = 11000 ether;

        vm.startPrank(USER);
        dUSDtoken.approve(address(dUSDEngine), amountToBurn);
        vm.expectRevert();
        dUSDEngine.burnDUSD(amountToBurn);
        vm.stopPrank();
    }

    function testUserShouldBeAbleToBurnAndRedeemIfTheHealthFactorDoesntBreak()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        uint256 redeemCollateralAmount = 5 ether;
        uint256 amountToBurn = 5000 ether;

        vm.startPrank(USER);
        dUSDtoken.approve(address(dUSDEngine), amountToBurn);
        dUSDEngine.redeemCollateralForDUSD(weth, redeemCollateralAmount, amountToBurn);
        vm.stopPrank();

        (uint256 totalDUSDMinted, uint256 totalCollateralValueInUsd) = dUSDEngine.getAccountInformation(USER);
        uint256 expectedTotalCollateralValue = dUSDEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);

        assertEq(totalDUSDMinted, MINT_DUSD_STARTING - amountToBurn);
        assertEq(expectedTotalCollateralValue, AMOUNT_COLLATERAL - redeemCollateralAmount);
    }

    function testUserShouldNotBeAbleToBurnAndRedeemIfTheHealthFactorBreak()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        uint256 redeemCollateralAmount = 5 ether;
        uint256 amountToBurn = 4000 ether;

        vm.startPrank(USER);
        dUSDtoken.approve(address(dUSDEngine), amountToBurn);
        vm.expectRevert(
            abi.encodeWithSelector(DUSDEngine.DUSDEngine__HealthFactorIsBroken.selector, 833333333333333333)
        );
        dUSDEngine.redeemCollateralForDUSD(weth, redeemCollateralAmount, amountToBurn);
        vm.stopPrank();
    }

    /////////////////////////
    //// Liquidate tests ////
    /////////////////////////

    function testLiquiateShouldRevertIfDebtToRecoveIsZero() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DUSDEngine.DUSDEngine__MustBeMoreThanZero.selector);
        dUSDEngine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testLiquidateShouldRevertIfTokenCollateralIsNotAllowed() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DUSDEngine.DUSDEngine__TokenNotAllowed.selector);
        dUSDEngine.liquidate(address(0), USER, 200000);
        vm.stopPrank();
    }

    function testLiquidateShouldRevertIfUsersHealthFactorIsNotBroken()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        depositCollateralMultiplier(LIQUIDATOR, 1, AMOUNT_COLLATERAL);
        mintDUSDMultiplier(LIQUIDATOR, 1, MINT_DUSD_STARTING);
        uint256 debtToRecover = 5000 ether;
        vm.startPrank(LIQUIDATOR);
        dUSDtoken.approve(address(dUSDEngine), debtToRecover);
        vm.expectRevert(DUSDEngine.DUSDEngine__HealthFactorNotBroken.selector);
        dUSDEngine.liquidate(weth, USER, debtToRecover);
        vm.stopPrank();
    }

    function testLiquidateShouldWorkIfUsersHealthFactorIsBroken()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        depositCollateralMultiplier(LIQUIDATOR, 3, AMOUNT_COLLATERAL);
        mintDUSDMultiplier(LIQUIDATOR, 2, MINT_DUSD_STARTING);
        int256 ETH_USD_PRICE_FEED_UPDATED_ANSWER = 1800e8;
        MockV3Aggregator(ethToUsdPriceFeed).updateAnswer(ETH_USD_PRICE_FEED_UPDATED_ANSWER);
        uint256 debtToRecover = 10000 ether;
        vm.startPrank(LIQUIDATOR);
        dUSDtoken.approve(address(dUSDEngine), debtToRecover);
        dUSDEngine.liquidate(weth, USER, debtToRecover);
        vm.stopPrank();
        assertEq(type(uint256).max, dUSDEngine.getHealthFactor(USER));
    }

    function testLiquidateShouldRevertIfLiquidatorsHealthFactorIsBroken()
        public
        depositCollateral(USER, 1, AMOUNT_COLLATERAL)
        mintDUSD(USER, 1, MINT_DUSD_STARTING)
    {
        depositCollateralMultiplier(LIQUIDATOR, 2, AMOUNT_COLLATERAL);
        mintDUSDMultiplier(LIQUIDATOR, 2, MINT_DUSD_STARTING);
        int256 ETH_USD_PRICE_FEED_UPDATED_ANSWER = 1800e8;
        MockV3Aggregator(ethToUsdPriceFeed).updateAnswer(ETH_USD_PRICE_FEED_UPDATED_ANSWER);
        uint256 liquidatorHealthFactor = dUSDEngine.calculateHeathFactor(
            dUSDEngine.getAccountCollateralValueInUSD(LIQUIDATOR), 2 * MINT_DUSD_STARTING
        );

        uint256 debtToRecover = 10000 ether;
        vm.startPrank(LIQUIDATOR);
        dUSDtoken.approve(address(dUSDEngine), debtToRecover);

        vm.expectRevert(
            abi.encodeWithSelector(DUSDEngine.DUSDEngine__HealthFactorIsBroken.selector, liquidatorHealthFactor)
        );
        dUSDEngine.liquidate(weth, USER, debtToRecover);
        vm.stopPrank();
    }
}
