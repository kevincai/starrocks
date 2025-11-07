#!/bin/bash

set -e

# Default values
DEFAULT_GCC_10_DOWNLOAD_URL="https://ftp.gnu.org/gnu/gcc/gcc-10.3.0/gcc-10.3.0.tar.gz"
DEFAULT_GCC_10_INSTALL_HOME="/opt/rh/gcc-toolset-10/root/usr"
DEFAULT_GCC_14_DOWNLOAD_URL="https://ftp.gnu.org/gnu/gcc/gcc-14.3.0/gcc-14.3.0.tar.gz"
DEFAULT_GCC_14_INSTALL_HOME="/opt/rh/gcc-toolset-10/root/usr"
DEFAULT_WORKSPACE_DIR="/workspace/gcc"
X86_64_CFLAGS=""
ARM64_CFLAGS="-march=armv8-a"

# Show help information
show_help() {
    echo "Usage: $0 --gcc-version VERSION [options]"
    echo ""
    echo "Options:"
    echo "  --gcc-version VERSION       Specify GCC version to build (10 or 14) [REQUIRED]"
    echo "  --gcc-download-url URL      Specify GCC download URL"
    echo "  --gcc-install-home PATH     Specify GCC installation path"
    echo "  --workspace-dir PATH        Specify workspace directory (default: $DEFAULT_WORKSPACE_DIR)"
    echo "  --bootstrap-gcc-path PATH   Specify bootstrap GCC path (required for gcc-14)"
    echo "  --x86_64_cflags FLAGS       Specify additional CFLAGS/CXXFLAGS for x86_64 architecture"
    echo "  --arm64_cflags FLAGS        Specify additional CFLAGS/CXXFLAGS for arm64 architecture"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment variables can also be used to set these values:"
    echo "  GCC_VERSION, GCC_DOWNLOAD_URL, GCC_INSTALL_HOME, WORKSPACE_DIR, BOOTSTRAP_GCC_PATH"
}

# Parse command line arguments using getopt
OPTIONS=$(getopt -o h --long gcc-version:,gcc-download-url:,gcc-install-home:,workspace-dir:,bootstrap-gcc-path:,x86_64_cflags:,arm64_cflags:,help -- "$@")

# Handle getopt errors
if [ $? -ne 0 ]; then
    echo "Error parsing options"
    show_help
    exit 1
fi

# Set parsed options
eval set -- "$OPTIONS"

# Process each option
while true; do
    case "$1" in
        --gcc-version)
            GCC_VERSION="$2"
            shift 2
            ;;
        --gcc-download-url)
            GCC_DOWNLOAD_URL="$2"
            shift 2
            ;;
        --gcc-install-home)
            GCC_INSTALL_HOME="$2"
            shift 2
            ;;
        --workspace-dir)
            WORKSPACE_DIR="$2"
            shift 2
            ;;
        --bootstrap-gcc-path)
            BOOTSTRAP_GCC_PATH="$2"
            shift 2
            ;;
        --x86_64_cflags)
            X86_64_CFLAGS="$2"
            shift 2
            ;;
        --arm64_cflags)
            ARM64_CFLAGS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Use environment variables for optional parameters
WORKSPACE_DIR=${WORKSPACE_DIR:-$DEFAULT_WORKSPACE_DIR}
BOOTSTRAP_GCC_PATH=${BOOTSTRAP_GCC_PATH:-""}

# Check if gcc-version is provided
if [[ -z "$GCC_VERSION" ]]; then
    echo "Error: --gcc-version is required"
    show_help
    exit 1
fi

GCC_WORKSPACE_NAME="gcc${GCC_VERSION}"

# Set version-specific defaults
if [[ "$GCC_VERSION" == "10" ]]; then
    GCC_DOWNLOAD_URL=${GCC_DOWNLOAD_URL:-$DEFAULT_GCC_10_DOWNLOAD_URL}
    GCC_INSTALL_HOME=${GCC_INSTALL_HOME:-$DEFAULT_GCC_10_INSTALL_HOME}
elif [[ "$GCC_VERSION" == "14" ]]; then
    GCC_DOWNLOAD_URL=${GCC_DOWNLOAD_URL:-$DEFAULT_GCC_14_DOWNLOAD_URL}
    GCC_INSTALL_HOME=${GCC_INSTALL_HOME:-$DEFAULT_GCC_14_INSTALL_HOME}

    # For gcc-14, bootstrap GCC is required
    if [[ -z "$BOOTSTRAP_GCC_PATH" ]]; then
        echo "Error: --bootstrap-gcc-path is required for building gcc-14"
        exit 1
    fi
else
    echo "Error: Unsupported GCC version: $GCC_VERSION. Supported versions are 10 and 14."
    exit 1
fi

# Detect architecture and set appropriate CFLAGS
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    EXTRA_CFLAGS="$X86_64_CFLAGS"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    EXTRA_CFLAGS="$ARM64_CFLAGS"
else
    echo "Warning: Unknown architecture $ARCH, using default CFLAGS"
    EXTRA_CFLAGS=""
fi

# For gcc-14, set CC and CXX to bootstrap GCC
if [[ "$GCC_VERSION" == "14" ]]; then
    export CC="$BOOTSTRAP_GCC_PATH/bin/gcc"
    export CXX="$BOOTSTRAP_GCC_PATH/bin/g++"
    echo "Using bootstrap GCC from $BOOTSTRAP_GCC_PATH"
fi

echo "========================================"
echo "Build Configuration:"
echo "- GCC Version: $GCC_VERSION"
echo "- GCC Download URL: $GCC_DOWNLOAD_URL"
echo "- GCC Install Home: $GCC_INSTALL_HOME"
echo "- Workspace Directory: $WORKSPACE_DIR"
echo "- Architecture: $ARCH"
echo "- Extra CFLAGS/CXXFLAGS: $EXTRA_CFLAGS"
if [[ "$GCC_VERSION" == "14" ]]; then
    echo "- Bootstrap GCC Path: $BOOTSTRAP_GCC_PATH"
fi
echo "========================================"

# Create workspace directory
echo "Creating workspace directory ..."
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Download and extract GCC
echo "Downloading GCC $GCC_VERSION..."
GCC_TAR_FILE="$WORKSPACE_DIR/gcc${GCC_VERSION}.tar.gz"
wget -c --progress=dot:mega --tries=3 --read-timeout=60 --connect-timeout=15 --no-check-certificate "$GCC_DOWNLOAD_URL" -O "$GCC_TAR_FILE"

echo "Extracting GCC..."
tar -xzf "$GCC_TAR_FILE" --strip-components=1

# Download prerequisites
echo "Downloading build prerequisites ..."
./contrib/download_prerequisites

# Configure GCC
echo "Configuring GCC ..."
CONFIG_OPTS="-v --disable-multilib --enable-languages=c,c++,lto --with-gcc-major-version-only \
    --prefix=/usr --enable-shared --enable-linker-build-id \
    --without-included-gettext --enable-threads=posix --enable-nls \
    --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes \
    --with-default-libstdcxx-abi=new --enable-gnu-unique-object --disable-vtable-verify \
    --enable-plugin --enable-default-pie --with-system-zlib \
    --with-target-system-zlib=auto --enable-multiarch \
    --disable-werror --enable-offload-defaulted \
    --enable-checking=release \
    --build=$ARCH-linux-gnu \
    --host=$ARCH-linux-gnu \
    --target=$ARCH-linux-gnu"

# Set CFLAGS/CXXFLAGS environment variables
if [[ -n "$EXTRA_CFLAGS" ]]; then
    export CFLAGS="$EXTRA_CFLAGS"
    export CXXFLAGS="$EXTRA_CFLAGS"
    echo "CFLAGS/CXXFLAGS set to: $EXTRA_CFLAGS"
fi

./configure $CONFIG_OPTS

# Compile GCC
JOBS=$(nproc)
echo "Compiling GCC (parallel jobs: $JOBS) ..."
make -j$JOBS

# Install GCC
echo "Installing GCC ..."
# Create installation directory if it doesn't exist
mkdir -p ${GCC_INSTALL_HOME}
# Install with DESTDIR to ensure files go to the correct location
make DESTDIR=${GCC_INSTALL_HOME} install-strip

# Clean up
echo "Cleaning up ..."
rm -rf "${WORKSPACE_DIR}"

echo ""
echo "GCC $GCC_VERSION build completed successfully!"
echo "- Installation directory: ${GCC_INSTALL_HOME}"
echo "- Binary files have been stripped and optimized"
