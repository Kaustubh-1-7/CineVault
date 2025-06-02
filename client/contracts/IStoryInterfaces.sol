// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// --- Struct Definitions (used by Story Protocol ABIs) ---

struct IPMetadata {
    string ipMetadataURI;
    bytes32 ipMetadataHash;
    string nftMetadataURI;
    bytes32 nftMetadataHash;
}

struct PILTerms {
    bool transferable;
    address royaltyPolicy;
    uint256 defaultMintingFee;
    uint256 expiration; // Check Story Docs: License terms expiration or minted license expiration?
    bool commercialUse;
    bool commercialAttribution;
    address commercializerChecker;
    bytes commercializerCheckerData;
    uint32 commercialRevShare;
    uint256 commercialRevCeiling;
    bool derivativesAllowed;
    bool derivativesAttribution;
    bool derivativesApproval;
    bool derivativesReciprocal;
    uint256 derivativeRevCeiling;
    address currency; // e.g., MERC20 address
    string uri; // URI to human-readable terms
}

struct LicensingConfig {
    bool isSet;
    uint256 mintingFee;
    address licensingHook; // e.g., TotalLicenseTokenLimitHook address
    bytes hookData;
    uint32 commercialRevShare; // Check Story docs if this is separate or derived from PILTerms
    bool disabled;
    uint32 expectMinimumGroupRewardShare;
    address expectGroupRewardPool;
}

struct LicenseTermsData {
    PILTerms terms;
    LicensingConfig licensingConfig;
}

// SignatureData for meta-transactions (if your contracts directly handle them)
// If backend handles signatures, your contracts might not need this struct directly.
struct SignatureData {
    address signer;
    uint256 deadline;
    bytes signature;
}


// --- Story Protocol Contract Interfaces ---

interface ILicenseAttachmentWorkflows {
    // Example function: Choose the one your operator will primarily use.
    // If your platform or creator mints an SPGNFT for the IP first.
    function mintAndRegisterIpAndAttachPILTerms(
        address spgNftContract, // e.g., Story's SPGNFT implementation or beacon proxy
        address recipient, // Creator's address
        IPMetadata calldata ipMetadata,
        LicenseTermsData[] calldata licenseTermsData,
        bool allowDuplicates
    ) external returns (address ipId, uint256 tokenId, uint256[] memory licenseTermsIds);

    // If the creator already has an NFT representing the IP (e.g., their own ERC721).
    function registerIpAndAttachPILTerms(
        address nftContract, // Creator's existing NFT representing the IP
        uint256 tokenId,     // Token ID of the creator's NFT
        IPMetadata calldata ipMetadata,
        LicenseTermsData[] calldata licenseTermsData,
        SignatureData calldata sigMetadataAndAttachAndConfig // For meta-transactions
    ) external returns (address ipId, uint256[] memory licenseTermsIds);
}

interface ILicensingModule {
    function mintLicenseTokens(
        address licensorIpId,       // The storyIpId of the movie
        address licenseTemplate,    // Address of PILicenseTemplate
        uint256 licenseTermsId,     // The ID of the specific terms (rental terms)
        uint256 amount,             // Usually 1 for a rental
        address receiver,           // The user renting the movie
        bytes calldata data         // Data for any licensing hooks
    ) external payable returns (uint256 startLicenseTokenId); // `payable` if fees (ETH) are collected by this module
}

interface IRoyaltyModule {
    // The exact function signature for setting a royalty policy might differ.
    // This is a common pattern, but CONSULT STORY DOCS for the precise function.
    // It could be `setRoyaltyPolicy`, `configureRoyalty`, `addRoyaltyPolicyStack`, etc.
    // Parameters might also vary (e.g., separate payees and shares arrays).
    function setRoyaltyPolicy(
        address ipId, // The Story IP ID
        address policyContractAddress, // e.g., RoyaltyPolicyLAP address
        bytes calldata policyData // Encoded data for payees, shares, etc. for the policyContractAddress
    ) external;
}

// --- Standard Interfaces ---

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface ILicenseToken { // Basic ERC721-like interface for Story's LicenseToken
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    // HYPOTHETICAL: Check if Story's LicenseToken contract has a direct way to get mint time.
    // function getMintTimestamp(uint256 tokenId) external view returns (uint256);
}