// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ServiceRegistry.sol";
import "./mocks/MockERC20.sol";

contract ServiceRegistryTest is Test {
    ServiceRegistry public registry;
    MockERC20 public usdc;

    address public owner = address(0x1);
    address public provider1 = address(0x2);
    address public provider2 = address(0x3);

    uint256 public constant REGISTRATION_FEE = 0.001 ether;

    event ServiceRegistered(
        uint256 indexed serviceId,
        address indexed provider,
        string name,
        string category,
        uint256 ratePerSecond
    );

    event ServiceUpdated(uint256 indexed serviceId, address indexed provider);

    event ServiceActiveStatusChanged(uint256 indexed serviceId, bool isActive);

    event ServiceVerificationChanged(uint256 indexed serviceId, bool isVerified);

    function setUp() public {
        vm.deal(provider1, 10 ether);
        vm.deal(provider2, 10 ether);

        vm.startPrank(owner);
        registry = new ServiceRegistry(owner, REGISTRATION_FEE);
        usdc = new MockERC20("USD Coin", "USDC", 1_000_000 * 1e6);
        vm.stopPrank();

        vm.label(owner, "Owner");
        vm.label(provider1, "Provider1");
        vm.label(provider2, "Provider2");
        vm.label(address(registry), "ServiceRegistry");
    }

    /*//////////////////////////////////////////////////////////////
                    SERVICE REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testRegisterService() public {
        string memory name = "GPU Compute";
        string memory description = "High-performance GPU compute service";
        string memory endpoint = "https://api.example.com/gpu";
        string memory category = "compute";
        uint256 ratePerSecond = 1000;
        uint256 minDuration = 60;
        uint256 maxDuration = 3600;

        vm.prank(provider1);
        vm.expectEmit(true, true, false, true);
        emit ServiceRegistered(0, provider1, name, category, ratePerSecond);

        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            name,
            description,
            endpoint,
            category,
            usdc,
            ratePerSecond,
            minDuration,
            maxDuration
        );

        assertEq(serviceId, 0);

        ServiceRegistry.Service memory service = registry.getService(serviceId);
        assertEq(service.provider, provider1);
        assertEq(service.name, name);
        assertEq(service.description, description);
        assertEq(service.endpoint, endpoint);
        assertEq(service.category, category);
        assertEq(address(service.token), address(usdc));
        assertEq(service.ratePerSecond, ratePerSecond);
        assertEq(service.minDuration, minDuration);
        assertEq(service.maxDuration, maxDuration);
        assertTrue(service.isActive);
        assertFalse(service.isVerified);
        assertEq(service.totalStreams, 0);
    }

    function testRegisterServiceInsufficientFee() public {
        vm.prank(provider1);
        vm.expectRevert(ServiceRegistry.InsufficientRegistrationFee.selector);
        registry.registerService{value: REGISTRATION_FEE - 1}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );
    }

    function testRegisterServiceInvalidName() public {
        vm.prank(provider1);
        vm.expectRevert(ServiceRegistry.InvalidServiceName.selector);
        registry.registerService{value: REGISTRATION_FEE}(
            "",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );
    }

    function testRegisterServiceInvalidToken() public {
        vm.prank(provider1);
        vm.expectRevert(ServiceRegistry.InvalidToken.selector);
        registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            IERC20(address(0)),
            1000,
            60,
            3600
        );
    }

    function testRegisterServiceInvalidRate() public {
        vm.prank(provider1);
        vm.expectRevert(ServiceRegistry.InvalidRate.selector);
        registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            0,
            60,
            3600
        );
    }

    function testRegisterServiceInvalidDuration() public {
        vm.prank(provider1);
        vm.expectRevert(ServiceRegistry.InvalidDuration.selector);
        registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            3600,
            60 // maxDuration < minDuration
        );
    }

    function testRegisterMultipleServices() public {
        vm.startPrank(provider1);
        
        uint256 serviceId1 = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description 1",
            "https://api1.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        uint256 serviceId2 = registry.registerService{value: REGISTRATION_FEE}(
            "Data Storage",
            "Description 2",
            "https://api2.example.com",
            "storage",
            usdc,
            500,
            60,
            7200
        );

        vm.stopPrank();

        assertEq(serviceId1, 0);
        assertEq(serviceId2, 1);

        uint256[] memory providerServices = registry.getProviderServices(provider1);
        assertEq(providerServices.length, 2);
        assertEq(providerServices[0], 0);
        assertEq(providerServices[1], 1);
    }

    /*//////////////////////////////////////////////////////////////
                    SERVICE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateService() public {
        // Register service
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Old description",
            "https://old.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        // Update service
        string memory newName = "Premium GPU";
        string memory newDescription = "New description";
        string memory newEndpoint = "https://new.example.com";
        uint256 newRate = 2000;

        vm.prank(provider1);
        vm.expectEmit(true, true, false, false);
        emit ServiceUpdated(serviceId, provider1);
        
        registry.updateService(
            serviceId,
            newName,
            newDescription,
            newEndpoint,
            newRate,
            120,
            7200
        );

        ServiceRegistry.Service memory service = registry.getService(serviceId);
        assertEq(service.name, newName);
        assertEq(service.description, newDescription);
        assertEq(service.endpoint, newEndpoint);
        assertEq(service.ratePerSecond, newRate);
        assertEq(service.minDuration, 120);
        assertEq(service.maxDuration, 7200);
    }

    function testUpdateServiceUnauthorized() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        vm.prank(provider2);
        vm.expectRevert(ServiceRegistry.Unauthorized.selector);
        registry.updateService(
            serviceId,
            "New Name",
            "New Description",
            "https://new.example.com",
            2000,
            60,
            3600
        );
    }

    function testUpdateServiceNotFound() public {
        vm.prank(provider1);
        vm.expectRevert(ServiceRegistry.ServiceNotFound.selector);
        registry.updateService(
            999,
            "New Name",
            "New Description",
            "https://new.example.com",
            2000,
            60,
            3600
        );
    }

    /*//////////////////////////////////////////////////////////////
                    ACTIVE STATUS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetServiceActiveStatus() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        // Deactivate
        vm.prank(provider1);
        vm.expectEmit(true, false, false, true);
        emit ServiceActiveStatusChanged(serviceId, false);
        registry.setServiceActiveStatus(serviceId, false);

        ServiceRegistry.Service memory service = registry.getService(serviceId);
        assertFalse(service.isActive);

        // Reactivate
        vm.prank(provider1);
        registry.setServiceActiveStatus(serviceId, true);

        service = registry.getService(serviceId);
        assertTrue(service.isActive);
    }

    function testSetServiceActiveStatusUnauthorized() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        vm.prank(provider2);
        vm.expectRevert(ServiceRegistry.Unauthorized.selector);
        registry.setServiceActiveStatus(serviceId, false);
    }

    /*//////////////////////////////////////////////////////////////
                    STREAM RECORDING TESTS
    //////////////////////////////////////////////////////////////*/

    function testRecordStream() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        // Record a stream
        vm.prank(address(this));
        registry.recordStream(serviceId);

        ServiceRegistry.Service memory service = registry.getService(serviceId);
        assertEq(service.totalStreams, 1);

        // Record another
        vm.prank(address(this));
        registry.recordStream(serviceId);

        service = registry.getService(serviceId);
        assertEq(service.totalStreams, 2);
    }

    function testRecordStreamInactive() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        // Deactivate service
        vm.prank(provider1);
        registry.setServiceActiveStatus(serviceId, false);

        // Try to record stream
        vm.expectRevert(ServiceRegistry.ServiceNotActive.selector);
        registry.recordStream(serviceId);
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetProviderServices() public {
        vm.startPrank(provider1);
        uint256 serviceId1 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description 1",
            "https://api1.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        uint256 serviceId2 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 2",
            "Description 2",
            "https://api2.example.com",
            "storage",
            usdc,
            500,
            60,
            7200
        );
        vm.stopPrank();

        uint256[] memory services = registry.getProviderServices(provider1);
        assertEq(services.length, 2);
        assertEq(services[0], serviceId1);
        assertEq(services[1], serviceId2);
    }

    function testGetCategoryServices() public {
        vm.prank(provider1);
        uint256 serviceId1 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description 1",
            "https://api1.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        vm.prank(provider2);
        uint256 serviceId2 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 2",
            "Description 2",
            "https://api2.example.com",
            "compute",
            usdc,
            500,
            60,
            7200
        );

        uint256[] memory services = registry.getCategoryServices("compute");
        assertEq(services.length, 2);
        assertEq(services[0], serviceId1);
        assertEq(services[1], serviceId2);
    }

    function testGetActiveProviderServices() public {
        vm.startPrank(provider1);
        uint256 serviceId1 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description 1",
            "https://api1.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        uint256 serviceId2 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 2",
            "Description 2",
            "https://api2.example.com",
            "storage",
            usdc,
            500,
            60,
            7200
        );

        // Deactivate service 2
        registry.setServiceActiveStatus(serviceId2, false);
        vm.stopPrank();

        uint256[] memory activeServices = registry.getActiveProviderServices(provider1);
        assertEq(activeServices.length, 1);
        assertEq(activeServices[0], serviceId1);
    }

    function testGetVerifiedCategoryServices() public {
        vm.prank(provider1);
        uint256 serviceId1 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description 1",
            "https://api1.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        vm.prank(provider2);
        uint256 serviceId2 = registry.registerService{value: REGISTRATION_FEE}(
            "Service 2",
            "Description 2",
            "https://api2.example.com",
            "compute",
            usdc,
            500,
            60,
            7200
        );

        // Verify service 1
        vm.prank(owner);
        registry.setServiceVerification(serviceId1, true);

        uint256[] memory verifiedServices = registry.getVerifiedCategoryServices("compute");
        assertEq(verifiedServices.length, 1);
        assertEq(verifiedServices[0], serviceId1);
    }

    function testIsValidDuration() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        assertTrue(registry.isValidDuration(serviceId, 60));
        assertTrue(registry.isValidDuration(serviceId, 1800));
        assertTrue(registry.isValidDuration(serviceId, 3600));
        
        assertFalse(registry.isValidDuration(serviceId, 59));
        assertFalse(registry.isValidDuration(serviceId, 3601));
    }

    function testIsValidDurationUnlimitedMax() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            0 // Unlimited max duration
        );

        assertTrue(registry.isValidDuration(serviceId, 60));
        assertTrue(registry.isValidDuration(serviceId, 1_000_000));
        
        assertFalse(registry.isValidDuration(serviceId, 59));
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetServiceVerification() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ServiceVerificationChanged(serviceId, true);
        registry.setServiceVerification(serviceId, true);

        ServiceRegistry.Service memory service = registry.getService(serviceId);
        assertTrue(service.isVerified);
    }

    function testSetServiceVerificationUnauthorized() public {
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        vm.prank(provider2);
        vm.expectRevert();
        registry.setServiceVerification(serviceId, true);
    }

    function testSetRegistrationFee() public {
        uint256 newFee = 0.005 ether;

        vm.prank(owner);
        registry.setRegistrationFee(newFee);

        assertEq(registry.registrationFee(), newFee);
    }

    function testWithdrawFees() public {
        // Register a service to generate fees
        vm.prank(provider1);
        registry.registerService{value: REGISTRATION_FEE}(
            "Service 1",
            "Description",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        address payable recipient = payable(address(0x999));
        uint256 balanceBefore = recipient.balance;

        vm.prank(owner);
        registry.withdrawFees(recipient);

        assertEq(recipient.balance, balanceBefore + REGISTRATION_FEE);
        assertEq(address(registry).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullServiceLifecycle() public {
        // 1. Register service
        vm.prank(provider1);
        uint256 serviceId = registry.registerService{value: REGISTRATION_FEE}(
            "GPU Compute",
            "High-performance compute",
            "https://api.example.com",
            "compute",
            usdc,
            1000,
            60,
            3600
        );

        // 2. Owner verifies service
        vm.prank(owner);
        registry.setServiceVerification(serviceId, true);

        // 3. Record some streams
        registry.recordStream(serviceId);
        registry.recordStream(serviceId);

        // 4. Provider updates service
        vm.prank(provider1);
        registry.updateService(
            serviceId,
            "Premium GPU",
            "Updated description",
            "https://new-api.example.com",
            2000,
            120,
            7200
        );

        // 5. Temporarily deactivate
        vm.prank(provider1);
        registry.setServiceActiveStatus(serviceId, false);

        // 6. Reactivate
        vm.prank(provider1);
        registry.setServiceActiveStatus(serviceId, true);

        // Verify final state
        ServiceRegistry.Service memory service = registry.getService(serviceId);
        assertEq(service.name, "Premium GPU");
        assertEq(service.ratePerSecond, 2000);
        assertTrue(service.isActive);
        assertTrue(service.isVerified);
        assertEq(service.totalStreams, 2);
    }
}
