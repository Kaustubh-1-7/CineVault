// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Using GitHub imports for OpenZeppelin; adjust if using npm imports
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/utils/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/utils/ReentrancyGuard.sol";

import "./IStoryInterfaces.sol"; // Your interface file

contract ContentManager is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum MovieStatus { Submitted, Approved, Rejected, StoryRegistered, RoyaltySet }

    struct MovieData {
        address creator;
        string trailerIpfsUri;
        string movieIpMetadataIpfsUri;
        string movieNftMetadataIpfsUri;
        uint256 platformRentalPrice;
        address rentalPaymentToken;
        MovieStatus status;
        uint256 platformLikes;
        uint256 rentalCount; // <--- NEW: Tracks number of rentals
        address storyIpId;
        uint256 storyLicenseTermsId;
    }

    uint256 public movieIdCounter;
    mapping(uint256 => MovieData) public movies;
    mapping(uint256 => mapping(address => bool)) public userHasLikedMovie;

    uint256 public platformUploadFee; // Fee in ETH
    address payable public platformRevenueWallet;

    address public storyLicenseAttachmentWorkflowsAddr;
    address public storyRoyaltyModuleAddr;
    address public storyPilTemplateAddr;
    address public storyRoyaltyPolicyLapAddr;
    address public storySpgNftContractAddr;

    event MovieSubmitted(
        uint256 indexed movieId,
        address indexed creator,
        string trailerIpfsUri,
        string movieIpMetadataIpfsUri,
        string movieNftMetadataIpfsUri,
        uint256 platformRentalPrice,
        address rentalPaymentToken
    );
    event MovieModerated(uint256 indexed movieId, MovieStatus status, address indexed moderator);
    event TriggerStoryIpRegistration(
        uint256 indexed movieId,
        address indexed creator,
        string movieIpMetadataIpfsUri,
        string movieNftMetadataIpfsUri,
        uint256 platformRentalPrice,
        address rentalPaymentToken,
        address storySpgNftContractToUse,
        address royaltyPolicyForTerms,
        address currencyForTerms
    );
    event MovieStoryRegistered(uint256 indexed movieId, address indexed storyIpId, uint256 storyLicenseTermsId);
    event TriggerStoryRoyaltySetup(
        uint256 indexed movieId,
        address indexed storyIpId,
        address indexed creator,
        address platformRevenueWallet,
        uint256 platformShareBps,
        address royaltyPolicyToUse
    );
    event MovieRoyaltySet(uint256 indexed movieId);
    event MovieLiked(uint256 indexed movieId, address indexed user);
    event MovieRentalCountIncremented(uint256 indexed movieId, uint256 newRentalCount); // <--- NEW EVENT
    event PlatformFeesWithdrawn(address indexed beneficiary, uint256 amount);
    event StoryAddressesUpdated();


    constructor(
        uint256 _initialUploadFee,
        address payable _platformRevenueWallet,
        address _sLicenseAttachmentWorkflowsAddr,
        address _sRoyaltyModuleAddr,
        address _sPilTemplateAddr,
        address _sRoyaltyPolicyLapAddr,
        address _sSpgNftContractAddr
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        platformUploadFee = _initialUploadFee;
        require(_platformRevenueWallet != address(0), "Revenue wallet cannot be zero");
        platformRevenueWallet = _platformRevenueWallet;

        storyLicenseAttachmentWorkflowsAddr = _sLicenseAttachmentWorkflowsAddr;
        storyRoyaltyModuleAddr = _sRoyaltyModuleAddr;
        storyPilTemplateAddr = _sPilTemplateAddr;
        storyRoyaltyPolicyLapAddr = _sRoyaltyPolicyLapAddr;
        storySpgNftContractAddr = _sSpgNftContractAddr;
    }

    // ... (other admin functions: updateStoryAddresses, addModerator, etc. remain the same) ...
    function updateStoryAddresses(
        address _sLicenseAttachmentWorkflowsAddr,
        address _sRoyaltyModuleAddr,
        address _sPilTemplateAddr,
        address _sRoyaltyPolicyLapAddr,
        address _sSpgNftContractAddr
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        storyLicenseAttachmentWorkflowsAddr = _sLicenseAttachmentWorkflowsAddr;
        storyRoyaltyModuleAddr = _sRoyaltyModuleAddr;
        storyPilTemplateAddr = _sPilTemplateAddr;
        storyRoyaltyPolicyLapAddr = _sRoyaltyPolicyLapAddr;
        storySpgNftContractAddr = _sSpgNftContractAddr;
        emit StoryAddressesUpdated();
    }

    function addModerator(address _moderator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(MODERATOR_ROLE, _moderator);
    }

    function removeModerator(address _moderator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(MODERATOR_ROLE, _moderator);
    }

    function addOperator(address _operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(OPERATOR_ROLE, _operator);
    }

    function removeOperator(address _operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(OPERATOR_ROLE, _operator);
    }

    function setPlatformUploadFee(uint256 _newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        platformUploadFee = _newFee;
    }

    function withdrawPlatformUploadFees() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH fees to withdraw");
        (bool success, ) = platformRevenueWallet.call{value: balance}("");
        require(success, "ETH Fee withdrawal failed");
        emit PlatformFeesWithdrawn(platformRevenueWallet, balance);
    }

    function pauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }


    // --- Core Logic ---
    function submitMovie(
        string calldata _trailerIpfsUri,
        string calldata _movieIpMetadataIpfsUri,
        string calldata _movieNftMetadataIpfsUri,
        uint256 _platformRentalPrice,
        address _rentalPaymentToken
    ) external payable whenNotPaused nonReentrant {
        require(msg.value >= platformUploadFee, "Insufficient upload fee paid");
        if (msg.value > platformUploadFee) {
            payable(msg.sender).transfer(msg.value - platformUploadFee);
        }

        movieIdCounter++;
        uint256 currentMovieId = movieIdCounter;

        movies[currentMovieId] = MovieData({
            creator: msg.sender,
            trailerIpfsUri: _trailerIpfsUri,
            movieIpMetadataIpfsUri: _movieIpMetadataIpfsUri,
            movieNftMetadataIpfsUri: _movieNftMetadataIpfsUri,
            platformRentalPrice: _platformRentalPrice,
            rentalPaymentToken: _rentalPaymentToken,
            status: MovieStatus.Submitted,
            platformLikes: 0,
            rentalCount: 0, // <--- INITIALIZE rentalCount
            storyIpId: address(0),
            storyLicenseTermsId: 0
        });

        emit MovieSubmitted(
            currentMovieId,
            msg.sender,
            _trailerIpfsUri,
            _movieIpMetadataIpfsUri,
            _movieNftMetadataIpfsUri,
            _platformRentalPrice,
            _rentalPaymentToken
        );
    }

    function reviewMovie(uint256 _movieId, bool _approve) external whenNotPaused onlyRole(MODERATOR_ROLE) {
        MovieData storage movie = movies[_movieId];
        require(movie.creator != address(0), "Movie does not exist");
        require(movie.status == MovieStatus.Submitted, "Movie not in submitted state");

        if (_approve) {
            movie.status = MovieStatus.Approved;
            emit TriggerStoryIpRegistration(
                _movieId,
                movie.creator,
                movie.movieIpMetadataIpfsUri,
                movie.movieNftMetadataIpfsUri,
                movie.platformRentalPrice,
                movie.rentalPaymentToken,
                storySpgNftContractAddr,
                storyRoyaltyPolicyLapAddr,
                movie.rentalPaymentToken
            );
        } else {
            movie.status = MovieStatus.Rejected;
        }
        emit MovieModerated(_movieId, movie.status, msg.sender);
    }

    function confirmStoryIpRegistered(
        uint256 _movieId,
        address _storyIpId,
        uint256 _storyLicenseTermsId
    ) external whenNotPaused onlyRole(OPERATOR_ROLE) {
        MovieData storage movie = movies[_movieId];
        require(movie.status == MovieStatus.Approved, "Movie not in approved state for Story registration confirmation");
        require(_storyIpId != address(0), "Story IP ID cannot be zero");
        require(_storyLicenseTermsId != 0, "Story License Terms ID cannot be zero");

        movie.storyIpId = _storyIpId;
        movie.storyLicenseTermsId = _storyLicenseTermsId;
        movie.status = MovieStatus.StoryRegistered;

        emit MovieStoryRegistered(_movieId, _storyIpId, _storyLicenseTermsId);
        emit TriggerStoryRoyaltySetup(_movieId, _storyIpId, movie.creator, platformRevenueWallet, 2000, storyRoyaltyPolicyLapAddr);
    }

    function confirmStoryRoyaltySet(uint256 _movieId) external whenNotPaused onlyRole(OPERATOR_ROLE) {
        MovieData storage movie = movies[_movieId];
        require(movie.status == MovieStatus.StoryRegistered, "Movie not in StoryRegistered state for royalty confirmation");
        movie.status = MovieStatus.RoyaltySet;
        emit MovieRoyaltySet(_movieId);
    }

    // <--- NEW FUNCTION to be called by Operator ---
    function incrementRentalCount(uint256 _movieId) external whenNotPaused onlyRole(OPERATOR_ROLE) {
        MovieData storage movie = movies[_movieId];
        require(movie.creator != address(0), "Movie does not exist");
        // Ensure movie is in a state where rentals are expected
        require(movie.status == MovieStatus.RoyaltySet, "Movie not in rentable state");

        movie.rentalCount++;
        emit MovieRentalCountIncremented(_movieId, movie.rentalCount);
    }

    function likeMovie(uint256 _movieId) external whenNotPaused nonReentrant {
        MovieData storage movie = movies[_movieId];
        require(movie.status == MovieStatus.Approved || movie.status == MovieStatus.StoryRegistered || movie.status == MovieStatus.RoyaltySet, "Movie not available");
        require(!userHasLikedMovie[_movieId][msg.sender], "Already liked");

        movie.platformLikes++;
        userHasLikedMovie[_movieId][msg.sender] = true;
        emit MovieLiked(_movieId, msg.sender);
    }

    // --- View Functions ---
    function getMovie(uint256 _movieId) external view returns (MovieData memory) {
        return movies[_movieId];
    }

    function isOperator(address account) external view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    function isModerator(address account) external view returns (bool) {
        return hasRole(MODERATOR_ROLE, account);
    }
}