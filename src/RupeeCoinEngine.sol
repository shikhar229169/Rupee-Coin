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
    error RupeeCoinEngine__healthFactorIsBroken(uint256 healthFactor);
    error RupeeCoinEngine__mintFailed();
    error RupeeCoinEngine__redeemAmountExceedsBalance();
    error RupeeCoinEngine__reedemtionFailed();
    error RupeeCoinEngine__burnAmountExceedsMintedAmount();
    error RupeeCoinEngine__coinTransferFailed();
    error RupeeCoinEngine__healthFactorIsGood(uint256 healthFactor);
    error RupeeCoinEngine__userHealthFactorNotImproved();

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
    uint256 private constant LIQUIDATION_BONUS = 5;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;


    // Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed token, address indexed from, address indexed to, uint256 amount);
    event RupeeCoinMinted(address indexed user, uint256 indexed amount);
    event RupeeCoinBurnt(address indexed onBehalfOf, address indexed from, uint256 indexed amount);

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
    function depositCollateralAndMintCoin(address token, uint256 collateralAmount, uint256 rupeeCoinAmount) external {
        depositCollateral(token, collateralAmount);
        mintCoin(rupeeCoinAmount);
    }

    function depositCollateral(address token, uint256 amount) public onlyAllowedToken(token) amountMoreThanZero(amount) {
        s_collateralDeposited[msg.sender][token] += amount;

        emit CollateralDeposited(msg.sender, token, amount);
        (bool success) = IERC20(token).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert RupeeCoinEngine__collateralDepositionFailed();
        }
    }

    function mintCoin(uint256 amount) public amountMoreThanZero(amount) {
        s_coinMinted[msg.sender] += amount;

        revertIfHealthFactorIsBroken(msg.sender);

        emit RupeeCoinMinted(msg.sender, amount);
        (bool success) = i_coin.mint(msg.sender, amount);

        if (!success) {
            revert RupeeCoinEngine__mintFailed();
        }
    }

    function redeemCollateral(address token, uint256 amount) public onlyAllowedToken(token) amountMoreThanZero(amount) {
        _redeemCollateral(token, msg.sender, msg.sender, amount);
        
        if (s_coinMinted[msg.sender] > 0) {
            revertIfHealthFactorIsBroken(msg.sender);
        }
    }

    function burnCoinAndRedeemCollateral(address token, uint256 collateralReedemAmount, uint256 burnAmount) external {
        burnCoin(burnAmount);
        redeemCollateral(token, collateralReedemAmount);
    }

    function burnCoin(uint256 amount) public amountMoreThanZero(amount) {
        _burnCoin(msg.sender, msg.sender, amount);
    }
    
    function liquidate(address user, address token, uint256 debtToCover) external {
        revertIfHealthFactorIsBroken(msg.sender);

        uint256 userStartingHealthFactor = _healthFactor(user);

        if (userStartingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert RupeeCoinEngine__healthFactorIsGood(userStartingHealthFactor);
        }

        uint256 reward = getTokenAmountFromINR(token, debtToCover);
        uint256 bonus = (reward * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalReward = reward + bonus;

        _redeemCollateral(token, user, msg.sender, totalReward);
        _burnCoin(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= userStartingHealthFactor) {
            revert RupeeCoinEngine__userHealthFactorNotImproved();
        }
    }


    // PRIVATE 

    function _redeemCollateral(address token, address from, address to, uint256 amount) private {
        if (amount > s_collateralDeposited[from][token]) {
            revert RupeeCoinEngine__redeemAmountExceedsBalance();
        }

        s_collateralDeposited[from][token] -= amount;

        emit CollateralRedeemed(token, from, to, amount);
        (bool success) = IERC20(token).transfer(to, amount);

        if (!success) {
            revert RupeeCoinEngine__reedemtionFailed();
        }
    }

    function _burnCoin(address onBehalfOf, address from, uint256 amount) private {
        if (amount > s_coinMinted[onBehalfOf]) {
            revert RupeeCoinEngine__burnAmountExceedsMintedAmount();
        }

        s_coinMinted[onBehalfOf] -= amount;

        (bool success) = i_coin.transferFrom(from, address(this), amount);

        if (!success) {
            revert RupeeCoinEngine__coinTransferFailed();
        }

        emit RupeeCoinBurnt(onBehalfOf, from, amount);
        i_coin.burn(amount);
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
            return type(uint256).max;
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

    function getTokenAmountFromINR(address token, uint256 inrValue) public view onlyAllowedToken(token) returns (uint256) {
        address priceFeeds = s_priceFeed[token];

        (, uint256 price) = IPriceFeedsAggregator(priceFeeds).latestRoundData();
        uint256 additionalDecimals = MAX_DECIMALS - IPriceFeedsAggregator(priceFeeds).decimals();
        uint256 additionalFeedPrecision = 10 ** additionalDecimals;

        return (inrValue * PRECISION) / (price * additionalFeedPrecision);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getRupeeCoin() external view returns (address) {
        return address(i_coin);
    }

    function getPriceFeedAddress(address token) external view returns (address) {
        return s_priceFeed[token];
    }

    function getUserCollateralDeposited(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getRupeeCoinMinted(address user) external view returns (uint256) {
        return s_coinMinted[user];
    }

    function getCollateralTokenAtIdx(uint256 idx) external view returns (address) {
        return s_collateralTokens[idx];
    }

    function getAllCollateralTokenAddresses() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getMaxDecimals() external pure returns (uint256) {
        return MAX_DECIMALS;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}