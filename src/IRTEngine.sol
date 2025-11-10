// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IndianRupeeCoin} from "./IndianRupeeCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title IRTEngine
 *    @author 0xAnvesaka Poison (Both are the same person)
 *
 *    The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 *
 *    This stablecoin has the properties:
 *    - Exogenous Collateral
 *    - Dollar Pegged
 *    - Algorithmically Stable
 *
 *   It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 *   Our IRT system should always be "overcolletralized". At no point, should the value of all collateral <= the $ backed value of all the IRT.
 *
 *   @notice This contract is the core of the IRT System. it handles all the logic for minting and redeeming IRT, as well
 *   as depositing & withdrawing collateral.
 *   @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract IRTEngine is ReentrancyGuard {
    // ERRORS //

    error IRTEngine__NeedsMoreThanZero();
    error IRTEngine__TokenAddressesAndPriceAddressesMustBeSameLength();
    error IRTEngine__NotAllowedToken();
    error IRTEngine__TransferFailed();
    error IRTEngine__BreaksHealthFactor(uint256 healthFactor);
    error IRTEngine__MintFailed();
    error IRTEngine__HealthFactorOk();
    error IRTEngine__HealthFactorNotImproved();

    // Types //
    using OracleLib for AggregatorV3Interface;

    // State Variables //
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountIrtToMinted) private s_IRTMinted;
    address[] private s_collateralTokens;

    IndianRupeeCoin private immutable i_irt;

    // Events //

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    // Modifier //

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert IRTEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert IRTEngine__NotAllowedToken();
        }
        _;
    }

    // Functions //
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address irtAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert IRTEngine__TokenAddressesAndPriceAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_irt = IndianRupeeCoin(irtAddress);
    }

    // External Functions //

    /**
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountIrtToMint The amount of decentralized stablecoin to mint
     * @notice this function will deposit your collateral and mint IRT in one transaction
     */

    function depositCollateralAndMintIrt(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountIrtToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintIrt(amountIrtToMint);
    }

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert IRTEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountIrtToBurn The amount of IRT to burn
     * This function burns IRT and redeems underlying collateral in one transaction
     */

    function redeemCollateralForIrt(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountIrtToBurn
    ) external {
        burnIrt(amountIrtToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // No need to check health factor here, since we just burned IRT
    }

    // In order to redeem collateral:
    // 1. health factor must be over 1 after collateral pulled
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice follows CEI
     * @param amountIrtToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintIrt(
        uint256 amountIrtToMint
    ) public moreThanZero(amountIrtToMint) nonReentrant {
        s_IRTMinted[msg.sender] += amountIrtToMint;
        // if they minted much more than their collateral then its gonna revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_irt.mint(msg.sender, amountIrtToMint);
        if (!success) {
            revert IRTEngine__MintFailed();
        }
    }

    function burnIrt(uint256 amount) public moreThanZero(amount) {
        _burnIrt(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // No Need for this but why not
    }

    /**
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of IRT you want to burn to improve the users health factor
     * @notice You can partially liquidate a user.
     * @notice you will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then
     * we wouldn't be able to incentivise the liquidators.
     *  For example, if the price of the collateral plummeted before anyone could be
     * liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // need to check health factor is the user
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert IRTEngine__HealthFactorOk();
        }
        // We want to burn thier IRT "debt"
        // And take their collateral
        // Bad User: $140 ETH, $100 IRT
        // debtToCover = $100
        // $100 of IRT == ??

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // And give them a 10% bonus
        // So we are giving the liquaidator $110 of WETH for $100 IRT
        // We should implement a feature to liquidate in the event the protocol is insolvent.

        // 0.05 * 0.1 = 0.005. getting 0.055 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralToRedeem
        );
        // We need to burn The Irt from the liquidator
        _burnIrt(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert IRTEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_irt);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    // Private And Internal View functions //

    /**
     * @dev low-level internal function, do not call unless the function calling it is
     * checking for health factors being broken
     */

    function _burnIrt(
        uint256 amountIrtToBurn,
        address onBehalfOf,
        address IrtFrom
    ) private {
        s_IRTMinted[onBehalfOf] -= amountIrtToBurn;
        bool success = i_irt.transferFrom(
            IrtFrom,
            address(this),
            amountIrtToBurn
        );
        if (!success) {
            revert IRTEngine__TransferFailed();
        }
        i_irt.burn(amountIrtToBurn);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert IRTEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalIrtMinted, uint256 collateralValueInUsd)
    {
        totalIrtMinted = s_IRTMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to Liquidation a user is
     * if a user goes below 1, then they can get liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalIrtMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalIrtMinted, collateralValueInUsd);
    }

    // function _healthFactor(address user) private view returns (uint256) {
    // Total DSC minted
    // Total Collateral VALUE
    // (
    // uint256 totalIrtMinted,
    // uint256 collateralValueInUsd
    // ) = _getAccountInformation(user);
    // uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
    // LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    //  1000 ETH * 50 = 50,000 / 100 = 500
    //  $150 ETH / 100 IRT = 1.5
    //  150 * 50 = 7500 / 100 = (75 / 100) < 1
    // 1000 * 50 = 50000 / 100 = (500 / 100) > 1
    // return (collateralAdjustedForThreshold * PRECISION) / totalIrtMinted;
    // }

    // Check health factor. Do they have enough collateral?
    // Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert IRTEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // Public And External View functions //

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // price of ETH
        // $/ETH ETH??
        // $2000 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10) = 0.005e18 ETH
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function _calculateHealthFactor(
        uint256 totalIrtMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalIrtMinted == 0) return type(uint256).max; // means "perfectly healthy"
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * 1e18) / totalIrtMinted;
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = $1000
        // The returned value  from CL will be 1000 * 1e8

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalIrtMinted, uint256 collateralValueInUsd)
    {
        (totalIrtMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
