// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {NovusAcademyCertificate} from "../src/NovusAcademyCertificate.sol";

contract NovusAcademyCertificateTest is Test {
    NovusAcademyCertificate public certificate;

    address public owner = address(1);
    address public platform = address(2);
    address public student = address(3);
    address public unauthorizedUser = address(4);

    uint256 public courseId = 1;
    string public metadataURI = "ipfs://QmTest";

    event CertificateMinted(address indexed student, uint256 courseId, uint256 certificateId);
    event PlatformAddressChanged(address indexed oldPlatform, address indexed newPlatform);

    function setUp() public {
        vm.startPrank(owner);
        certificate = new NovusAcademyCertificate();
        vm.stopPrank();
    }

    // Test initial state
    function testInitialState() public {
        assertEq(certificate.name(), "Novus Academy Certificate");
        assertEq(certificate.symbol(), "NAC");
        assertTrue(certificate.paused());
        assertEq(certificate.owner(), owner);
        assertFalse(certificate.isPlatformSet());
    }

    // Test setting platform address
    function testSetPlatformAddress() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, false);
        emit PlatformAddressChanged(address(0), platform);

        certificate.setPlatformAddress(platform);

        assertTrue(certificate.isPlatformSet());
        assertFalse(certificate.paused());
        vm.stopPrank();
    }

    // Test only owner can set platform address
    function testOnlyOwnerCanSetPlatformAddress() public {
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Ownable: caller is not the owner");
        certificate.setPlatformAddress(platform);
        vm.stopPrank();
    }

    // Test cannot set zero address as platform
    function testCannotSetZeroAddressAsPlatform() public {
        vm.startPrank(owner);
        vm.expectRevert("NAC: platform address cannot be zero");
        certificate.setPlatformAddress(address(0));
        vm.stopPrank();
    }

    // Test pause and unpause
    function testPauseAndUnpause() public {
        // Set platform address first
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);

        // Test pause
        certificate.pause();
        assertTrue(certificate.paused());

        // Test unpause
        certificate.unpause();
        assertFalse(certificate.paused());
        vm.stopPrank();
    }

    // Test cannot unpause without platform address set
    function testCannotUnpauseWithoutPlatformAddress() public {
        // Certificate is already paused by default
        vm.startPrank(owner);
        vm.expectRevert("NAC: platform address not set");
        certificate.unpause();
        vm.stopPrank();
    }

    // Test minting certificate success
    function testMintCertificate() public {
        // Setup: Set platform address and unpause
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);
        vm.stopPrank();

        // Mint certificate as platform
        vm.startPrank(platform);

        vm.expectEmit(true, true, false, true);
        emit CertificateMinted(student, courseId, 1);

        uint256 certificateId = certificate.mintCertificate(student, courseId, metadataURI);

        assertEq(certificateId, 1);
        assertEq(certificate.ownerOf(1), student);
        assertEq(certificate.tokenURI(1), metadataURI);
        vm.stopPrank();

        // Check certificate course
        assertEq(certificate.getCertificateCourse(1), courseId);

        // Check student certificates
        uint256[] memory studentCerts = certificate.getStudentCertificates(student);
        assertEq(studentCerts.length, 1);
        assertEq(studentCerts[0], 1);

        // Check verification
        assertTrue(certificate.verifyCourseCompletion(student, courseId));
        assertFalse(certificate.verifyCourseCompletion(student, 999)); // Non-existent course
    }

    // Test only platform can mint certificates
    function testOnlyPlatformCanMintCertificates() public {
        // Setup: Set platform address and unpause
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);
        vm.stopPrank();

        // Try to mint as unauthorized user
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("NAC: caller is not the platform");
        certificate.mintCertificate(student, courseId, metadataURI);
        vm.stopPrank();
    }

    // Test cannot mint when paused
    function testCannotMintWhenPaused() public {
        // Setup: Set platform address
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);
        certificate.pause();
        vm.stopPrank();

        // Try to mint as platform but contract is paused
        vm.startPrank(platform);
        vm.expectRevert("Pausable: paused");
        certificate.mintCertificate(student, courseId, metadataURI);
        vm.stopPrank();
    }

    // Test cannot mint with empty metadata URI
    function testCannotMintWithEmptyMetadataURI() public {
        // Setup: Set platform address and unpause
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);
        vm.stopPrank();

        // Try to mint with empty metadata URI
        vm.startPrank(platform);
        vm.expectRevert("NAC: empty metadata URI");
        certificate.mintCertificate(student, courseId, "");
        vm.stopPrank();
    }

    // Test cannot mint to zero address
    function testCannotMintToZeroAddress() public {
        // Setup: Set platform address and unpause
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);
        vm.stopPrank();

        // Try to mint to zero address
        vm.startPrank(platform);
        vm.expectRevert("NAC: cannot mint to zero address");
        certificate.mintCertificate(address(0), courseId, metadataURI);
        vm.stopPrank();
    }

    // Test multiple certificate minting for the same student
    function testMultipleCertificatesForStudent() public {
        // Setup: Set platform address and unpause
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);
        vm.stopPrank();

        // Mint multiple certificates
        vm.startPrank(platform);

        certificate.mintCertificate(student, 1, "ipfs://Qm1");
        certificate.mintCertificate(student, 2, "ipfs://Qm2");
        certificate.mintCertificate(student, 3, "ipfs://Qm3");

        vm.stopPrank();

        // Check student certificates
        uint256[] memory studentCerts = certificate.getStudentCertificates(student);
        assertEq(studentCerts.length, 3);
        assertEq(studentCerts[0], 1);
        assertEq(studentCerts[1], 2);
        assertEq(studentCerts[2], 3);

        // Check course verification for each course
        assertTrue(certificate.verifyCourseCompletion(student, 1));
        assertTrue(certificate.verifyCourseCompletion(student, 2));
        assertTrue(certificate.verifyCourseCompletion(student, 3));
    }

    // Test changing platform address
    function testChangePlatformAddress() public {
        address newPlatform = address(5);

        // Setup: Set platform address
        vm.startPrank(owner);
        certificate.setPlatformAddress(platform);

        // Change platform address
        vm.expectEmit(true, true, false, false);
        emit PlatformAddressChanged(platform, newPlatform);

        certificate.setPlatformAddress(newPlatform);
        vm.stopPrank();

        // Try to mint as old platform (should fail)
        vm.startPrank(platform);
        vm.expectRevert("NAC: caller is not the platform");
        certificate.mintCertificate(student, courseId, metadataURI);
        vm.stopPrank();

        // Mint as new platform (should succeed)
        vm.startPrank(newPlatform);
        uint256 certificateId = certificate.mintCertificate(student, courseId, metadataURI);
        assertEq(certificateId, 1);
        vm.stopPrank();
    }
}
