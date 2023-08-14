// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {RupeeCoin} from "../../src/RupeeCoin.sol";
import {RupeeCoinEngine} from "../../src/RupeeCoinEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Handler is Test {
    RupeeCoin rupeeCoin;
    RupeeCoinEngine rupeeCoinEngine;
    address[] tokens;
    uint256 maxTokenAmount = type(uint96).max;
    address[] users;
    uint256 public mintCalled;
    uint256 public depositCalled;
    uint256 public redeemCalledForUser;
    uint256 public redeemCalledForMsgSender;

    constructor(RupeeCoin _rupeeCoin, RupeeCoinEngine _rupeeCoinEngine) {
        rupeeCoin = _rupeeCoin;
        rupeeCoinEngine = _rupeeCoinEngine;
        tokens = rupeeCoinEngine.getAllCollateralTokenAddresses();
    }

    function depositCollateral(uint256 tokenSeed, uint256 amountToDeposit) public {
        address token = getTokenFromSeed(tokenSeed);
        amountToDeposit = bound(amountToDeposit, 1, maxTokenAmount);

        vm.startPrank(msg.sender);

        ERC20Mock(token).mint(msg.sender, amountToDeposit);
        IERC20(token).approve(address(rupeeCoinEngine), amountToDeposit);
        rupeeCoinEngine.depositCollateral(token, amountToDeposit);

        vm.stopPrank();

        users.push(msg.sender);
        depositCalled++;
    }

    function redeemCollateral(uint256 userSeed, uint256 tokenSeed, uint256 amountToWithdraw) public {
        address token = getTokenFromSeed(tokenSeed);
        address user;
        if (users.length == 0) {
            user = msg.sender;
        }
        else {
            user = getUserFromSeed(userSeed);
        }

        uint256 userCollateral = rupeeCoinEngine.getUserCollateralDeposited(user, token);

        (uint256 collateralDeposited, uint256 coinMinted) = rupeeCoinEngine.getUserAccountInfo(user);
        uint256 collateralRequired = 2 * coinMinted;
        uint256 canTakeInInr = collateralDeposited - collateralRequired;

        uint256 maxRedeemtionPossible = rupeeCoinEngine.getTokenAmountFromINR(token, canTakeInInr);

        if (userCollateral < maxRedeemtionPossible) {
            maxRedeemtionPossible = userCollateral;
        }
        
        amountToWithdraw = bound(amountToWithdraw, 0, maxRedeemtionPossible);

        if (amountToWithdraw == 0) {
            return;
        }

        vm.prank(user);
        rupeeCoinEngine.redeemCollateral(token, amountToWithdraw);

        if (users.length == 0) {
            redeemCalledForMsgSender++;
        }
        else {
            redeemCalledForUser++;
        }
    }

    function mintRupeeCoin(uint256 userSeed, uint256 mintAmount) public {
        if (users.length == 0) {
            return;
        }
        address user = getUserFromSeed(userSeed);

        (uint256 collateralDeposited, uint256 coinMinted) = rupeeCoinEngine.getUserAccountInfo(user);
        uint256 maxMaxCoinMintPossible = (collateralDeposited * 50) / 100;
        uint256 maxMintPossible = maxMaxCoinMintPossible - coinMinted;


        mintAmount = bound(mintAmount, 0, maxMintPossible);
        if (mintAmount == 0) {
            return;
        }

        vm.prank(user);
        rupeeCoinEngine.mintCoin(mintAmount);

        mintCalled++;
    }

    function getTokenFromSeed(uint256 tokenSeed) internal view returns (address) {
        return tokens[tokenSeed % tokens.length];
    }

    function getUserFromSeed(uint256 userSeed) internal view returns (address) {
        return users[userSeed % users.length];
    }
}