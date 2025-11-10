// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployIRT} from "../../script/DeployIRT.s.sol";
import {IndianRupeeCoin} from "../../src/IndianRupeeCoin.sol";
import {IRTEngine} from "../../src/IRTEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract IRTEngineTest is Test {
    DeployIRT deployer;
    IndianRupeeCoin irt;
    IRTEngine irte;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant amountToMint = 100 ether;
    uint256 public constant amountCollateral = 20000 ether;

    function setUp() public {
        deployer = new DeployIRT();
        (irt, irte, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor Tests //
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthMismatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(IRTEngine.IRTEngine__TokenAddressesAndPriceAddressesMustBeSameLength.selector);

        new IRTEngine(tokenAddresses, priceFeedAddresses, address(irt));
    }

    // PRICE TESTS //

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = irte.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = irte.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    // depositCollateral Test //

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(irte), AMOUNT_COLLATERAL);

        vm.expectRevert(IRTEngine.IRTEngine__NeedsMoreThanZero.selector);
        irte.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock sexToken = new ERC20Mock("SEX", "SEX", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(IRTEngine.IRTEngine__NotAllowedToken.selector);
        irte.depositCollateral(address(sexToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(irte), AMOUNT_COLLATERAL);
        irte.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalIrtMinted, uint256 collateralValueInUsd) = irte.getAccountInformation(USER);

        uint256 expectedTotalIrtMinted = 0;
        uint256 expectedDepositAmount = irte.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalIrtMinted, expectedTotalIrtMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertIfRedeemZeroCollateral() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(IRTEngine.IRTEngine__NeedsMoreThanZero.selector);
        irte.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral {
        vm.startPrank(USER);
        irte.redeemCollateral(weth, AMOUNT_COLLATERAL / 2);
        vm.stopPrank();

        (uint256 totalIrtMinted, uint256 collateralValueInUsd) = irte.getAccountInformation(USER);
        assertEq(totalIrtMinted, 0);
        assertEq(collateralValueInUsd, irte.getUsdValue(weth, AMOUNT_COLLATERAL / 2));
    }

    function testBurnIrtUpdatesBalance() public depositCollateral {
        vm.startPrank(USER);
        irte.mintIrt(1 ether);
        irt.approve(address(irte), 1 ether);
        irte.burnIrt(1 ether);
        vm.stopPrank();

        assertEq(irt.balanceOf(USER), 0);
    }

    function testGetUserCollateralValue() public depositCollateral {
        uint256 value = irte.getAccountCollateralValue(USER);
        assertGt(value, 0);
    }

    function testLiquidateFailsIfHealthy() public depositCollateral {
        vm.startPrank(USER);
        irte.mintIrt(1 ether);
        vm.stopPrank();

        vm.expectRevert(IRTEngine.IRTEngine__HealthFactorOk.selector);
        irte.liquidate(USER, weth, 1 ether);
    }

    function testRevertIfZeroAmountMint() public {
        vm.startPrank(USER);
        vm.expectRevert(IRTEngine.IRTEngine__NeedsMoreThanZero.selector);
        irte.mintIrt(0);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedIrt() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(irte), amountCollateral);
        irte.depositCollateralAndMintIrt(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }
}
