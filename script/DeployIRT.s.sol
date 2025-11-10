// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IndianRupeeCoin} from "../src/IndianRupeeCoin.sol";
import {IRTEngine} from "../src/IRTEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployIRT is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (IndianRupeeCoin, IRTEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        IndianRupeeCoin irt = new IndianRupeeCoin(deployer);
        IRTEngine engine = new IRTEngine(tokenAddresses, priceFeedAddresses, address(irt));
        vm.stopBroadcast();

        // transfer ownership from deployer → engine
        vm.startBroadcast(deployerKey);
        irt.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (irt, engine, config);
    }
}
