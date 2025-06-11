// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ContentManager is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant ADMIN_OPERATOR_ROLE = keccak256("ADMIN_OPERATOR_ROLE");

    enum MoviePlatformStatus {
        Submitted, ApprovedByModerator, RejectedByModerator, LiveOnStory, HiddenFromStory
    }

    struct MoviePlatformData {
        address creator;
        string trailerIpfsUri;
        string movieIpfsMetadataUri;
        uint256 platformRentalPrice;
        address rentalPaymentToken;
        MoviePlatformStatus platformStatus;
        uint256 platformLikes;
        uint256 platformRentalCount;
        address storyIpId;
        uint256 storyPrimaryLicenseTermsId;
    }

    uint256 public movieIdCounter;
    mapping(uint256 => MoviePlatformData) public movies;
    mapping(uint256 => mapping(address => bool)) public userHasLikedMovie;

    address payable public platformRevenueWallet;
    uint256 public platformUploadFee;

    event MovieSubmittedToPlatform(uint256 movieId, address creator, string metadata, uint256 price, address token);
    event MovieModeratedOnPlatform(uint256 movieId, MoviePlatformStatus status, address moderator);
    event MovieLikedOnPlatform(uint256 movieId, address user);
    event MovieStoryInfoUpdated(uint256 movieId, address storyIpId, uint256 storyLicenseTermsId);
    event MovieRentalCountIncrementedOnPlatform(uint256 movieId, uint256 newCount);
    event PlatformFeesWithdrawn(uint256 amount);
    event PlatformUploadFeeUpdated(uint256 oldFee, uint256 newFee);

    constructor(uint256 _initialUploadFee, address payable _platformRevenueWallet) {
        platformUploadFee = _initialUploadFee;
        platformRevenueWallet = _platformRevenueWallet;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_OPERATOR_ROLE, msg.sender);
    }

    function addModerator(address moderator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MODERATOR_ROLE, moderator);
    }

    function removeModerator(address moderator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(MODERATOR_ROLE, moderator);
    }

    function addAdminOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(ADMIN_OPERATOR_ROLE, operator);
    }

    function removeAdminOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(ADMIN_OPERATOR_ROLE, operator);
    }

    function isModerator(address account) public view returns (bool) {
        return hasRole(MODERATOR_ROLE, account);
    }

    function isAdminOperator(address account) public view returns (bool) {
        return hasRole(ADMIN_OPERATOR_ROLE, account);
    }

    function setPlatformUploadFee(uint256 _newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldFee = platformUploadFee;
        platformUploadFee = _newFee;
        emit PlatformUploadFeeUpdated(oldFee, _newFee);
    }

    function withdrawPlatformUploadFees() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH fees to withdraw");
        (bool success, ) = platformRevenueWallet.call{value: balance}("");
        require(success, "ETH Fee withdrawal failed");
        emit PlatformFeesWithdrawn(balance);
    }

    function pauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function hasUserLikedMovie(uint256 _movieId, address _user) external view returns (bool) {
        return userHasLikedMovie[_movieId][_user];
    }

    function getMovie(uint256 _movieId) external view returns (MoviePlatformData memory) {
        require(_movieId > 0 && _movieId <= movieIdCounter, "Invalid movie ID");
        return movies[_movieId];
    }

    function getTotalMovies() external view returns (uint256) {
        return movieIdCounter;
    }

    function submitMovieToPlatform(
        string calldata _trailerIpfsUri,
        string calldata _movieIpfsMetadataUri,
        uint256 _platformRentalPrice,
        address _rentalPaymentToken
    ) external payable whenNotPaused nonReentrant {
        require(msg.value >= platformUploadFee, "Upload fee required");

        uint256 excess = msg.value - platformUploadFee;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }

        (bool ok, ) = platformRevenueWallet.call{value: platformUploadFee}("");
        require(ok, "Fee transfer failed");

        movieIdCounter++;
        movies[movieIdCounter] = MoviePlatformData({
            creator: msg.sender,
            trailerIpfsUri: _trailerIpfsUri,
            movieIpfsMetadataUri: _movieIpfsMetadataUri,
            platformRentalPrice: _platformRentalPrice,
            rentalPaymentToken: _rentalPaymentToken,
            platformStatus: MoviePlatformStatus.Submitted,
            platformLikes: 0,
            platformRentalCount: 0,
            storyIpId: address(0),
            storyPrimaryLicenseTermsId: 0
        });

        emit MovieSubmittedToPlatform(movieIdCounter, msg.sender, _movieIpfsMetadataUri, _platformRentalPrice, _rentalPaymentToken);
    }

    function reviewMovieOnPlatform(uint256 _movieId, bool _approve)
        external
        whenNotPaused
        onlyRole(MODERATOR_ROLE)
    {
        require(_movieId > 0 && _movieId <= movieIdCounter, "Invalid movie ID");
        MoviePlatformData storage movie = movies[_movieId];
        require(movie.platformStatus == MoviePlatformStatus.Submitted, "Movie not in submitted status");

        if (_approve) {
            movie.platformStatus = MoviePlatformStatus.ApprovedByModerator;
        } else {
            movie.platformStatus = MoviePlatformStatus.RejectedByModerator;
        }

        emit MovieModeratedOnPlatform(_movieId, movie.platformStatus, msg.sender);
    }

    function likeMovieOnPlatform(uint256 _movieId) external whenNotPaused nonReentrant {
        require(_movieId > 0 && _movieId <= movieIdCounter, "Invalid movie ID");
        require(!userHasLikedMovie[_movieId][msg.sender], "Already liked");

        movies[_movieId].platformLikes++;
        userHasLikedMovie[_movieId][msg.sender] = true;

        emit MovieLikedOnPlatform(_movieId, msg.sender);
    }

    function confirmStoryLinking(uint256 _movieId, address _storyIpId, uint256 _storyLicenseTermsId) external whenNotPaused onlyRole(ADMIN_OPERATOR_ROLE) {
        require(_movieId > 0 && _movieId <= movieIdCounter, "Invalid movie ID");
        MoviePlatformData storage movie = movies[_movieId];
        movie.storyIpId = _storyIpId;
        movie.storyPrimaryLicenseTermsId = _storyLicenseTermsId;
        movie.platformStatus = MoviePlatformStatus.LiveOnStory;
        emit MovieStoryInfoUpdated(_movieId, _storyIpId, _storyLicenseTermsId);
    }

    function incrementPlatformRentalCount(uint256 _movieId) external whenNotPaused onlyRole(ADMIN_OPERATOR_ROLE) {
        require(_movieId > 0 && _movieId <= movieIdCounter, "Invalid movie ID");
        movies[_movieId].platformRentalCount++;
        emit MovieRentalCountIncrementedOnPlatform(_movieId, movies[_movieId].platformRentalCount);
    }

    function getMovieRentalPrerequisites(uint256 movieId) external view returns (
        address, uint256, address, uint8, address, uint256
    ) {
        MoviePlatformData memory m = movies[movieId];
        return (m.creator, m.platformRentalPrice, m.rentalPaymentToken, uint8(m.platformStatus), m.storyIpId, m.storyPrimaryLicenseTermsId);
    }

    function listAllMovies() external view returns (MoviePlatformData[] memory) {
        MoviePlatformData[] memory result = new MoviePlatformData[](movieIdCounter);
        for (uint256 i = 1; i <= movieIdCounter; i++) {
            result[i - 1] = movies[i];
        }
        return result;
    }
} 
