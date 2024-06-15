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

import {DUSD} from "./DUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DUSDEngine
 * @author Sarvesh Agarwal (sarveshagl1327@gmail.com) github- sarvesh1327
 * This system is designed to be as minimal as possible, and have the tokens maintain
 * a 1 token == $1 peg
 * This stablecoin has following properties:
 * - Exogenous Collateral
 * - Dollar pegged
 * - Algorithmic Stable
 * This is similar to DAI if DAI had no goverance, no fees and was only backed by WETH
 * and WBTC,
 *
 * DUSD system should always be "overcollateralized". At no point should all the
 * collateral<= allDUSD value in $.
 * @notice This contract is the core of DUSD system, it handle all the logic for mining
 * and redeeming DUSD, as well as depositing and withdrawing collateral
 * @notice This contract is loosely based on MakerDAO DSS(DAI) system.
 */
contract DUSDEngine is ReentrancyGuard {
    //Errors
    error DUSDEngine__MustBeMoreThanZero();
    error DUSDEngine__TokenAddressedAndPriceFeedAddressesLengthMustBeSame();
    error DUSDEngine__TokenNotAllowed();
    error DUSDEngine__CollateralTransferFailed();
    error DUSDEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DUSDEngine__MintFailed();
    error DUSDEngine__TransferFailed();
    error DUSDEngine__HealthFactorNotBroken();
    error DUSDEngine__HealthFactorNotImproved();

    //State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    DUSD private immutable i_DUSD;
    mapping(address token => address priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDUSDMinted) private s_amountMinted;

    address[] private s_collateralTokens;

    //Events
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed tokenCollateralAddress, uint256 amount
    );

    //Modifiers

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DUSDEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DUSDEngine__TokenNotAllowed();
        }
        _;
    }

    //Functions

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address DUSDAdress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DUSDEngine__TokenAddressedAndPriceFeedAddressesLengthMustBeSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_collateralTokens.push(tokenAddresses[i]);
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_DUSD = DUSD(DUSDAdress);
    }

    //External functions
    /**
     * @notice This function allows user to deposit collateral and mint DUSD tokens in one transaction
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDUSDToMint Amount of DUSD token to mint
     * @notice User must have more collateral value more than the minimum threshold to mint DUSD
     */
    function depositCollateralAndMintDUSD(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDUSDToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDUSD(amountDUSDToMint);
    }

    /**
     *
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DUSDEngine__CollateralTransferFailed();
        }
    }

    /**
     * @notice User's Health factor should be more than 1 after redeeming collateral
     * CEI
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateralAddress Token address of the token to be redeemed
     * @param amountCollateral Amount of collateral User want to Redeem
     * @param amountDUSDToBurn Amount of the DUSD token User want to redeem collateral with
     * This function redeems Collateral and burn DUSD tokens
     */
    function redeemCollateralForDUSD(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDUSDToBurn)
        external
    {
        burnDUSD(amountDUSDToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     *
     * @param amountDUSDToMint Amount of DUSD token to mint
     * @notice User must have more collateral value more than the minimum threshold
     */
    function mintDUSD(uint256 amountDUSDToMint) public moreThanZero(amountDUSDToMint) nonReentrant {
        s_amountMinted[msg.sender] += amountDUSDToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_DUSD.mint(msg.sender, amountDUSDToMint);
        if (!minted) {
            revert DUSDEngine__MintFailed();
        }
    }

    /**
     * @param amount Amount of DUSD user want to burn
     */
    function burnDUSD(uint256 amount) public moreThanZero(amount) {
        _burnDUSD(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateralAddress Address of the ERC20 to liquidate the user
     * @param user User to be liquidated(Their health factor should be below min health factor)
     * @param debtToRecover Amount of DUSD token which will be recovered
     * @notice You can partially liquidate a user
     * @notice You will get liquidate bonus to liquidate a user
     * @notice The function assumes the protocol will be atleast 200% overcollaterallized in order
     * for this to work
     * Follows CEI
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToRecover)
        external
        moreThanZero(debtToRecover)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DUSDEngine__HealthFactorNotBroken();
        }

        uint256 tokenAmountFromDebtRecovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToRecover);
        uint256 bonusCollateral = (tokenAmountFromDebtRecovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtRecovered + bonusCollateral;
        _burnDUSD(user, msg.sender, debtToRecover);
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor<=startingUserHealthFactor){
            revert DUSDEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    //////Private Functions

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        internal
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DUSDEngine__TransferFailed();
        }
    }

    function _burnDUSD(address onBehalfOf, address dUSDfrom, uint256 amountDUSDToBurn) internal{
        s_amountMinted[onBehalfOf] -= amountDUSDToBurn;
        bool success = i_DUSD.transferFrom(dUSDfrom, address(this), amountDUSDToBurn);
        if (!success) {
            revert DUSDEngine__TransferFailed();
        }
        i_DUSD.burn(amountDUSDToBurn);
    }

    /////Private and Internal View Functions
    /**
     *
     * @param user address of the user
     * @return totalDUSDMinted total DUSD minted by User
     * @return totalCollateralValue total collateral in USD deposited by the user
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDUSDMinted, uint256 totalCollateralValue)
    {
        totalDUSDMinted = s_amountMinted[user];
        totalCollateralValue = getAccountCollateralValueInUSD(user);
    }

    /**
     *
     * @param user Address of the user
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDUSDMinted, uint256 totalCollateralValue) = _getAccountInformation(user);
        return _calculateHealthFactor(totalCollateralValue, totalDUSDMinted);
    }


    function _calculateHealthFactor(uint256 collateralValue, uint256 dUSDMinted) private pure returns (uint256){
        uint256 collateralAdjustedForThreshold = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        if(dUSDMinted<=0){
            return type(uint256).max;
        }
        return (collateralAdjustedForThreshold * PRECISION) / dUSDMinted;
    }

    /**
     *
     * @param user User for whom the health factor is needed to be checked
     * @notice It will compare User's collateral with the total amount user can mint
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DUSDEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    //Public view and Pure funcrtions

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 collateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount == 0) {
                continue;
            }
            collateralValueInUSD += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address tokenAddress, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address tokenAddress, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralAmount(address tokenCollateralAddress, address user) public view returns (uint256){
        return s_collateralDeposited[user][tokenCollateralAddress];
    }

    function getCollatrealTokens() public view returns(address[] memory){
        return s_collateralTokens;
    }

    function getAccountInformation(address user) external view returns(uint256 totalDUSDMinted, uint256 totalCollateralValue){
       (totalDUSDMinted, totalCollateralValue)= _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns(uint256 healthFactor) {
        healthFactor = _healthFactor(user);
    }

    function calculateHeathFactor(uint256 collateralValue, uint256 dUSDMinted) public pure returns(uint256){
        return _calculateHealthFactor(collateralValue, dUSDMinted);
    }
}
