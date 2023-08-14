// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployRupeeCoin} from "../../script/DeployRupeeCoin.s.sol";
import {RupeeCoin} from "../../src/RupeeCoin.sol";
import {RupeeCoinEngine} from "../../src/RupeeCoinEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    RupeeCoin rupeeCoin;
    RupeeCoinEngine rupeeCoinEngine;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        DeployRupeeCoin deployer = new DeployRupeeCoin();
        (rupeeCoin, rupeeCoinEngine, helperConfig) = deployer.run();
        (weth, wbtc, , , ) = helperConfig.networkConfig();
        handler = new Handler(rupeeCoin, rupeeCoinEngine);

        targetContract(address(handler));
    }

    function invariant_protocolHaveMoreDepositedThanMintedAmount() public view {
        uint256 totalRupeeCoinSupply = rupeeCoin.totalSupply();
        
        uint256 engineEth = IERC20(weth).balanceOf(address(rupeeCoinEngine));
        uint256 engineBtc = IERC20(wbtc).balanceOf(address(rupeeCoinEngine));

        uint256 ethInr = rupeeCoinEngine.getINRValue(weth, engineEth);
        uint256 btcInr = rupeeCoinEngine.getINRValue(wbtc, engineBtc);

        assert((ethInr + btcInr) >= totalRupeeCoinSupply);

        console.log("Deposit Called -", handler.depositCalled());
        console.log("Redeem Called for User -", handler.redeemCalledForUser());
        console.log("Redeem Called for msg.sender -", handler.redeemCalledForMsgSender());
        console.log("Mint Called -", handler.mintCalled());
        console.log("ETH -", ethInr);
        console.log("BTC -", btcInr);
        console.log("Supply -", totalRupeeCoinSupply);
    }
}