// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {IRTEngine} from "../../src/IRTEngine.sol";
import {IndianRupeeCoin} from "../../src/IndianRupeeCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    IRTEngine internal irte;
    IndianRupeeCoin internal irt;

    ERC20Mock internal weth;
    ERC20Mock internal wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 internal constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(IRTEngine _irte, IndianRupeeCoin _irt) {
        irte = _irte;
        irt = _irt;

        address[] memory collateralTokens = irte.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(
            irte.getCollateralTokenPriceFeed(address(weth))
        );
    }

    // -------------------------
    // 🟢 MINT IRT FUNCTION
    // -------------------------
    function mintIrt(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;

        address user = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];

        (uint256 totalMinted, uint256 collateralValueInUsd) = irte
            .getAccountInformation(user);

        // Half collateral value allowed to mint
        if (collateralValueInUsd <= totalMinted * 2) return;
        uint256 maxMint = (collateralValueInUsd / 2) - totalMinted;

        amount = bound(amount, 1, maxMint);
        if (amount == 0) return;

        vm.startPrank(user);
        try irte.mintIrt(amount) {
            timesMintIsCalled++;
        } catch {
            // Skip failed mint, don't revert fuzz
        }
        vm.stopPrank();
    }

    // -------------------------
    // 🟢 DEPOSIT COLLATERAL
    // -------------------------
    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1e18, MAX_DEPOSIT_SIZE);

        address user = msg.sender;
        collateral.mint(user, amountCollateral);

        vm.startPrank(user);
        collateral.approve(address(irte), amountCollateral);
        try irte.depositCollateral(address(collateral), amountCollateral) {
            usersWithCollateralDeposited.push(user);
        } catch {
            // ignore failed deposits to keep fuzz running
        }
        vm.stopPrank();
    }

    // -------------------------
    // 🟢 REDEEM COLLATERAL
    // -------------------------
    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        if (usersWithCollateralDeposited.length == 0) return;
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        address user = usersWithCollateralDeposited[
            collateralSeed % usersWithCollateralDeposited.length
        ];

        uint256 maxCollateral = irte.getCollateralBalanceOfUser(
            user,
            address(collateral)
        );
        if (maxCollateral == 0) return;

        amountCollateral = bound(amountCollateral, 1, maxCollateral);

        vm.startPrank(user);
        try
            irte.redeemCollateral(address(collateral), amountCollateral)
        {} catch {}
        vm.stopPrank();
    }

    // function updateCollateralPrice(uint256 newPrice) public {
    // int256 newPriceInt = int256(uint256(newPrice));
    // ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // -------------------------
    // 🧠 HELPER
    // -------------------------
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        return collateralSeed % 2 == 0 ? weth : wbtc;
    }
}
