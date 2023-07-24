// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {RupeeCoin} from "../src/RupeeCoin.sol";
import {RupeeCoinEngine} from "../src/RupeeCoinEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployRupeeCoin is Script {
    address[] tokens;
    address[] priceFeedAddresses;

    function run() external returns (RupeeCoin, RupeeCoinEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address weth, address wbtc, address ethPriceFeed, address btcPriceFeed, uint256 deployerKey) = helperConfig.networkConfig();

        tokens = [weth, wbtc];
        priceFeedAddresses = [ethPriceFeed, btcPriceFeed];

        vm.startBroadcast(deployerKey);

        RupeeCoin rupeeCoin = new RupeeCoin();
        RupeeCoinEngine rupeeCoinEngine = new RupeeCoinEngine(address(rupeeCoin), tokens, priceFeedAddresses);
        rupeeCoin.transferOwnership(address(rupeeCoinEngine));

        vm.stopBroadcast();

        return (rupeeCoin, rupeeCoinEngine, helperConfig);
    }
}
