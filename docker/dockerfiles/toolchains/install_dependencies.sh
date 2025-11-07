#!/bin/bash

set -e

# Default values for command line options
CMAKE_INSTALL_HOME="/opt/cmake"
JDK_INSTALL_HOME="/opt/jdk17"
MAVEN_INSTALL_HOME="/opt/maven"
MAVEN_VERSION="3.6.3"
CMAKE_URL="https://cmake.org/files/v3.31/cmake-3.31.9-linux-{arch}.tar.gz"
JDK_URL="http://cdn-thirdparty.starrocks.com/OpenJDK17U-jdk_{arch}_linux_hotspot_17.0.13_11.tar.gz"
CLANG_FORMAT_URL="http://cdn-thirdparty.starrocks.com/{arch}/clang-format"

# Function to display usage information
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "    --cmake-home <path>          Set CMake installation directory (default: $CMAKE_INSTALL_HOME)"
    echo "    --jdk-home <path>            Set JDK installation directory (default: $JDK_INSTALL_HOME)"
    echo "    --maven-home <path>          Set Maven installation directory (default: $MAVEN_INSTALL_HOME)"
    echo "    --maven-version <version>    Set Maven version (default: $MAVEN_VERSION)"
    echo "    --cmake-url <url>            Set custom CMake download URL (supports {arch} template)"
    echo "    --jdk-url <url>              Set custom JDK download URL (supports {arch} template)"
    echo "    --clang-format-url <url>     Set custom clang-format download URL (supports {arch} template, default: ${CLANG_FORMAT_URL})"
    echo "    -h, --help                   Display this help message"
    exit 1
}

# Parse command line options using getopt
if ! options=$(getopt -o h --long cmake-home:,jdk-home:,maven-home:,maven-version:,cmake-url:,jdk-url:,clang-format-url:,help -- "$@"); then
    echo "Error parsing command line options"
    usage
fi

eval set -- "$options"

while true; do
    case "$1" in
        --cmake-home)
            CMAKE_INSTALL_HOME="$2"
            shift 2
            ;;
        --jdk-home)
            JDK_INSTALL_HOME="$2"
            shift 2
            ;;
        --maven-home)
            MAVEN_INSTALL_HOME="$2"
            shift 2
            ;;
        --maven-version)
            MAVEN_VERSION="$2"
            shift 2
            ;;
        --cmake-url)
            CMAKE_URL="$2"
            shift 2
            ;;
        --jdk-url)
            JDK_URL="$2"
            shift 2
            ;;
        --clang-format-url)
            CLANG_FORMAT_URL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Detect architecture once for reuse throughout the script
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Create temp directory for downloads
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Define wget common options
WGET_OPTS="-c --progress=dot:mega --tries=3 --read-timeout=60 --connect-timeout=15 --no-check-certificate"

# Install CMake
echo "Installing CMake ..."
mkdir -p "$CMAKE_INSTALL_HOME"
CMAKE_TARBALL="$TEMP_DIR/cmake-3.31.9-linux-${ARCH}.tar.gz"

# Substitute {arch} template in custom URL
CMAKE_URL=$(echo "$CMAKE_URL" | sed "s/{arch}/$ARCH/g")

echo "Downloading CMake from: $CMAKE_URL"
echo "Installing to: $CMAKE_INSTALL_HOME"

wget $WGET_OPTS -O "$CMAKE_TARBALL" "$CMAKE_URL"
tar -xzf "$CMAKE_TARBALL" -C "$CMAKE_INSTALL_HOME" --strip-components=1
rm -f "$CMAKE_TARBALL"

# Force create symlink, overwriting if it exists
ln -sf "$CMAKE_INSTALL_HOME/bin/cmake" /usr/bin/cmake
echo "Created symlink /usr/bin/cmake -> $CMAKE_INSTALL_HOME/bin/cmake"

# Install JDK 17
echo "Installing JDK 17 ..."
mkdir -p "${JDK_INSTALL_HOME}"

# Substitute {arch} template in custom URL
JDK_URL=$(echo "$JDK_URL" | sed "s/{arch}/$ARCH/g")

JDK_TARBALL="$TEMP_DIR/jdk17.tar.gz"

echo "Downloading JDK 17 from: $JDK_URL"
echo "Installing to: $JDK_INSTALL_HOME"

wget $WGET_OPTS -O "$JDK_TARBALL" "$JDK_URL"
tar -xzf "$JDK_TARBALL" -C "${JDK_INSTALL_HOME}" --strip-components=1
rm -f "$JDK_TARBALL"

# Install Maven
echo "Installing Maven ..."
mkdir -p "${MAVEN_INSTALL_HOME}"

# Automatically assemble Maven URL based on Maven version
MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
MAVEN_TARBALL="$TEMP_DIR/apache-maven-${MAVEN_VERSION}-bin.tar.gz"

echo "Downloading Maven $MAVEN_VERSION from: $MAVEN_URL"
echo "Installing to: $MAVEN_INSTALL_HOME"

wget $WGET_OPTS -O "$MAVEN_TARBALL" "$MAVEN_URL"
tar -xzf "$MAVEN_TARBALL" -C "${MAVEN_INSTALL_HOME}" --strip-components=1
rm -f "$MAVEN_TARBALL"

# Force create symlink, overwriting if it exists
ln -sf "${MAVEN_INSTALL_HOME}/bin/mvn" /usr/bin/mvn
echo "Created symlink /usr/bin/mvn -> ${MAVEN_INSTALL_HOME}/bin/mvn"

# Install clang-format
echo "Installing clang-format ..."

# Substitute {arch} template in custom URL
DOWNLOAD_URL=$(echo "$CLANG_FORMAT_URL" | sed "s/{arch}/$ARCH/g")
echo "Downloading clang-format from: $DOWNLOAD_URL"

# Directly download to target location
wget $WGET_OPTS -O /usr/bin/clang-format "$DOWNLOAD_URL"
chmod +x /usr/bin/clang-format

echo "Installed clang-format to /usr/bin/clang-format"

echo "All dependencies installed successfully!"
