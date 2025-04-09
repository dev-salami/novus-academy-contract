// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NovusAcademyCertificate
 * @dev ERC721 token for course completion certificates
 */
contract NovusAcademyCertificate is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    // Mapping from certificate ID to course ID
    mapping(uint256 => uint256) private _certificateToCourse;

    // Mapping from student address to array of certificate IDs
    mapping(address => uint256[]) private _studentCertificates;

    // Address of the NovusAcademyPlatform contract that can mint certificates
    address private _platformAddress;

    event CertificateMinted(address indexed student, uint256 courseId, uint256 certificateId);

    constructor() ERC721("Novus Academy Certificate", "NAC") Ownable(msg.sender) {}

    /**
     * @dev Sets the platform address that is authorized to mint certificates
     * @param platformAddress Address of the NovusAcademyPlatform contract
     */
    function setPlatformAddress(address platformAddress) external onlyOwner {
        _platformAddress = platformAddress;
    }

    /**
     * @dev Mints a new certificate NFT
     * @param student Address of the student who completed the course
     * @param courseId ID of the completed course
     * @param metadataURI IPFS URI to the certificate metadata
     * @return certificateId ID of the minted certificate
     */
    function mintCertificate(address student, uint256 courseId, string memory metadataURI) external returns (uint256) {
        require(msg.sender == _platformAddress, "Only platform can mint certificates");

        _tokenIds.increment();
        uint256 certificateId = _tokenIds.current();

        _mint(student, certificateId);
        _setTokenURI(certificateId, metadataURI);

        _certificateToCourse[certificateId] = courseId;
        _studentCertificates[student].push(certificateId);

        emit CertificateMinted(student, courseId, certificateId);

        return certificateId;
    }

    /**
     * @dev Gets the course ID for a certificate
     * @param certificateId ID of the certificate
     * @return courseId ID of the course
     */
    function getCertificateCourse(uint256 certificateId) external view returns (uint256) {
        require(_exists(certificateId), "Certificate does not exist");
        return _certificateToCourse[certificateId];
    }

    /**
     * @dev Gets all certificates owned by a student
     * @param student Address of the student
     * @return array of certificate IDs
     */
    function getStudentCertificates(address student) external view returns (uint256[] memory) {
        return _studentCertificates[student];
    }

    /**
     * @dev Verifies if a student has completed a specific course
     * @param student Address of the student
     * @param courseId ID of the course
     * @return bool True if the student has completed the course
     */
    function verifyCourseCompletion(address student, uint256 courseId) external view returns (bool) {
        uint256[] memory certificates = _studentCertificates[student];

        for (uint256 i = 0; i < certificates.length; i++) {
            if (_certificateToCourse[certificates[i]] == courseId) {
                return true;
            }
        }

        return false;
    }
}

/**
 * @title NovusAcademyFactory
 * @dev Factory contract to deploy the entire Novus Academy+ system
 */
contract NovusAcademyFactory {
    event PlatformDeployed(address certificateContract, address platformContract);

    /**
     * @dev Deploys the Novus Academy+ platform
     * @return certificateAddress Address of the certificate contract
     * @return platformAddress Address of the platform contract
     */
    function deployPlatform() external returns (address certificateAddress, address platformAddress) {
        // Deploy certificate contract
        NovusAcademyCertificate certificateContract = new NovusAcademyCertificate();
        certificateAddress = address(certificateContract);

        // Deploy platform contract
        NovusAcademyPlatform platformContract = new NovusAcademyPlatform(certificateAddress);
        platformAddress = address(platformContract);

        // Set platform address in certificate contract
        certificateContract.setPlatformAddress(platformAddress);

        // Transfer ownership of certificate contract to msg.sender
        certificateContract.transferOwnership(msg.sender);

        // Transfer ownership of platform contract to msg.sender
        platformContract.transferOwnership(msg.sender);

        emit PlatformDeployed(certificateAddress, platformAddress);

        return (certificateAddress, platformAddress);
    }
}
