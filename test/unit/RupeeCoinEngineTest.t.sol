// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRupeeCoin} from "../../script/DeployRupeeCoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {RupeeCoin} from "../../src/RupeeCoin.sol";
import {RupeeCoinEngine} from "../../src/RupeeCoinEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockPriceFeedsAggregator} from "../mocks/MockPriceFeedsAggregator.sol";

contract RupeeCoinEngineTest is Test {
    RupeeCoin rupeeCoin;
    RupeeCoinEngine rupeeCoinEngine;
    HelperConfig helperConfig;

    address user = makeAddr("user");
    address liquidator = makeAddr("liquidator");
    address weth;
    address wbtc;
    address ethPriceFeed;
    address btcPriceFeed;
    uint256 private constant START_BALANCE = 10 ether;
    uint256 private constant START_WETH_BALANCE = 20e18;
    uint256 private constant START_WBTC_BALANCE = 20e18;
    uint256 private constant COLLATERAL_AMOUNT = 10e18;
    uint256 private constant RUPEE_COIN_MINT_AMT = 10000e18;
    uint256 private constant ETH_INR_PRICE = 150000e8;
    uint256 private constant BTC_INR_PRICE = 2372000e8;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed token, address indexed from, address indexed to, uint256 amount);
    event RupeeCoinMinted(address indexed user, uint256 indexed amount);
    event RupeeCoinBurnt(address indexed onBehalfOf, address indexed from, uint256 indexed amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 indexed improvedHealthFactor);

    function setUp() external {
        DeployRupeeCoin deployRupeeCoin = new DeployRupeeCoin();

        (rupeeCoin, rupeeCoinEngine, helperConfig) = deployRupeeCoin.run();

        (weth, wbtc, ethPriceFeed, btcPriceFeed, ) = helperConfig.networkConfig();

        ERC20Mock(weth).mint(user, START_WETH_BALANCE);
        ERC20Mock(wbtc).mint(user, START_WBTC_BALANCE);
        ERC20Mock(weth).mint(liquidator, START_WETH_BALANCE);
        ERC20Mock(wbtc).mint(liquidator, START_WBTC_BALANCE);
        vm.deal(user, START_BALANCE);
        vm.deal(liquidator, START_BALANCE);
    }

    modifier approveAndDepositCollateral(address who) {
        vm.startPrank(who);

        IERC20(weth).approve(address(rupeeCoinEngine), COLLATERAL_AMOUNT);
        rupeeCoinEngine.depositCollateral(weth, COLLATERAL_AMOUNT);

        vm.stopPrank();

        _;
    }

    modifier mintRupeeCoin(address who) {
        vm.prank(who);
        rupeeCoinEngine.mintCoin(RUPEE_COIN_MINT_AMT);
        _;
    }

    modifier mintMaxRupeeCoin() {
        uint256 maxMintAmount = 750000e18;

        vm.prank(user);
        rupeeCoinEngine.mintCoin(maxMintAmount);

        _;
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] tokens;
    address[] priceFeeds;

    function test_Constructor_RevertsIfTokensAndPriceFeedsAreOfDiffSize() public {
        tokens.push(weth);
        tokens.push(wbtc);
        priceFeeds.push(ethPriceFeed);

        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__tokenAndPriceFeedsShouldBeOfSameLength.selector
        );

        new RupeeCoinEngine(address(rupeeCoin), tokens, priceFeeds);
    }

    function test_Constructor_ValuesAreSetUpCorrectly() public {
        address actualRupeeCoinAddress = rupeeCoinEngine.getRupeeCoin();
        address expectedRupeeCoinAddress = address(rupeeCoin);

        assertEq(actualRupeeCoinAddress, expectedRupeeCoinAddress);
    }

    
    //////////////////////////////
    // Deposit Collateral Tests //
    //////////////////////////////

    function test_DepositCollateralRevertsIfAmountPassedIsZero() public {
        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__amountShouldBeMoreThanZero.selector
        );

        rupeeCoinEngine.depositCollateral(weth, 0);
    }

    function test_DepositCollateralRevertsIfTokenNotAllowedAsCollateral() public {
        ERC20Mock attackToken = new ERC20Mock("Attack Token", "ATK", msg.sender, START_BALANCE);

        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__tokenNotAllowedForCollateral.selector
        );

        rupeeCoinEngine.depositCollateral(address(attackToken), COLLATERAL_AMOUNT);
    }

    function test_DepositCollateralRevertsIfUserNotApprovedTheBalance() public {
        vm.expectRevert("ERC20: insufficient allowance");

        vm.prank(user);
        rupeeCoinEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
    }

    function test_AllowsUserToDepositCollateral() public {
        vm.startPrank(user);

        IERC20(weth).approve(address(rupeeCoinEngine), COLLATERAL_AMOUNT);

        vm.expectEmit(true, true, true, false, address(rupeeCoinEngine));
        emit CollateralDeposited(user, weth, COLLATERAL_AMOUNT);

        rupeeCoinEngine.depositCollateral(weth, COLLATERAL_AMOUNT);

        vm.stopPrank();

        uint256 actualCollateralDeposited = rupeeCoinEngine.getUserCollateralDeposited(user, weth);
        uint256 engineCollateralAmount = IERC20(weth).balanceOf(address(rupeeCoinEngine));
        uint256 userBalance = IERC20(weth).balanceOf(user);

        assertEq(actualCollateralDeposited, COLLATERAL_AMOUNT);
        assertEq(engineCollateralAmount, COLLATERAL_AMOUNT);
        assertEq(userBalance, START_WETH_BALANCE - COLLATERAL_AMOUNT);
    }

    /////////////////////////
    // Get INR Value Tests //
    /////////////////////////

    function test_GetINRValueGivesCorrectResult() public {
        // 1 eth - 150,000 INR
        // 10 eth - 1,500,000 INR

        uint256 expectedInrAmount = 1500000e18;
        uint256 actualInrAmount = rupeeCoinEngine.getINRValue(weth, COLLATERAL_AMOUNT);

        assertEq(actualInrAmount, expectedInrAmount);
    }

    /////////////////////////
    // Health Factor Tests //
    /////////////////////////

    function test_healthFactorGivesCorrectResult() public approveAndDepositCollateral(user) mintRupeeCoin(user) {
        // user deposited 10 eth, which is equivalent to 1,500,000 INR
        // threshold collateral amount is 50% = 750,000 INR

        uint256 thresholdCollateralAmount = 750000e18;
        uint256 coinMinted = rupeeCoinEngine.getRupeeCoinMinted(user);
        uint256 expectedHealthFactor = (thresholdCollateralAmount * 1e18) / coinMinted;

        uint256 actualHealthFactor = rupeeCoinEngine.getHealthFactor(user);

        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function test_healthFactorGivesMaxHealthFactorIfNoRupeeCoinMinted() public approveAndDepositCollateral(user) {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFactor = rupeeCoinEngine.getHealthFactor(user);

        assertEq(actualHealthFactor, expectedHealthFactor);
    }


    ///////////////////////////
    // Mint Rupee Coin Tests //
    ///////////////////////////

    function test_MintCoinRevertsIfAmountIsZero() public {
        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__amountShouldBeMoreThanZero.selector
        );

        rupeeCoinEngine.mintCoin(0);
    }

    function test_MintCoinRevertsIfHealthFactorIsZero() public {
        uint256 expectedHealthFactor = 0;

        vm.expectRevert(
            abi.encodeWithSelector(RupeeCoinEngine.RupeeCoinEngine__healthFactorIsBroken.selector, expectedHealthFactor)
        );
        
        rupeeCoinEngine.mintCoin(RUPEE_COIN_MINT_AMT);
    }

    function test_MintCoinRevertsIfEnoughCollateralNotDeposited() public approveAndDepositCollateral(user) {
        // I deposited 10 eth, which is worth 1,500,000 INR
        // So corresponding to that I can get 50% of 1,500,000 INR
        // Which means I can get 750,000 Rupee Coins✨

        uint256 depositedThresholdAmount = 750000e18;
        uint256 mintAmount = 750000e18 + 1;
        uint256 healthFactor = (depositedThresholdAmount * 1e18) / (mintAmount);

        vm.expectRevert(
            abi.encodeWithSelector(RupeeCoinEngine.RupeeCoinEngine__healthFactorIsBroken.selector, healthFactor)
        );

        vm.prank(user);
        rupeeCoinEngine.mintCoin(mintAmount);
    }

    function test_MintCoinAllowsUserToMintRupeeCoin() public approveAndDepositCollateral(user) {
        // to test this we will mint the max amount possible
        uint256 maxMintAmount = 750000e18;

        vm.expectEmit(true, true, false, false, address(rupeeCoinEngine));
        emit RupeeCoinMinted(user, maxMintAmount);

        vm.prank(user);
        rupeeCoinEngine.mintCoin(maxMintAmount);

        uint256 actualUserRupeeCoinBalance = rupeeCoinEngine.getRupeeCoinMinted(user);
        uint256 mintedAmountInCoinContract = rupeeCoin.balanceOf(user);
        uint256 endingUserHealthFactor = rupeeCoinEngine.getHealthFactor(user);
        uint256 expectedUserHealthFactor = 1e18;

        assertEq(actualUserRupeeCoinBalance, maxMintAmount);
        assertEq(mintedAmountInCoinContract, maxMintAmount);
        assertEq(endingUserHealthFactor, expectedUserHealthFactor);
    }


    /////////////////////////////
    // Redeem Collateral Tests //
    /////////////////////////////

    function test_RedeemCollateralRevertsIfAmountIsZero() public approveAndDepositCollateral(user) {
        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__amountShouldBeMoreThanZero.selector
        );

        vm.prank(user);
        rupeeCoinEngine.redeemCollateral(weth, 0);
    }

    function test_RedeemCollateralRevertsIfTokenNotAllowedAsCollateral() public {
        ERC20Mock attackToken = new ERC20Mock("Attack Token", "ATK", msg.sender, START_BALANCE);

        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__tokenNotAllowedForCollateral.selector
        );

        rupeeCoinEngine.redeemCollateral(address(attackToken), COLLATERAL_AMOUNT);
    }

    function test_RedeemCollateralRevertsIfHealthFactorBreaks() public approveAndDepositCollateral(user) mintMaxRupeeCoin {
        uint256 depositedThresholdAmount = 750000e18;
        uint256 mintedCoinAmount = 750000e18;
        
        // Should revert even if we try to redeem 1 wei
        uint256 redeemAmount = 1 wei;

        uint256 expectedHealthFactor = ((depositedThresholdAmount - 1) * 1e18) / mintedCoinAmount;

        vm.expectRevert(
            abi.encodeWithSelector(RupeeCoinEngine.RupeeCoinEngine__healthFactorIsBroken.selector, expectedHealthFactor)
        );

        vm.prank(user);
        rupeeCoinEngine.redeemCollateral(weth, redeemAmount);
    }

    function test_redeemCollateralAllowsToWithdrawCollateral() public approveAndDepositCollateral(user) {
        vm.expectEmit(true, true, true, true, address(rupeeCoinEngine));
        emit CollateralRedeemed(weth, user, user, COLLATERAL_AMOUNT);

        vm.prank(user);
        rupeeCoinEngine.redeemCollateral(weth, COLLATERAL_AMOUNT);

        uint256 finalCollateralDeposited = rupeeCoinEngine.getUserCollateralDeposited(user, weth);
        uint256 finalWethBalance = IERC20(weth).balanceOf(user);

        assertEq(finalCollateralDeposited, 0);
        assertEq(finalWethBalance, START_WETH_BALANCE);
    }



    ///////////////////////////
    // Burn Rupee Coin Tests //
    ///////////////////////////

    function test_BurnCoin_RevertsIfAmountIsZero() public {
        vm.expectRevert(
            RupeeCoinEngine.RupeeCoinEngine__amountShouldBeMoreThanZero.selector
        );

        rupeeCoinEngine.burnCoin(0);
    }

    function test_BurnCoinAllowsUserToBurnRupeeCoin() public approveAndDepositCollateral(user) mintMaxRupeeCoin {
        uint256 mintAmount = 750000e18;

        vm.startPrank(user);

        rupeeCoin.approve(address(rupeeCoinEngine), mintAmount);

        vm.expectEmit(true, true, true, false, address(rupeeCoinEngine));
        emit RupeeCoinBurnt(user, user, mintAmount);

        rupeeCoinEngine.burnCoin(mintAmount);

        vm.stopPrank();

        uint256 userMintBalance = rupeeCoinEngine.getRupeeCoinMinted(user);
        uint256 userRupeeCoinBalance = rupeeCoin.balanceOf(user);

        assertEq(userMintBalance, 0);
        assertEq(userRupeeCoinBalance, 0);
    }

    /////////////////////////////////////
    // Get Token Amount From INR Tests //
    /////////////////////////////////////
    function test_TokenAmountIsCalculatedCorrectly() public {
        uint256 inrAmount = 70000e18;

        // As the price feeds amount for 1 eth is 150,000 INR
        // 150,000 INR = 1 eth
        // 70,000 INR = 0.466666666666666666 eth

        uint256 expectedTokenAmount = (1e18 * inrAmount) / (ETH_INR_PRICE * 1e10);
        uint256 actualTokenAmount = rupeeCoinEngine.getTokenAmountFromINR(weth, inrAmount);

        console.log(actualTokenAmount);

        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    /////////////////////
    // Liquidate Tests //
    /////////////////////

    function test_Liquidate_RevertsIfUserHealthFactorIsGood() public approveAndDepositCollateral(user) mintRupeeCoin(user) approveAndDepositCollateral(liquidator) mintRupeeCoin(liquidator) {
        uint256 debtToCover = RUPEE_COIN_MINT_AMT;

        // user deposited 10 eth, and minted 10,000 Rupee Coin
        // 10 eth - 1,500,000
        // threshold amount - 750,000 INR  
        uint256 thresholdCollateralAmount = 750000e18;
        uint256 expectedUserHealthFactor = (thresholdCollateralAmount * 1e18) / RUPEE_COIN_MINT_AMT;

        vm.expectRevert(
            abi.encodeWithSelector(RupeeCoinEngine.RupeeCoinEngine__healthFactorIsGood.selector, expectedUserHealthFactor)
        );

        vm.prank(liquidator);
        rupeeCoinEngine.liquidate(user, weth, debtToCover);
    }

    function test_Liquidate_AllowsLiquidatorToLiquidateUser() public approveAndDepositCollateral(user) mintMaxRupeeCoin() {
        // Now let's decrease the price of eth, as a result of which user health factor will get decresed
        // and it will be below min health factor

        uint256 newPrice = 140000e8;
        MockPriceFeedsAggregator(ethPriceFeed).updateRoundData(newPrice, block.timestamp);
        uint256 mintAmount = 750000e18;
        uint256 debtToCover = mintAmount;

        vm.startPrank(liquidator);

        uint256 collateralAmount = 15 ether;
        IERC20(weth).approve(address(rupeeCoinEngine), collateralAmount);
        rupeeCoinEngine.depositCollateral(weth, collateralAmount);
        rupeeCoinEngine.mintCoin(mintAmount);

        rupeeCoin.approve(address(rupeeCoinEngine), debtToCover);

        vm.expectEmit(true, true, true, false, address(rupeeCoinEngine));
        emit Liquidated(user, liquidator, type(uint256).max);

        rupeeCoinEngine.liquidate(user, weth, debtToCover);

        vm.stopPrank();
    }
}