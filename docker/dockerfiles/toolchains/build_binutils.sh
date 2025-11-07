#!/bin/bash

# Script to rebuild binutils from SRPM package

set -e

# Default values
BINUTILS_SRPM_URL="https://cdn-thirdparty.starrocks.com/centos7%2Fbinutils-2.30-108.el8.src.rpm"
RPMS_DIR="/opt/rpms"
SRPM_TEMP_FILE="/tmp/binutils.src.rpm"

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Function to display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --binutils-srpm-url URL    URL to download the binutils SRPM package"
    echo "  --rpms-dir DIR             Directory to store the generated RPMs (default: /opt/rpms)"
    echo "  --help                     Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  BINUTILS_SRPM_URL          Same as --binutils-srpm-url"
    echo "  RPMS_DIR                   Same as --rpms-dir"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --binutils-srpm-url)
            BINUTILS_SRPM_URL="$2"
            shift 2
            ;;
        --rpms-dir)
            RPMS_DIR="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        *)
            handle_error "Unknown option: $1"
            ;;
    esac
done

# Display build configuration
echo "Building binutils from SRPM with the following configuration:"
echo "- Binutils SRPM URL: ${BINUTILS_SRPM_URL}"
echo "- RPMs output directory: ${RPMS_DIR}"

# Create workspace directory
mkdir -p "${RPMS_DIR}" || handle_error "Failed to create workspace directory"

# Download SRPM package
echo "Downloading binutils SRPM package..."
curl -s -L --retry 3 --retry-delay 5 --max-time 300 "${BINUTILS_SRPM_URL}" -o "${SRPM_TEMP_FILE}" || handle_error "Failed to download binutils SRPM"

# Rebuild the SRPM package
echo "Rebuilding binutils SRPM package..."
rpmbuild --rebuild "${SRPM_TEMP_FILE}" || handle_error "Failed to rebuild binutils SRPM"

# Move the resulting RPMs to the RPMs directory
echo "Moving generated RPMs to RPMs directory..."
mkdir -p "${RPMS_DIR}" || handle_error "Failed to create RPMs directory"
mv /root/rpmbuild/RPMS/*/*.rpm "${RPMS_DIR}/" || handle_error "Failed to move generated RPMs"

# List the generated RPMs
echo "Generated RPMs:"
ls -la "${RPMS_DIR}/"

# Clean up temporary files
rm -f "${SRPM_TEMP_FILE}" || echo "Warning: Failed to clean up temporary files"

echo "Binutils rebuild completed successfully!"
