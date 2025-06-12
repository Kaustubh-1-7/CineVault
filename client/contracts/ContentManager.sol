// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ContentManager is AccessControl, Pausable, ReentrancyGuard {
bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
bytes32 public constant ADMIN_OPERATOR_ROLE = keccak256("ADMIN_OPERATOR_ROLE");

enum MoviePlatformStatus {
    Submitted,
    ApprovedByModerator,
    RejectedByModerator,
    LiveOnStory,
    HiddenFromStory
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
mapping(uint256 => string) private _movieCoverImage;
mapping(uint256 => address) public movieCreators;

uint256 public platformUploadFee;
address payable public platformRevenueWallet;

event MovieSubmittedToPlatform(
    uint256 indexed movieId,
    address indexed creator,
    string movieIpfsMetadataUri,
    uint256 platformRentalPrice,
    address rentalPaymentToken
);
event MovieModeratedOnPlatform(uint256 indexed movieId, MoviePlatformStatus status, address indexed moderator);
event RequestRegisterOrUpdateOnStory(uint256 indexed movieId, address creator);
event RequestHideFromStory(uint256 indexed movieId);
event MovieStoryInfoUpdated(uint256 indexed movieId, address storyIpId, uint256 storyLicenseTermsId);
event MovieLikedOnPlatform(uint256 indexed movieId, address indexed user);
event MovieRentalCountIncrementedOnPlatform(uint256 indexed movieId, uint256 newRentalCount);
event PlatformUploadFeeUpdated(uint256 oldFee, uint256 newFee);
event PlatformFeesWithdrawn(uint256 amount);
event CoverImageUpdated(uint256 indexed movieId, string imageUri);

constructor(uint256 _initialUploadFee, address payable _platformRevenueWallet) {
    require(_platformRevenueWallet != address(0), "Invalid revenue wallet");
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_OPERATOR_ROLE, msg.sender);
    platformUploadFee = _initialUploadFee;
    platformRevenueWallet = _platformRevenueWallet;
}

// Role Management
function addAdminOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(operator != address(0), "Invalid address");
    grantRole(ADMIN_OPERATOR_ROLE, operator);
}

function removeAdminOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(ADMIN_OPERATOR_ROLE, operator);
}

function addModerator(address moderator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(moderator != address(0), "Invalid address");
    grantRole(MODERATOR_ROLE, moderator);
}

function removeModerator(address moderator) external onlyRole(DEFAULT_ADMIN_ROLE) {
    revokeRole(MODERATOR_ROLE, moderator);
}

function isModerator(address account) public view returns (bool) {
    return hasRole(MODERATOR_ROLE, account);
}

function isAdminOperator(address account) public view returns (bool) {
    return hasRole(ADMIN_OPERATOR_ROLE, account);
}

// Admin Functions
function setPlatformUploadFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 oldFee = platformUploadFee;
    platformUploadFee = newFee;
    emit PlatformUploadFeeUpdated(oldFee, newFee);
}

function withdrawPlatformUploadFees() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 balance = address(this).balance;
    require(balance > 0, "No ETH to withdraw");
    (bool success, ) = platformRevenueWallet.call{value: balance}("");
    require(success, "Withdrawal failed");
    emit PlatformFeesWithdrawn(balance);
}

function pauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _pause();
}

function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _unpause();
}

// Core Logic
function submitMovieToPlatform(
    string calldata trailerIpfsUri,
    string calldata movieIpfsMetadataUri,
    uint256 platformRentalPrice,
    address rentalPaymentToken
) external payable whenNotPaused nonReentrant {
    require(bytes(trailerIpfsUri).length > 0, "Missing trailer URI");
    require(bytes(movieIpfsMetadataUri).length > 0, "Missing metadata URI");
    require(platformRentalPrice > 0, "Invalid price");
    require(msg.value >= platformUploadFee, "Insufficient fee");

    uint256 excess = msg.value - platformUploadFee;

    movieIdCounter++;
    movies[movieIdCounter] = MoviePlatformData({
        creator: msg.sender,
        trailerIpfsUri: trailerIpfsUri,
        movieIpfsMetadataUri: movieIpfsMetadataUri,
        platformRentalPrice: platformRentalPrice,
        rentalPaymentToken: rentalPaymentToken,
        platformStatus: MoviePlatformStatus.Submitted,
        platformLikes: 0,
        platformRentalCount: 0,
        storyIpId: address(0),
        storyPrimaryLicenseTermsId: 0
    });

    movieCreators[movieIdCounter] = msg.sender;

    emit MovieSubmittedToPlatform(movieIdCounter, msg.sender, movieIpfsMetadataUri, platformRentalPrice, rentalPaymentToken);

    if (excess > 0) {
        payable(msg.sender).transfer(excess);
    }
}

function reviewMovieOnPlatform(uint256 movieId, bool approve) external whenNotPaused onlyRole(MODERATOR_ROLE) {
    require(movieId > 0 && movieId <= movieIdCounter, "Invalid ID");
    MoviePlatformData storage movie = movies[movieId];
    require(movie.platformStatus == MoviePlatformStatus.Submitted, "Not submitted");

    if (approve) {
        movie.platformStatus = MoviePlatformStatus.ApprovedByModerator;
        emit RequestRegisterOrUpdateOnStory(movieId, movie.creator);
    } else {
        movie.platformStatus = MoviePlatformStatus.RejectedByModerator;
    }

    emit MovieModeratedOnPlatform(movieId, movie.platformStatus, msg.sender);
}

function confirmStoryLinking(uint256 movieId, address storyIpId, uint256 licenseId)
    external whenNotPaused onlyRole(ADMIN_OPERATOR_ROLE)
{
    require(movieId > 0 && movieId <= movieIdCounter, "Invalid ID");
    require(storyIpId != address(0) && licenseId > 0, "Invalid story info");

    MoviePlatformData storage movie = movies[movieId];
    require(movie.platformStatus == MoviePlatformStatus.ApprovedByModerator, "Not approved");

    movie.storyIpId = storyIpId;
    movie.storyPrimaryLicenseTermsId = licenseId;
    movie.platformStatus = MoviePlatformStatus.LiveOnStory;

    emit MovieStoryInfoUpdated(movieId, storyIpId, licenseId);
}

function incrementPlatformRentalCount(uint256 movieId) external whenNotPaused onlyRole(ADMIN_OPERATOR_ROLE) {
    require(movieId > 0 && movieId <= movieIdCounter, "Invalid ID");
    require(movies[movieId].platformStatus == MoviePlatformStatus.LiveOnStory, "Not live");

    movies[movieId].platformRentalCount++;
    emit MovieRentalCountIncrementedOnPlatform(movieId, movies[movieId].platformRentalCount);
}

function likeMovieOnPlatform(uint256 movieId) external whenNotPaused nonReentrant {
    require(movieId > 0 && movieId <= movieIdCounter, "Invalid ID");
    require(!userHasLikedMovie[movieId][msg.sender], "Already liked");

    MoviePlatformData storage movie = movies[movieId];
    require(
        movie.platformStatus == MoviePlatformStatus.ApprovedByModerator ||
        movie.platformStatus == MoviePlatformStatus.LiveOnStory,
        "Not approved or live"
    );

    movie.platformLikes++;
    userHasLikedMovie[movieId][msg.sender] = true;

    emit MovieLikedOnPlatform(movieId, msg.sender);
}

function getMovieRentalPrerequisites(uint256 movieId) external view returns (
    address creator,
    uint256 platformRentalPrice,
    address rentalPaymentToken,
    uint8 platformStatus,
    address storyIpId,
    uint256 storyPrimaryLicenseTermsId
) {
    MoviePlatformData memory m = movies[movieId];
    return (
        m.creator,
        m.platformRentalPrice,
        m.rentalPaymentToken,
        uint8(m.platformStatus),
        m.storyIpId,
        m.storyPrimaryLicenseTermsId
    );
}

// ✅ New Cover Image Logic
function setMovieCoverImage(uint256 movieId, string calldata imageUri) external {
    require(movieCreators[movieId] == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not creator/admin");
    require(bytes(imageUri).length > 0, "Empty URI");
    _movieCoverImage[movieId] = imageUri;
    emit CoverImageUpdated(movieId, imageUri);
}

function getMovieCoverImage(uint256 movieId) external view returns (string memory) {
    return _movieCoverImage[movieId];
}

// View Functions
function getMovie(uint256 movieId) external view returns (MoviePlatformData memory) {
    return movies[movieId];
}

function getTotalMovies() external view returns (uint256) {
    return movieIdCounter;
}

function hasUserLikedMovie(uint256 movieId, address user) external view returns (bool) {
    return userHasLikedMovie[movieId][user];
}

function listAllMovies() external view returns (MoviePlatformData[] memory) {
    MoviePlatformData[] memory all = new MoviePlatformData[](movieIdCounter);
    for (uint256 i = 1; i <= movieIdCounter; i++) {
        all[i - 1] = movies[i];
    }
    return all;
}

receive() external payable {}
}









