// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockPriceFeedsAggregator} from "../test/mocks/MockPriceFeedsAggregator.sol";

contract HelperConfig is Script{

    // THe ethPriceFeed and btcPriceFeed addresses are the contract addresses which provides their INR amount
    struct NetworkConfig {
        address weth;
        address wbtc;
        address ethPriceFeed;
        address btcPriceFeed;
        uint256 deployerKey;
    }

    NetworkConfig public networkConfig;
    uint256 private constant DECIMALS = 8;
    uint256 private constant ETH_INR_PRICE = 150000e8;
    uint256 private constant BTC_INR_PRICE = 2372000e8;

    constructor() {
        if (block.chainid == 11155111) {
            networkConfig = getSepoliaConfig();
        }
        else {
            networkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            ethPriceFeed: 0x38c6D12DC5aee7A804e5Ce4CFef47a0a684C829d,
            btcPriceFeed: 0xf5600144B2A0c9b02812A6daE790dA1129c4b7df,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (networkConfig.weth != address(0)) {
            return networkConfig;
        }

        vm.startBroadcast();

        ERC20Mock weth = new ERC20Mock("wETH", "wETH", msg.sender, 2000e18);
        ERC20Mock wbtc = new ERC20Mock("wBTC", "wBTC", msg.sender, 2000e18);

        MockPriceFeedsAggregator ethPriceFeed = new MockPriceFeedsAggregator(DECIMALS, ETH_INR_PRICE);
        MockPriceFeedsAggregator btcPriceFeed = new MockPriceFeedsAggregator(DECIMALS, BTC_INR_PRICE);

        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(weth),
            wbtc: address(wbtc),
            ethPriceFeed: address(ethPriceFeed),
            btcPriceFeed: address(btcPriceFeed),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
    }
}