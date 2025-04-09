/**
 * @title NovusAcademyPlatform
 * @dev Main contract for the Novus Academy+ platform
 */
contract NovusAcademyPlatform is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    Counters.Counter private _courseIds;

    // Certificate contract
    NovusAcademyCertificate private _certificateContract;

    // Platform fee percentage (in basis points, e.g., 250 = 2.5%)
    uint256 private _platformFeePercentage = 250;

    struct Course {
        uint256 id;
        string title;
        string description;
        string metadataURI; // IPFS URI to course metadata
        address author;
        uint256 price;
        bool isActive;
        uint256 totalEnrollments;
    }

    struct Enrollment {
        address student;
        uint256 enrollmentDate;
        bool completed;
        uint256 completionDate;
        bool certificateIssued;
        uint256 certificateId;
    }

    // Maps course ID to Course struct
    mapping(uint256 => Course) private _courses;

    // Maps course ID to array of enrolled students
    mapping(uint256 => address[]) private _courseEnrollments;

    // Maps course ID to mapping of student address to Enrollment struct
    mapping(uint256 => mapping(address => Enrollment)) private _enrollmentDetails;

    // Maps author address to array of created course IDs
    mapping(address => uint256[]) private _authorCourses;

    // Maps student address to array of enrolled course IDs
    mapping(address => uint256[]) private _studentCourses;

    // Maps author address to their earned balance
    mapping(address => uint256) private _authorBalances;

    // Events
    event CourseCreated(uint256 indexed courseId, address indexed author, string title, uint256 price);
    event CourseUpdated(uint256 indexed courseId, string title, uint256 price, bool isActive);
    event CourseEnrollment(uint256 indexed courseId, address indexed student, uint256 price);
    event CourseCompleted(uint256 indexed courseId, address indexed student);
    event CertificateIssued(uint256 indexed courseId, address indexed student, uint256 certificateId);
    event AuthorWithdrawal(address indexed author, uint256 amount);
    event PlatformFeeUpdated(uint256 newFeePercentage);

    constructor(address certificateContract) Ownable(msg.sender) {
        _certificateContract = NovusAcademyCertificate(certificateContract);
    }

    /**
     * @dev Updates the platform fee percentage
     * @param newFeePercentage New fee percentage in basis points (e.g., 250 = 2.5%)
     */
    function updatePlatformFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 1000, "Fee cannot exceed 10%");
        _platformFeePercentage = newFeePercentage;
        emit PlatformFeeUpdated(newFeePercentage);
    }

    /**
     * @dev Creates a new course
     * @param title Course title
     * @param description Course description
     * @param metadataURI IPFS URI to course metadata
     * @param price Course price in wei
     * @return courseId ID of the created course
     */
    function createCourse(string memory title, string memory description, string memory metadataURI, uint256 price)
        external
        returns (uint256)
    {
        _courseIds.increment();
        uint256 courseId = _courseIds.current();

        _courses[courseId] = Course({
            id: courseId,
            title: title,
            description: description,
            metadataURI: metadataURI,
            author: msg.sender,
            price: price,
            isActive: true,
            totalEnrollments: 0
        });

        _authorCourses[msg.sender].push(courseId);

        emit CourseCreated(courseId, msg.sender, title, price);

        return courseId;
    }

    /**
     * @dev Updates an existing course
     * @param courseId ID of the course to update
     * @param title New title (or empty string to keep existing)
     * @param description New description (or empty string to keep existing)
     * @param metadataURI New metadata URI (or empty string to keep existing)
     * @param price New price (or 0 to keep existing)
     * @param isActive New active status
     */
    function updateCourse(
        uint256 courseId,
        string memory title,
        string memory description,
        string memory metadataURI,
        uint256 price,
        bool isActive
    ) external {
        require(_courses[courseId].author == msg.sender, "Only author can update course");

        Course storage course = _courses[courseId];

        if (bytes(title).length > 0) {
            course.title = title;
        }

        if (bytes(description).length > 0) {
            course.description = description;
        }

        if (bytes(metadataURI).length > 0) {
            course.metadataURI = metadataURI;
        }

        if (price > 0) {
            course.price = price;
        }

        course.isActive = isActive;

        emit CourseUpdated(courseId, course.title, course.price, course.isActive);
    }

    /**
     * @dev Enrolls a student in a course
     * @param courseId ID of the course to enroll in
     */
    function enrollInCourse(uint256 courseId) external payable nonReentrant {
        Course storage course = _courses[courseId];

        require(course.isActive, "Course is not active");
        require(msg.value >= course.price, "Insufficient payment");
        require(_enrollmentDetails[courseId][msg.sender].student == address(0), "Already enrolled");

        // Calculate platform fee
        uint256 platformFee = (course.price * _platformFeePercentage) / 10000;
        uint256 authorPayment = course.price - platformFee;

        // Update author balance
        _authorBalances[course.author] += authorPayment;

        // Refund excess payment if any
        if (msg.value > course.price) {
            payable(msg.sender).transfer(msg.value - course.price);
        }

        // Record enrollment
        _enrollmentDetails[courseId][msg.sender] = Enrollment({
            student: msg.sender,
            enrollmentDate: block.timestamp,
            completed: false,
            completionDate: 0,
            certificateIssued: false,
            certificateId: 0
        });

        _courseEnrollments[courseId].push(msg.sender);
        _studentCourses[msg.sender].push(courseId);

        course.totalEnrollments++;

        emit CourseEnrollment(courseId, msg.sender, course.price);
    }

    /**
     * @dev Marks a course as completed for a student (only callable by the course author)
     * @param courseId ID of the completed course
     * @param student Address of the student
     * @param certificateURI IPFS URI to the certificate metadata
     */
    function completeCourse(uint256 courseId, address student, string memory certificateURI) external {
        Course storage course = _courses[courseId];
        require(course.author == msg.sender, "Only author can mark completion");

        Enrollment storage enrollment = _enrollmentDetails[courseId][student];
        require(enrollment.student != address(0), "Student not enrolled");
        require(!enrollment.completed, "Course already completed");

        enrollment.completed = true;
        enrollment.completionDate = block.timestamp;

        emit CourseCompleted(courseId, student);

        // Issue certificate
        uint256 certificateId = _certificateContract.mintCertificate(student, courseId, certificateURI);

        enrollment.certificateIssued = true;
        enrollment.certificateId = certificateId;

        emit CertificateIssued(courseId, student, certificateId);
    }

    /**
     * @dev Allows an author to withdraw their earned balance
     */
    function authorWithdraw() external nonReentrant {
        uint256 amount = _authorBalances[msg.sender];
        require(amount > 0, "No balance to withdraw");

        _authorBalances[msg.sender] = 0;

        payable(msg.sender).transfer(amount);

        emit AuthorWithdrawal(msg.sender, amount);
    }

    /**
     * @dev Allows the platform owner to withdraw accumulated platform fees
     */
    function platformWithdraw() external onlyOwner nonReentrant {
        uint256 platformBalance = address(this).balance;
        require(platformBalance > 0, "No balance to withdraw");

        payable(owner()).transfer(platformBalance);
    }

    /**
     * @dev Gets details of a course
     * @param courseId ID of the course
     * @return Course details
     */
    function getCourse(uint256 courseId) external view returns (Course memory) {
        return _courses[courseId];
    }

    /**
     * @dev Gets the enrollment details for a student in a course
     * @param courseId ID of the course
     * @param student Address of the student
     * @return Enrollment details
     */
    function getEnrollment(uint256 courseId, address student) external view returns (Enrollment memory) {
        return _enrollmentDetails[courseId][student];
    }

    /**
     * @dev Gets all courses created by an author
     * @param author Address of the author
     * @return Array of course IDs
     */
    function getAuthorCourses(address author) external view returns (uint256[] memory) {
        return _authorCourses[author];
    }

    /**
     * @dev Gets all courses enrolled by a student
     * @param student Address of the student
     * @return Array of course IDs
     */
    function getStudentCourses(address student) external view returns (uint256[] memory) {
        return _studentCourses[student];
    }

    /**
     * @dev Gets all students enrolled in a course
     * @param courseId ID of the course
     * @return Array of student addresses
     */
    function getCourseStudents(uint256 courseId) external view returns (address[] memory) {
        return _courseEnrollments[courseId];
    }

    /**
     * @dev Gets the current balance of an author
     * @param author Address of the author
     * @return Author's current balance
     */
    function getAuthorBalance(address author) external view returns (uint256) {
        return _authorBalances[author];
    }

    /**
     * @dev Gets the current platform fee percentage
     * @return Fee percentage in basis points
     */
    function getPlatformFeePercentage() external view returns (uint256) {
        return _platformFeePercentage;
    }
}
