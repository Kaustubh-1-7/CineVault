// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Using GitHub imports for OpenZeppelin; adjust if using npm imports
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/utils/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/utils/ReentrancyGuard.sol";

import "./IStoryInterfaces.sol"; // Your interface file

// Interface for ContentManager to read its public 'movies' mapping
interface IContentManager {
    // We expect the 'movies' mapping in ContentManager to return these fields.
    // The 'status' field will be returned as its underlying integer type (uint8 for enums).
    function movies(uint256 movieId) external view returns (
        address creator,
        string memory trailerIpfsUri,
        string memory movieIpMetadataIpfsUri,
        string memory movieNftMetadataIpfsUri,
        uint256 platformRentalPrice,
        address rentalPaymentToken,
        uint8 status, // Enum from ContentManager, accessed as uint8
        uint256 platformLikes,
        uint256 rentalCount, // <--- ADDED rentalCount here
        address storyIpId,
        uint256 storyLicenseTermsId
    );
}


contract RentalManager is AccessControl, Pausable, ReentrancyGuard {
    IContentManager public immutable PLATFORM_CONTENT_MANAGER;
    ILicensingModule public immutable STORY_LICENSING_MODULE;
    address public immutable STORY_PIL_TEMPLATE_ADDRESS; // From Story Protocol

    // Define the integer value corresponding to ContentManager.MovieStatus.RoyaltySet
    // Assuming 0-indexed in ContentManager.sol:
    // Submitted=0, Approved=1, Rejected=2, StoryRegistered=3, RoyaltySet=4
    uint8 private constant CONTENT_MANAGER_MOVIE_STATUS_ROYALTY_SET = 4;


    event MovieRented(
        uint256 indexed platformMovieId,
        address indexed user,
        address indexed storyIpId,
        uint256 storyLicenseTermsId,
        uint256 rentalFeePaid,
        address paymentToken,
        uint256 storyStartLicenseTokenId // First token ID if multiple were minted (usually 1)
    );
    // event StoryAddressesUpdatedRental(address licensingModule, address pilTemplate); // Removed, addresses are immutable


    constructor(
        address _contentManagerAddr,
        address _storyLicensingModuleAddr,
        address _storyPilTemplateAddr
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        PLATFORM_CONTENT_MANAGER = IContentManager(_contentManagerAddr);
        STORY_LICENSING_MODULE = ILicensingModule(_storyLicensingModuleAddr);
        STORY_PIL_TEMPLATE_ADDRESS = _storyPilTemplateAddr;
    }

    // --- Admin Functions ---
    function pauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpauseContract() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }


    // --- Core Logic ---
    function rentMovie(uint256 _platformMovieId) external payable whenNotPaused nonReentrant {
        (
            /* address creator */, // Not directly used in this function's logic
            /* string memory trailerIpfsUri */, // Not directly used
            /* string memory movieIpMetadataIpfsUri */, // Not directly used
            /* string memory movieNftMetadataIpfsUri */, // Not directly used
            uint256 platformRentalPrice,
            address rentalPaymentToken,
            uint8 status, // Received as uint8
            /* uint256 platformLikes */, // Not directly used
            /* uint256 rentalCount */, // Not directly used in this function's logic itself
            address storyIpId,
            uint256 storyLicenseTermsId
        ) = PLATFORM_CONTENT_MANAGER.movies(_platformMovieId);

        // Check if movie exists (platformRentalPrice > 0 implies creator != address(0) due to ContentManager logic)
        require(platformRentalPrice > 0, "Movie does not exist or price not set");
        require(status == CONTENT_MANAGER_MOVIE_STATUS_ROYALTY_SET, "Movie not available for rental (not RoyaltySet)");
        require(storyIpId != address(0) && storyLicenseTermsId != 0, "Movie not fully registered with Story");

        uint256 startLicenseTokenId;

        if (rentalPaymentToken == address(0)) { // ETH Payment
            require(msg.value >= platformRentalPrice, "Insufficient ETH sent for rental");
            // Call Story Protocol to mint the license token, forwarding ETH
            startLicenseTokenId = STORY_LICENSING_MODULE.mintLicenseTokens{value: platformRentalPrice}(
                storyIpId,
                STORY_PIL_TEMPLATE_ADDRESS,
                storyLicenseTermsId,
                1, // amount
                msg.sender, // receiver
                "" // hookData (empty for no hook or default hook behavior)
            );
            if (msg.value > platformRentalPrice) { // Refund any excess ETH
                payable(msg.sender).transfer(msg.value - platformRentalPrice);
            }
        } else { // ERC20 Payment
            require(msg.value == 0, "ETH should not be sent for ERC20 rentals");
            // User must have approved Story's LicensingModule (STORY_LICENSING_MODULE address)
            // to spend `platformRentalPrice` of `rentalPaymentToken`.
            // Story's LicensingModule will internally call `transferFrom` on the ERC20 token.
            IERC20 paymentToken = IERC20(rentalPaymentToken);
            uint256 allowance = paymentToken.allowance(msg.sender, address(STORY_LICENSING_MODULE));
            require(allowance >= platformRentalPrice, "Check ERC20 allowance for Story Licensing Module");

            startLicenseTokenId = STORY_LICENSING_MODULE.mintLicenseTokens( // Not payable if ERC20
                storyIpId,
                STORY_PIL_TEMPLATE_ADDRESS,
                storyLicenseTermsId,
                1, // amount
                msg.sender, // receiver
                "" // hookData
            );
        }

        emit MovieRented(
            _platformMovieId,
            msg.sender,
            storyIpId,
            storyLicenseTermsId,
            platformRentalPrice,
            rentalPaymentToken,
            startLicenseTokenId
        );
    }

    // --- View Functions ---
    // Function to check current allowance for ERC20 tokens (useful for frontend)
    function getErc20AllowanceForLicensingModule(address tokenAddress, address user) external view returns (uint256) {
        if (tokenAddress == address(0)) return type(uint256).max; // effectively infinite for ETH
        IERC20 token = IERC20(tokenAddress);
        return token.allowance(user, address(STORY_LICENSING_MODULE));
    }
}