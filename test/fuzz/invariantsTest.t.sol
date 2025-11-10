// SPDX-License-Identifier: MIT

// Have Our Invariant aka properties

// What are our invariants?

// 1. The total supply of IRT should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployIRT} from "../../script/DeployIRT.s.sol";
import {IRTEngine} from "../../src/IRTEngine.sol";
import {IndianRupeeCoin} from "../../src/IndianRupeeCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployIRT deployer;
    IRTEngine irte;
    IndianRupeeCoin irt;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployIRT();
        (irt, irte, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        // targetContract(address(irte));
        handler = new Handler(irte, irt);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralThanTotalSupply() public {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (IRT)

        uint256 totalSupply = irt.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(irte));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(irte));

        uint256 wethValue = irte.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = irte.getUsdValue(wbtc, totalWbtcDeposited);

        

        assert(wethValue + wbtcValue >= totalSupply);
    }

    
}
