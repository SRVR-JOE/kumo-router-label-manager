"""Custom exception hierarchy for the KUMO Router Management System.

This module defines all custom exceptions used throughout the system,
providing specific error types for different failure scenarios.
"""


class KUMOException(Exception):
    """Base exception class for all KUMO-related errors.

    All custom exceptions in the KUMO system inherit from this base class,
    allowing for easy catching of all system-specific errors.

    Attributes:
        message: Human-readable error message
        details: Optional dictionary containing additional error details
    """

    def __init__(self, message: str, details: dict = None) -> None:
        """Initialize the exception.

        Args:
            message: Human-readable error message
            details: Optional dictionary containing additional error details
        """
        self.message = message
        self.details = details or {}
        super().__init__(self.message)

    def __str__(self) -> str:
        """String representation of the exception."""
        if self.details:
            details_str = ", ".join(f"{k}={v}" for k, v in self.details.items())
            return f"{self.message} ({details_str})"
        return self.message


class KUMOConnectionError(KUMOException):
    """Exception raised for router connection errors.

    This exception is raised when there are problems connecting to the KUMO router,
    including network errors, authentication failures, or timeout issues.

    Attributes:
        router_ip: IP address of the router that failed to connect
        error_code: Optional error code for specific failure types
    """

    def __init__(
        self,
        message: str,
        router_ip: str = None,
        error_code: str = None,
        details: dict = None
    ) -> None:
        """Initialize the connection error.

        Args:
            message: Human-readable error message
            router_ip: IP address of the router
            error_code: Optional error code
            details: Optional additional error details
        """
        self.router_ip = router_ip
        self.error_code = error_code

        error_details = details or {}
        if router_ip:
            error_details["router_ip"] = router_ip
        if error_code:
            error_details["error_code"] = error_code

        super().__init__(message, error_details)


class KUMOValidationError(KUMOException):
    """Exception raised for data validation errors.

    This exception is raised when validation of labels, configuration,
    or other data fails validation rules.

    Attributes:
        field: Name of the field that failed validation
        value: The invalid value
        validation_errors: List of specific validation error messages
    """

    def __init__(
        self,
        message: str,
        field: str = None,
        value: any = None,
        validation_errors: list = None,
        details: dict = None
    ) -> None:
        """Initialize the validation error.

        Args:
            message: Human-readable error message
            field: Name of the field that failed validation
            value: The invalid value
            validation_errors: List of specific validation errors
            details: Optional additional error details
        """
        self.field = field
        self.value = value
        self.validation_errors = validation_errors or []

        error_details = details or {}
        if field:
            error_details["field"] = field
        if value is not None:
            error_details["value"] = str(value)
        if validation_errors:
            error_details["validation_errors"] = validation_errors

        super().__init__(message, error_details)


class KUMOFileError(KUMOException):
    """Exception raised for file operation errors.

    This exception is raised when file operations fail, including
    reading, writing, parsing, or access permission issues.

    Attributes:
        file_path: Path to the file that caused the error
        operation: The file operation that failed (e.g., 'read', 'write')
        original_exception: The original exception that caused this error
    """

    def __init__(
        self,
        message: str,
        file_path: str = None,
        operation: str = None,
        original_exception: Exception = None,
        details: dict = None
    ) -> None:
        """Initialize the file error.

        Args:
            message: Human-readable error message
            file_path: Path to the file
            operation: File operation that failed
            original_exception: Original exception that caused this error
            details: Optional additional error details
        """
        self.file_path = file_path
        self.operation = operation
        self.original_exception = original_exception

        error_details = details or {}
        if file_path:
            error_details["file_path"] = file_path
        if operation:
            error_details["operation"] = operation
        if original_exception:
            error_details["original_error"] = str(original_exception)

        super().__init__(message, error_details)
