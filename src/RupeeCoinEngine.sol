// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {RupeeCoin} from "./RupeeCoin.sol";
import {IPriceFeedsAggregator} from "./interface/IPriceFeedsAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract RupeeCoinEngine {
    // Errors
    error RupeeCoinEngine__amountShouldBeMoreThanZero();
    error RupeeCoinEngine__tokenAndPriceFeedsShouldBeOfSameLength();
    error RupeeCoinEngine__tokenNotAllowedForCollateral();
    error RupeeCoinEngine__addressShouldNotBeZero();
    error RupeeCoinEngine__collateralDepositionFailed();
    error RupeeCoinEngine__cantCalculateHealthFactorAsCoinMintedIsZero();
    error RupeeCoinEngine__healthFactorIsBroken(uint256 healthFactor);
    error RupeeCoinEngine__mintFailed();

    // State Variables
    RupeeCoin private immutable i_coin;
    mapping(address token => address priceFeeds) private s_priceFeed;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 rupeeCoinMinted) private s_coinMinted;
    address[] private s_collateralTokens;

    uint256 private constant MAX_DECIMALS = 18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;


    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event RupeeCoinMinted(address indexed user, uint256 indexed amount);

    // Modifiers
    modifier onlyAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert RupeeCoinEngine__tokenNotAllowedForCollateral();
        }
        _;
    }

    modifier amountMoreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert RupeeCoinEngine__amountShouldBeMoreThanZero();
        }
        _;
    }

    // Constructor
    constructor(address rupeeCoinAddress, address[] memory tokens, address[] memory priceFeeds) {
        if (tokens.length != priceFeeds.length) {
            revert RupeeCoinEngine__tokenAndPriceFeedsShouldBeOfSameLength();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0) || priceFeeds[i] == address(0)) {
                revert RupeeCoinEngine__addressShouldNotBeZero();
            }

            s_priceFeed[tokens[i]] = priceFeeds[i];
            s_collateralTokens.push(tokens[i]);
        }

        i_coin = RupeeCoin(rupeeCoinAddress);
    }


    // External Functions
    function depositCollateralAndMintCoin() external {

    }

    function depositCollateral(address token, uint256 amount) external onlyAllowedToken(token) amountMoreThanZero(amount) {
        s_collateralDeposited[msg.sender][token] += amount;

        emit CollateralDeposited(msg.sender, token, amount);
        (bool success) = IERC20(token).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert RupeeCoinEngine__collateralDepositionFailed();
        }
    }

    function mintCoin(uint256 amount) external amountMoreThanZero(amount) {
        s_coinMinted[msg.sender] += amount;

        revertIfHealthFactorIsBroken(msg.sender);

        emit RupeeCoinMinted(msg.sender, amount);
        (bool success) = i_coin.mint(msg.sender, amount);

        if (!success) {
            revert RupeeCoinEngine__mintFailed();
        }
    }

    function redeemCollateral() external {

    }

    function burnCoinAndRedeemCollateral() external {

    }

    function burnCoin() external {

    }
    
    function liquidate() external {

    }



    // INTERNAL & PRIVATE VIEW / PURE
    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert RupeeCoinEngine__healthFactorIsBroken(userHealthFactor);
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalCollateralDeposited, uint256 totalRupeeCoinMinted) = getUserAccountInfo(user);

        if (totalRupeeCoinMinted == 0) {
            revert RupeeCoinEngine__cantCalculateHealthFactorAsCoinMintedIsZero();
        }

        uint256 thresholdCollateral = (totalCollateralDeposited * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (thresholdCollateral * PRECISION) / totalRupeeCoinMinted;
    }


    // EXTERNAL AND PUBLIC VIEW / PURE
    function getUserAccountInfo(address user) public view returns (uint256 totalCollateralDeposited, uint256 totalRupeeCoinMinted) {
        totalCollateralDeposited = getTotalCollateralDepositedBy(user);
        totalRupeeCoinMinted = s_coinMinted[user];
    }

    function getTotalCollateralDepositedBy(address user) public view returns (uint256) {
        uint256 userCollateralDeposited = 0;

        uint256 totalCollateralTokens = s_collateralTokens.length;

        for (uint256 i = 0; i < totalCollateralTokens; i++) {
            address token = s_collateralTokens[i];
            uint256 userAmountDeposited = s_collateralDeposited[user][token];

            userCollateralDeposited += getINRValue(token, userAmountDeposited);
        }

        return userCollateralDeposited;
    }

    function getINRValue(address token, uint256 amount) public view onlyAllowedToken(token) returns (uint256) {
        address priceFeeds = s_priceFeed[token];
        (, uint256 price) = IPriceFeedsAggregator(priceFeeds).latestRoundData();
        uint256 additionalDecimals = MAX_DECIMALS - IPriceFeedsAggregator(priceFeeds).decimals();
        uint256 additionalFeedPrecision = 10 ** additionalDecimals;

        return ((price * additionalFeedPrecision) * amount) / PRECISION;
    }
}