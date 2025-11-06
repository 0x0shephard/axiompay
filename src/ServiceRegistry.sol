// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ServiceRegistry
 * @author AxiomPay
 * @notice An on-chain "Yellow Pages" for agent services
 * @dev Allows provider agents to register services with pricing and metadata
 * 
 * Features:
 * - Service registration with pricing tiers
 * - Service metadata (name, description, endpoint)
 * - Availability management
 * - Service discovery by provider or category
 * - Verified/curated service badges (admin controlled)
 */
contract ServiceRegistry is Ownable {

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Represents a service offered by a provider
     * @param provider The address of the service provider
     * @param name The name of the service
     * @param description Brief description of the service
     * @param endpoint API endpoint or connection string
     * @param category Service category (e.g., "compute", "data", "ai")
     * @param token The ERC-20 token accepted for payment
     * @param ratePerSecond The cost per second in tokens
     * @param minDuration Minimum duration in seconds
     * @param maxDuration Maximum duration in seconds (0 = unlimited)
     * @param isActive Whether the service is currently available
     * @param isVerified Whether the service is verified by protocol
     * @param registeredAt Timestamp when service was registered
     * @param totalStreams Total number of streams created
     */
    struct Service {
        address provider;
        string name;
        string description;
        string endpoint;
        string category;
        IERC20 token;
        uint256 ratePerSecond;
        uint256 minDuration;
        uint256 maxDuration;
        bool isActive;
        bool isVerified;
        uint256 registeredAt;
        uint256 totalStreams;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping from serviceId to Service struct
    mapping(uint256 => Service) public services;

    /// @notice Counter for generating unique service IDs
    uint256 public nextServiceId;

    /// @notice Mapping from provider address to array of their service IDs
    mapping(address => uint256[]) public providerServices;

    /// @notice Mapping from category to array of service IDs in that category
    mapping(string => uint256[]) public categoryServices;

    /// @notice Registration fee in wei (to prevent spam)
    uint256 public registrationFee;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new service is registered
     * @param serviceId The unique identifier for the service
     * @param provider The provider address
     * @param name The service name
     * @param category The service category
     * @param ratePerSecond The pricing rate
     */
    event ServiceRegistered(
        uint256 indexed serviceId,
        address indexed provider,
        string name,
        string category,
        uint256 ratePerSecond
    );

    /**
     * @notice Emitted when a service is updated
     * @param serviceId The service being updated
     * @param provider The provider address
     */
    event ServiceUpdated(uint256 indexed serviceId, address indexed provider);

    /**
     * @notice Emitted when a service's active status changes
     * @param serviceId The service being toggled
     * @param isActive The new active status
     */
    event ServiceActiveStatusChanged(uint256 indexed serviceId, bool isActive);

    /**
     * @notice Emitted when a service is verified
     * @param serviceId The service being verified
     * @param isVerified The new verification status
     */
    event ServiceVerificationChanged(uint256 indexed serviceId, bool isVerified);

    /**
     * @notice Emitted when registration fee is updated
     * @param oldFee The previous fee
     * @param newFee The new fee
     */
    event RegistrationFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when a stream is recorded for a service
     * @param serviceId The service used
     * @param totalStreams The new total stream count
     */
    event StreamRecorded(uint256 indexed serviceId, uint256 totalStreams);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ServiceNotFound();
    error Unauthorized();
    error InvalidProvider();
    error InvalidToken();
    error InvalidRate();
    error InvalidDuration();
    error InvalidServiceName();
    error InsufficientRegistrationFee();
    error ServiceNotActive();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the ServiceRegistry contract
     * @param _initialOwner The initial owner of the contract
     * @param _registrationFee The fee required to register a service
     */
    constructor(address _initialOwner, uint256 _registrationFee) Ownable(_initialOwner) {
        registrationFee = _registrationFee;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new service
     * @dev Requires registration fee to be paid
     * @param name The name of the service
     * @param description Description of the service
     * @param endpoint API endpoint or connection string
     * @param category Service category
     * @param token The ERC-20 token for payment
     * @param ratePerSecond The cost per second
     * @param minDuration Minimum duration in seconds
     * @param maxDuration Maximum duration in seconds (0 for unlimited)
     * @return serviceId The unique identifier for this service
     */
    function registerService(
        string calldata name,
        string calldata description,
        string calldata endpoint,
        string calldata category,
        IERC20 token,
        uint256 ratePerSecond,
        uint256 minDuration,
        uint256 maxDuration
    ) external payable returns (uint256 serviceId) {
        // Validation
        if (bytes(name).length == 0) revert InvalidServiceName();
        if (address(token) == address(0)) revert InvalidToken();
        if (ratePerSecond == 0) revert InvalidRate();
        if (maxDuration > 0 && minDuration > maxDuration) revert InvalidDuration();
        if (msg.value < registrationFee) revert InsufficientRegistrationFee();

        // Generate service ID
        serviceId = nextServiceId++;

        // Create service
        services[serviceId] = Service({
            provider: msg.sender,
            name: name,
            description: description,
            endpoint: endpoint,
            category: category,
            token: token,
            ratePerSecond: ratePerSecond,
            minDuration: minDuration,
            maxDuration: maxDuration,
            isActive: true,
            isVerified: false,
            registeredAt: block.timestamp,
            totalStreams: 0
        });

        // Add to provider's services
        providerServices[msg.sender].push(serviceId);

        // Add to category index
        categoryServices[category].push(serviceId);

        emit ServiceRegistered(serviceId, msg.sender, name, category, ratePerSecond);
    }

    /**
     * @notice Update an existing service
     * @dev Only the service provider can update
     * @param serviceId The ID of the service to update
     * @param name The new name
     * @param description The new description
     * @param endpoint The new endpoint
     * @param ratePerSecond The new rate
     * @param minDuration The new minimum duration
     * @param maxDuration The new maximum duration
     */
    function updateService(
        uint256 serviceId,
        string calldata name,
        string calldata description,
        string calldata endpoint,
        uint256 ratePerSecond,
        uint256 minDuration,
        uint256 maxDuration
    ) external {
        Service storage service = services[serviceId];

        // Validation
        if (service.provider == address(0)) revert ServiceNotFound();
        if (msg.sender != service.provider) revert Unauthorized();
        if (bytes(name).length == 0) revert InvalidServiceName();
        if (ratePerSecond == 0) revert InvalidRate();
        if (maxDuration > 0 && minDuration > maxDuration) revert InvalidDuration();

        // Update service
        service.name = name;
        service.description = description;
        service.endpoint = endpoint;
        service.ratePerSecond = ratePerSecond;
        service.minDuration = minDuration;
        service.maxDuration = maxDuration;

        emit ServiceUpdated(serviceId, msg.sender);
    }

    /**
     * @notice Toggle service active status
     * @dev Only the service provider can toggle
     * @param serviceId The ID of the service
     * @param isActive The new active status
     */
    function setServiceActiveStatus(uint256 serviceId, bool isActive) external {
        Service storage service = services[serviceId];

        if (service.provider == address(0)) revert ServiceNotFound();
        if (msg.sender != service.provider) revert Unauthorized();

        service.isActive = isActive;

        emit ServiceActiveStatusChanged(serviceId, isActive);
    }

    /**
     * @notice Record that a stream was created for a service
     * @dev This should be called by the AxiomStream contract
     * @param serviceId The service being used
     */
    function recordStream(uint256 serviceId) external {
        Service storage service = services[serviceId];

        if (service.provider == address(0)) revert ServiceNotFound();
        if (!service.isActive) revert ServiceNotActive();

        service.totalStreams++;

        emit StreamRecorded(serviceId, service.totalStreams);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get details of a service
     * @param serviceId The ID of the service
     * @return service The service struct
     */
    function getService(uint256 serviceId) external view returns (Service memory service) {
        service = services[serviceId];
        if (service.provider == address(0)) revert ServiceNotFound();
    }

    /**
     * @notice Get all services for a provider
     * @param provider The provider address
     * @return serviceIds Array of service IDs
     */
    function getProviderServices(address provider) 
        external 
        view 
        returns (uint256[] memory serviceIds) 
    {
        return providerServices[provider];
    }

    /**
     * @notice Get all services in a category
     * @param category The category to query
     * @return serviceIds Array of service IDs
     */
    function getCategoryServices(string calldata category) 
        external 
        view 
        returns (uint256[] memory serviceIds) 
    {
        return categoryServices[category];
    }

    /**
     * @notice Get active services for a provider
     * @param provider The provider address
     * @return activeServiceIds Array of active service IDs
     */
    function getActiveProviderServices(address provider) 
        external 
        view 
        returns (uint256[] memory activeServiceIds) 
    {
        uint256[] memory allServices = providerServices[provider];
        uint256 activeCount = 0;

        // Count active services
        for (uint256 i = 0; i < allServices.length; i++) {
            if (services[allServices[i]].isActive) {
                activeCount++;
            }
        }

        // Build array of active service IDs
        activeServiceIds = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allServices.length; i++) {
            if (services[allServices[i]].isActive) {
                activeServiceIds[index] = allServices[i];
                index++;
            }
        }
    }

    /**
     * @notice Get verified services in a category
     * @param category The category to query
     * @return verifiedServiceIds Array of verified service IDs
     */
    function getVerifiedCategoryServices(string calldata category) 
        external 
        view 
        returns (uint256[] memory verifiedServiceIds) 
    {
        uint256[] memory allServices = categoryServices[category];
        uint256 verifiedCount = 0;

        // Count verified services
        for (uint256 i = 0; i < allServices.length; i++) {
            if (services[allServices[i]].isVerified && services[allServices[i]].isActive) {
                verifiedCount++;
            }
        }

        // Build array of verified service IDs
        verifiedServiceIds = new uint256[](verifiedCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allServices.length; i++) {
            Service memory service = services[allServices[i]];
            if (service.isVerified && service.isActive) {
                verifiedServiceIds[index] = allServices[i];
                index++;
            }
        }
    }

    /**
     * @notice Check if a duration is valid for a service
     * @param serviceId The service to check
     * @param duration The duration to validate
     * @return valid Whether the duration is valid
     */
    function isValidDuration(uint256 serviceId, uint256 duration) 
        external 
        view 
        returns (bool valid) 
    {
        Service storage service = services[serviceId];
        if (service.provider == address(0)) revert ServiceNotFound();

        if (duration < service.minDuration) return false;
        if (service.maxDuration > 0 && duration > service.maxDuration) return false;

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set verification status for a service
     * @dev Only callable by owner (for curation)
     * @param serviceId The service to verify/unverify
     * @param isVerified The new verification status
     */
    function setServiceVerification(uint256 serviceId, bool isVerified) external onlyOwner {
        Service storage service = services[serviceId];
        if (service.provider == address(0)) revert ServiceNotFound();

        service.isVerified = isVerified;

        emit ServiceVerificationChanged(serviceId, isVerified);
    }

    /**
     * @notice Update the registration fee
     * @dev Only callable by owner
     * @param newFee The new registration fee
     */
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = registrationFee;
        registrationFee = newFee;

        emit RegistrationFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Withdraw accumulated registration fees
     * @dev Only callable by owner
     * @param recipient The address to send fees to
     */
    function withdrawFees(address payable recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidProvider();

        uint256 balance = address(this).balance;
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "Transfer failed");
    }
}
