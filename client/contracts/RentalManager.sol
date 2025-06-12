// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IPlatformContentManager {
    function getMovieRentalPrerequisites(uint256 movieId) external view returns (
        address creator,
        uint256 platformRentalPrice,
        address rentalPaymentToken,
        uint8 platformStatus,
        address storyIpId,
        uint256 storyPrimaryLicenseTermsId
    );
}

contract RentalManager is AccessControl, Pausable, ReentrancyGuard {
    IPlatformContentManager public immutable PLATFORM_CONTENT_MANAGER;
    address payable public immutable platformRevenueWalletForRentals;

    uint8 private constant MOVIE_STATUS_LIVE_ON_STORY = 3;

    struct RentalRecord {
        address renter;
        uint256 timestamp;
        uint256 amountPaid;
        address paymentToken;
        uint256 rentalExpiry;
    }

    mapping(uint256 => RentalRecord[]) private _movieRentals;
    mapping(address => mapping(uint256 => RentalRecord)) private _userRentalData;

    event RentalPaymentProcessed(
        uint256 indexed platformMovieId,
        address indexed renter,
        address storyIpId,
        uint256 storyLicenseTermsId,
        uint256 feePaid,
        address paymentToken,
        address creator,
        uint256 expiry
    );

    event ETHWithdrawn(uint256 amount);
    event ERC20Withdrawn(address token, uint256 amount);

    uint256 public constant RENTAL_DURATION = 3 days;

    constructor(address _contentManagerAddr, address payable _platformRevenueWallet) {
        require(_contentManagerAddr != address(0), "Invalid content manager address");
        require(_platformRevenueWallet != address(0), "Invalid revenue wallet");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        PLATFORM_CONTENT_MANAGER = IPlatformContentManager(_contentManagerAddr);
        platformRevenueWalletForRentals = _platformRevenueWallet;
    }

    function pauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function rentMovieOnPlatform(uint256 _platformMovieId) external payable nonReentrant whenNotPaused {
        (
            address creator_,
            uint256 price_,
            address token_,
            uint8 status_,
            address story_,
            uint256 license_
        ) = PLATFORM_CONTENT_MANAGER.getMovieRentalPrerequisites(_platformMovieId);

        require(creator_ != address(0), "Movie not found");
        require(status_ == MOVIE_STATUS_LIVE_ON_STORY, "Movie not available");
        require(price_ > 0, "Price not set");
        require(story_ != address(0) && license_ > 0, "Invalid Story info");

        uint256 creatorShare = (price_ * 80) / 100;
        uint256 platformShare = price_ - creatorShare;

        if (token_ == address(0)) {
            require(msg.value >= price_, "Insufficient ETH");
            if (msg.value > price_) {
                payable(msg.sender).transfer(msg.value - price_);
            }
            payable(creator_).transfer(creatorShare);
            platformRevenueWalletForRentals.transfer(platformShare);
        } else {
            require(msg.value == 0, "Do not send ETH");
            IERC20 token = IERC20(token_);
            require(token.transferFrom(msg.sender, creator_, creatorShare), "ERC20 to creator failed");
            require(token.transferFrom(msg.sender, platformRevenueWalletForRentals, platformShare), "ERC20 to platform failed");
        }

        uint256 expiryTime = block.timestamp + RENTAL_DURATION;

        _userRentalData[msg.sender][_platformMovieId] = RentalRecord({
            renter: msg.sender,
            timestamp: block.timestamp,
            amountPaid: price_,
            paymentToken: token_,
            rentalExpiry: expiryTime
        });

        _movieRentals[_platformMovieId].push(_userRentalData[msg.sender][_platformMovieId]);

        emit RentalPaymentProcessed(
            _platformMovieId,
            msg.sender,
            story_,
            license_,
            price_,
            token_,
            creator_,
            expiryTime
        );
    }

    function hasUserRentedMovie(address user, uint256 movieId) external view returns (bool) {
        RentalRecord memory rec = _userRentalData[user][movieId];
        return rec.renter != address(0) && rec.rentalExpiry >= block.timestamp;
    }

    function getMovieRentalHistory(uint256 movieId) external view returns (RentalRecord[] memory) {
        return _movieRentals[movieId];
    }

    function getUserRentalDetails(address user, uint256 movieId) external view returns (RentalRecord memory) {
        return _userRentalData[user][movieId];
    }

    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getERC20Balance(address tokenAddress) external view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function withdrawPlatformETHRentals(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        (bool success, ) = platformRevenueWalletForRentals.call{value: amount}("");
        require(success, "ETH withdrawal failed");
        emit ETHWithdrawn(amount);
    }

    function withdrawPlatformERC20Rentals(address tokenAddress, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) >= amount, "Insufficient token balance");
        require(token.transfer(platformRevenueWalletForRentals, amount), "ERC20 withdrawal failed");
        emit ERC20Withdrawn(tokenAddress, amount);
    }

    function getErc20Allowance(address tokenAddress, address user, address spender) external view returns (uint256) {
        if (tokenAddress == address(0)) return type(uint256).max;
        IERC20 token = IERC20(tokenAddress);
        return token.allowance(user, spender);
    }
}
