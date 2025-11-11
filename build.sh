#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [CHROMIUM_VERSION|latest]

Build PDFium XCFramework for iOS, macOS, and Mac Catalyst.

Arguments:
    CHROMIUM_VERSION    The Chromium version number (e.g., 7506)
    latest              Automatically fetch and build the latest version

    If not provided, uses VERSION and RELEASE_TAG environment variables
    or shows this usage message.

Examples:
    $0 latest           Build the latest available PDFium version
    $0 7506             Build PDFium from chromium/7506
    $0 7595             Build PDFium from chromium/7595
    VERSION=144.0.7506.0 RELEASE_TAG=chromium/7506 $0
                        Build using environment variables

Environment Variables:
    VERSION             Full PDFium version (e.g., 144.0.7506.0)
    RELEASE_TAG         Release tag from pdfium-binaries (e.g., chromium/7506)
    WORK_DIR            Build directory (default: ./build)
    OUTPUT_DIR          Output directory (default: ./output)

EOF
    exit 1
}

# Fetch latest release tag from pdfium-binaries repository
fetch_latest_release() {
    log_info "Fetching latest release from pdfium-binaries..."

    # Get the latest release tag from GitHub API
    local latest_tag
    latest_tag=$(curl -s https://api.github.com/repos/bblanchon/pdfium-binaries/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$latest_tag" ]; then
        log_error "Failed to fetch latest release tag"
        exit 1
    fi

    log_info "Latest release tag: ${latest_tag}"

    # Extract chromium version from tag (e.g., "chromium/7506" -> "7506")
    local chromium_version
    chromium_version=$(echo "$latest_tag" | sed 's/chromium\///')

    if [ -z "$chromium_version" ]; then
        log_error "Failed to parse chromium version from tag: ${latest_tag}"
        exit 1
    fi

    echo "$chromium_version|$latest_tag"
}

# Parse command-line arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# Determine version from argument or environment
if [ -n "$1" ]; then
    if [ "$1" = "latest" ]; then
        # Fetch latest version
        latest_info=$(fetch_latest_release)
        IFS='|' read -r CHROMIUM_VERSION RELEASE_TAG <<< "$latest_info"
        VERSION="${VERSION:-144.0.${CHROMIUM_VERSION}.0}"
    else
        # Chromium version provided as argument
        CHROMIUM_VERSION="$1"

        # Derive VERSION and RELEASE_TAG from chromium version
        # Note: The major.minor.build format may vary, so we use a sensible default
        # Users can override with environment variables if needed
        VERSION="${VERSION:-144.0.${CHROMIUM_VERSION}.0}"
        RELEASE_TAG="chromium/${CHROMIUM_VERSION}"
    fi
else
    # Check if environment variables are set
    if [ -z "$VERSION" ] && [ -z "$RELEASE_TAG" ]; then
        # No parameters and no environment variables - show usage
        usage
    fi

    # Use environment variables or defaults
    VERSION="${VERSION:-144.0.7506.0}"
    RELEASE_TAG="${RELEASE_TAG:-chromium/7506}"
fi

# Configuration
BASE_URL="https://github.com/bblanchon/pdfium-binaries/releases/download/${RELEASE_TAG}"
WORK_DIR="${WORK_DIR:-./build}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
XCFRAMEWORK_NAME="PDFium.xcframework"

# Cleanup function
cleanup() {
    if [ -d "$WORK_DIR" ]; then
        log_info "Cleaning up work directory..."
        rm -rf "$WORK_DIR"
    fi
}

# Download and extract a tgz file
download_and_extract() {
    local file_name=$1
    local target_dir=$2
    local url="${BASE_URL}/${file_name}"

    log_info "Downloading ${file_name}..."
    if ! curl -L -f -o "${WORK_DIR}/${file_name}" "$url"; then
        log_error "Failed to download ${file_name}"
        return 1
    fi

    log_info "Extracting ${file_name}..."
    mkdir -p "$target_dir"
    if ! tar -xzf "${WORK_DIR}/${file_name}" -C "$target_dir"; then
        log_error "Failed to extract ${file_name}"
        return 1
    fi
}

# Create framework from dylib
create_framework() {
    local dylib_path=$1
    local framework_path=$2
    local platform=$3
    local arch=$4
    local variant=$5
    local extract_root=$6

    log_info "Creating framework for ${platform}-${arch}${variant:+-${variant}}..."

    # Extract framework name without .framework extension
    # The binary name MUST match the framework directory name for xcodebuild
    local framework_name=$(basename "$framework_path" .framework)
    local binary_name="${framework_name}"

    # Determine if this is an iOS framework (use shallow bundle) or macOS (use deep bundle)
    local is_ios=false
    if [ "$platform" = "iPhoneOS" ] || [ "$platform" = "iPhoneSimulator" ]; then
        is_ios=true
    fi

    # Create framework structure based on platform
    if [ "$is_ios" = true ]; then
        # iOS uses shallow bundle structure
        mkdir -p "${framework_path}/Headers"

        # Copy dylib as the framework binary (binary name = framework name)
        cp "$dylib_path" "${framework_path}/${binary_name}"

        # Fix install name for iOS framework
        chmod +w "${framework_path}/${binary_name}"
        # Try full path first, fall back to short path if header space is insufficient
        if ! install_name_tool -id "@rpath/${framework_name}.framework/${binary_name}" "${framework_path}/${binary_name}" 2>/dev/null; then
            log_warning "Full path doesn't fit, using short path @rpath/${binary_name}"
            install_name_tool -id "@rpath/${binary_name}" "${framework_path}/${binary_name}"
        fi
    else
        # macOS uses deep bundle structure with Versions
        mkdir -p "${framework_path}/Versions/A/Headers"
        mkdir -p "${framework_path}/Versions/A/Resources"

        # Copy dylib as the framework binary
        cp "$dylib_path" "${framework_path}/Versions/A/${binary_name}"

        # Fix install name for macOS framework
        chmod +w "${framework_path}/Versions/A/${binary_name}"
        # Try full path first, fall back to short path if header space is insufficient
        if ! install_name_tool -id "@rpath/${framework_name}.framework/${binary_name}" "${framework_path}/Versions/A/${binary_name}" 2>/dev/null; then
            log_warning "Full path doesn't fit, using short path @rpath/${binary_name}"
            install_name_tool -id "@rpath/${binary_name}" "${framework_path}/Versions/A/${binary_name}"
        fi
    fi

    # Copy headers - they're in the include directory at the extraction root
    # The dylib is typically in lib/libpdfium.dylib, headers are in include/
    # Note: Headers must be in each framework (can't be at XCFramework level for frameworks)
    local header_dir="${extract_root}/include"
    if [ -d "$header_dir" ]; then
        if [ "$is_ios" = true ]; then
            cp -R "${header_dir}"/* "${framework_path}/Headers/"
            find "${framework_path}/Headers" -type f \( -name "*.orig" -o -name "*.bak" -o -name "*~" -o -name ".DS_Store" \) -delete
        else
            cp -R "${header_dir}"/* "${framework_path}/Versions/A/Headers/"
            find "${framework_path}/Versions/A/Headers" -type f \( -name "*.orig" -o -name "*.bak" -o -name "*~" -o -name ".DS_Store" \) -delete
        fi
    else
        log_warning "Headers not found at ${header_dir}"
    fi

    # Look for and copy dSYM if available
    local dsym_dir="${extract_root}/lib/libpdfium.dylib.dSYM"
    if [ -d "$dsym_dir" ]; then
        log_info "Found dSYM, copying to framework..."
        local framework_dsym_path="${framework_path}.dSYM"
        cp -R "$dsym_dir" "$framework_dsym_path"

        # Update the dSYM binary reference to match framework name
        if [ -d "${framework_dsym_path}/Contents/Resources/DWARF" ]; then
            local old_binary_name=$(ls "${framework_dsym_path}/Contents/Resources/DWARF/" | head -n 1)
            if [ -n "$old_binary_name" ] && [ "$old_binary_name" != "$binary_name" ]; then
                mv "${framework_dsym_path}/Contents/Resources/DWARF/${old_binary_name}" \
                   "${framework_dsym_path}/Contents/Resources/DWARF/${binary_name}"
            fi
        fi
    else
        log_warning "No dSYM found at ${dsym_dir} - debug symbols will not be available"
    fi

    # Create symlinks for macOS frameworks only
    if [ "$is_ios" = false ]; then
        cd "${framework_path}/Versions" && ln -sf "A" "Current" && cd - > /dev/null
        cd "${framework_path}" && ln -sf "Versions/Current/${binary_name}" "${binary_name}" && cd - > /dev/null
        cd "${framework_path}" && ln -sf "Versions/Current/Headers" "Headers" && cd - > /dev/null
        cd "${framework_path}" && ln -sf "Versions/Current/Resources" "Resources" && cd - > /dev/null
    fi

    # Create Info.plist with proper platform variant support
    local supported_platforms="<string>${platform}</string>"
    if [ "$variant" = "catalyst" ]; then
        supported_platforms="<string>MacOSX</string>"
    fi

    # Determine Info.plist location based on bundle type
    local plist_path
    if [ "$is_ios" = true ]; then
        plist_path="${framework_path}/Info.plist"
    else
        plist_path="${framework_path}/Versions/A/Resources/Info.plist"
    fi

    # Convert VERSION to 3-part format for CFBundleShortVersionString
    # Apple requires max 3 non-negative integers (e.g., 144.0.7506.0 -> 144.0.7506)
    local short_version=$(echo "${VERSION}" | awk -F. '{print $1"."$2"."$3}')

    # Determine MinimumOSVersion based on platform
    local min_os_version="11.0"
    if [ "$platform" = "iPhoneOS" ] || [ "$platform" = "iPhoneSimulator" ]; then
        min_os_version="11.0"
    elif [ "$platform" = "MacOSX" ]; then
        if [ "$variant" = "catalyst" ]; then
            min_os_version="11.0"  # Mac Catalyst minimum
        else
            min_os_version="10.13"  # macOS minimum
        fi
    fi

    # Create Info.plist
    cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${binary_name}</string>
    <key>CFBundleIdentifier</key>
    <string>com.pdfium.PDFium</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PDFium</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${short_version}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        ${supported_platforms}
    </array>
    <key>MinimumOSVersion</key>
    <string>${min_os_version}</string>
</dict>
</plist>
EOF
}

# Verify XCFramework integrity
verify_xcframework() {
    local xcframework_path=$1

    log_info "Verifying XCFramework integrity..."

    if [ ! -d "$xcframework_path" ]; then
        log_error "XCFramework not found at: $xcframework_path"
        return 1
    fi

    # Check Info.plist exists
    if [ ! -f "${xcframework_path}/Info.plist" ]; then
        log_error "Missing Info.plist in XCFramework"
        return 1
    fi

    # Verify structure
    log_info "Checking XCFramework structure..."

    # Count available libraries
    local lib_count=$(find "$xcframework_path" -name "*.framework" -depth 2 | wc -l | tr -d ' ')
    log_info "Found ${lib_count} framework(s) in XCFramework"

    # Verify each framework
    local error_count=0
    for framework in "${xcframework_path}"/*/*.framework; do
        if [ -d "$framework" ]; then
            local framework_name=$(basename "$framework")
            log_info "Verifying framework: ${framework_name}"

            # Check for binary
            local binary_name=$(basename "$framework" .framework)
            local binary_path="${framework}/${binary_name}"

            if [ ! -f "$binary_path" ] && [ ! -L "$binary_path" ]; then
                log_error "  ✗ Binary not found: ${binary_name}"
                error_count=$((error_count + 1))
                continue
            fi

            # Resolve symlink if needed (macOS compatible)
            if [ -L "$binary_path" ]; then
                # Follow symlink to actual file
                local target
                target=$(readlink "$binary_path")
                if [[ "$target" = /* ]]; then
                    binary_path="$target"
                else
                    binary_path="$(dirname "$binary_path")/$target"
                fi
            fi

            # Verify it's a valid Mach-O file
            if file "$binary_path" | grep -q "Mach-O"; then
                log_info "  ✓ Valid Mach-O binary"

                # Show architectures
                local archs=$(lipo -info "$binary_path" 2>/dev/null | sed 's/.*: //')
                log_info "  ✓ Architectures: ${archs}"
            else
                log_error "  ✗ Invalid binary format"
                error_count=$((error_count + 1))
            fi

            # Check headers (follow symlinks)
            local headers_path="${framework}/Headers"
            if [ -L "$headers_path" ]; then
                # It's a symlink, resolve it
                local target
                target=$(readlink "$headers_path")
                if [[ "$target" = /* ]]; then
                    headers_path="$target"
                else
                    headers_path="$(dirname "$headers_path")/$target"
                fi
            fi

            if [ -d "$headers_path" ]; then
                local header_count=$(find "$headers_path" -name "*.h" 2>/dev/null | wc -l | tr -d ' ')
                log_info "  ✓ Headers: ${header_count} files"
            else
                log_warning "  ⚠ No headers directory found"
            fi

            # Check Info.plist
            if [ -f "${framework}/Resources/Info.plist" ] || [ -f "${framework}/Info.plist" ]; then
                log_info "  ✓ Info.plist found"
            else
                log_error "  ✗ Info.plist missing"
                error_count=$((error_count + 1))
            fi
        fi
    done

    if [ $error_count -eq 0 ]; then
        log_info "✅ XCFramework verification passed!"
        return 0
    else
        log_error "❌ XCFramework verification failed with ${error_count} error(s)"
        return 1
    fi
}

# Process architecture in parallel
process_architecture() {
    local platform=$1
    local arch=$2
    local tgz_file=$3
    local variant=$4
    # Use a unique internal name for the framework directory during build
    # but the framework itself will always be named "PDFium.framework"
    local internal_name="PDFium-${platform}-${arch}${variant:+-${variant}}"
    local framework_name="PDFium.framework"
    local extract_dir="${WORK_DIR}/extracted/${internal_name}"
    local framework_dir="${WORK_DIR}/frameworks/${internal_name}/${framework_name}"

    download_and_extract "$tgz_file" "$extract_dir"

    # Find the dylib file
    local dylib=$(find "$extract_dir" \( -name "*.dylib" -o -name "libpdfium.so" \) | head -n 1)
    if [ -z "$dylib" ]; then
        dylib=$(find "$extract_dir" -name "*.a" | head -n 1)
    fi

    if [ -z "$dylib" ]; then
        log_error "No library file found in $extract_dir"
        return 1
    fi

    create_framework "$dylib" "$framework_dir" "$platform" "$arch" "$variant" "$extract_dir"
    echo "$framework_dir"
}

# Main function
main() {
    log_info "Starting XCFramework build process..."
    log_info "Version: ${VERSION}"
    
    # Create directories
    mkdir -p "$WORK_DIR"
    mkdir -p "$OUTPUT_DIR"

    # Define architectures to process (compatible with Bash 3.2)
    # Format: "config_name|tgz_filename|platform_type|platform_variant|arch"
    CONFIGS=(
        "ios-catalyst-arm64|pdfium-ios-catalyst-arm64.tgz|ios|catalyst|arm64"
        "ios-catalyst-x64|pdfium-ios-catalyst-x64.tgz|ios|catalyst|x64"
        "ios-device-arm64|pdfium-ios-device-arm64.tgz|ios|device|arm64"
        "ios-simulator-arm64|pdfium-ios-simulator-arm64.tgz|ios|simulator|arm64"
        "ios-simulator-x64|pdfium-ios-simulator-x64.tgz|ios|simulator|x64"
        "mac-arm64|pdfium-mac-arm64.tgz|mac||arm64"
        "mac-x64|pdfium-mac-x64.tgz|mac||x64"
    )

    # Process architectures in parallel
    log_info "Processing architectures in parallel..."
    pids=()

    for config_line in "${CONFIGS[@]}"; do
        IFS='|' read -r config tgz_file platform_type platform_variant arch <<< "$config_line"

        # Determine platform string for framework and variant
        platform=""
        variant=""
        if [ "$platform_type" = "ios" ]; then
            if [ "$platform_variant" = "device" ]; then
                platform="iPhoneOS"
            elif [ "$platform_variant" = "simulator" ]; then
                platform="iPhoneSimulator"
            elif [ "$platform_variant" = "catalyst" ]; then
                platform="MacOSX"
                variant="catalyst"
            fi
        elif [ "$platform_type" = "mac" ]; then
            platform="MacOSX"
        fi

        if [ -z "$platform" ]; then
            log_error "Unable to determine platform for config: $config"
            continue
        fi

        (
            result=$(process_architecture "$platform" "$arch" "$tgz_file" "$variant")
            echo "$result" > "${WORK_DIR}/.framework_path_${config}"
        ) &
        pids+=($!)
    done

    # Wait for all parallel jobs to complete
    log_info "Waiting for parallel processing to complete..."
    for pid in "${pids[@]}"; do
        wait $pid || {
            log_error "Process $pid failed"
            exit 1
        }
    done

    # Create fat frameworks for platforms with multiple architectures
    log_info "Creating fat frameworks for multi-architecture platforms..."

    # Define which frameworks to combine into fat binaries
    # Format: "output_dir|internal_name1|internal_name2"
    FAT_CONFIGS=(
        "iPhoneSimulator|PDFium-iPhoneSimulator-arm64|PDFium-iPhoneSimulator-x64"
        "MacOSX-catalyst|PDFium-MacOSX-arm64-catalyst|PDFium-MacOSX-x64-catalyst"
        "MacOSX|PDFium-MacOSX-arm64|PDFium-MacOSX-x64"
    )

    framework_paths=()

    # Create fat frameworks
    for fat_config in "${FAT_CONFIGS[@]}"; do
        IFS='|' read -r output_dir internal1 internal2 <<< "$fat_config"

        framework1_path="${WORK_DIR}/frameworks/${internal1}/PDFium.framework"
        framework2_path="${WORK_DIR}/frameworks/${internal2}/PDFium.framework"
        fat_dir="${WORK_DIR}/frameworks/${output_dir}"
        fat_path="${fat_dir}/PDFium.framework"

        if [ ! -d "$framework1_path" ] || [ ! -d "$framework2_path" ]; then
            log_error "Missing frameworks for ${output_dir}"
            continue
        fi

        log_info "Creating fat framework: ${output_dir}/PDFium.framework"

        # Create output directory
        mkdir -p "$fat_dir"

        # Copy the first framework as the base
        cp -R "$framework1_path" "$fat_path"

        # Binary name is always "PDFium" (matching the framework name)
        local binary_name="PDFium"

        # Determine if this is iOS (shallow) or macOS (deep) bundle
        local is_ios=false
        if [[ "$output_dir" == *"iPhone"* ]]; then
            is_ios=true
        fi

        # Use lipo to combine the binaries
        if [ "$is_ios" = true ]; then
            # iOS shallow bundle - binary is at root
            lipo -create \
                "${framework1_path}/${binary_name}" \
                "${framework2_path}/${binary_name}" \
                -output "${fat_path}/${binary_name}"

            # Fix install name for iOS fat framework
            chmod +w "${fat_path}/${binary_name}"
            # Try full path first, fall back to short path if header space is insufficient
            if ! install_name_tool -id "@rpath/PDFium.framework/${binary_name}" "${fat_path}/${binary_name}" 2>/dev/null; then
                log_warning "Full path doesn't fit, using short path @rpath/${binary_name}"
                install_name_tool -id "@rpath/${binary_name}" "${fat_path}/${binary_name}"
            fi
        else
            # macOS deep bundle - binary is in Versions/A
            lipo -create \
                "${framework1_path}/Versions/A/${binary_name}" \
                "${framework2_path}/Versions/A/${binary_name}" \
                -output "${fat_path}/Versions/A/${binary_name}"

            # Fix install name for macOS fat framework
            chmod +w "${fat_path}/Versions/A/${binary_name}"
            # Try full path first, fall back to short path if header space is insufficient
            if ! install_name_tool -id "@rpath/PDFium.framework/${binary_name}" "${fat_path}/Versions/A/${binary_name}" 2>/dev/null; then
                log_warning "Full path doesn't fit, using short path @rpath/${binary_name}"
                install_name_tool -id "@rpath/${binary_name}" "${fat_path}/Versions/A/${binary_name}"
            fi
        fi

        framework_paths+=("$fat_path")
    done

    # Add single-architecture framework (iOS device)
    framework_paths+=("${WORK_DIR}/frameworks/PDFium-iPhoneOS-arm64/PDFium.framework")

    # Create xcframework
    log_info "Creating XCFramework..."
    xcodebuild_args=(-create-xcframework)

    for framework in "${framework_paths[@]}"; do
        xcodebuild_args+=(-framework "$framework")

        # Check if dSYM exists for this framework
        local dsym_path="${framework}.dSYM"
        if [ -d "$dsym_path" ]; then
            log_info "Including dSYM for $(basename "$framework")"
            xcodebuild_args+=(-debug-symbols "$dsym_path")
        fi
    done

    xcodebuild_args+=(-output "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}")

    # Remove existing xcframework if it exists
    if [ -d "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}" ]; then
        rm -rf "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}"
    fi

    xcodebuild "${xcodebuild_args[@]}"

    log_info "✅ XCFramework created successfully at ${OUTPUT_DIR}/${XCFRAMEWORK_NAME}"

    # Verify the XCFramework
    verify_xcframework "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}"

    # Create zip and checksum for distribution
    log_info "Creating distribution package..."

    # Generate build ID from timestamp (format: YYYYMMDD-HHMMSS)
    BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%d-%H%M%S)}"

    # Extract chromium version from RELEASE_TAG (e.g., "chromium/7506" -> "7506")
    CHROMIUM_VER=$(echo "$RELEASE_TAG" | sed 's/chromium\///')

    # Create zip name with chromium version and build ID
    # Format: PDFium-chromium-7506-20250209-143052.xcframework.zip
    ZIP_NAME="PDFium-chromium-${CHROMIUM_VER}-${BUILD_ID}.xcframework.zip"

    cd "${OUTPUT_DIR}"
    zip -r --symlinks "${ZIP_NAME}" "${XCFRAMEWORK_NAME}"
    CHECKSUM=$(shasum -a 256 "${ZIP_NAME}" | awk '{print $1}')
    echo "$CHECKSUM  ${ZIP_NAME}" > "${ZIP_NAME}.sha256"

    # Also create a symlink without build ID for convenience
    ln -sf "${ZIP_NAME}" "${XCFRAMEWORK_NAME}.zip"
    ln -sf "${ZIP_NAME}.sha256" "${XCFRAMEWORK_NAME}.zip.sha256"
    cd - > /dev/null

    log_info "Build ID: ${BUILD_ID}"
    log_info "Checksum: ${CHECKSUM}"

    # Save version information for CI/CD workflows (before cleanup)
    cat > "${OUTPUT_DIR}/.version_info" <<EOF
VERSION=${VERSION}
UPSTREAM_RELEASE_TAG=${RELEASE_TAG}
BUILD_ID=${BUILD_ID}
ZIP_NAME=${ZIP_NAME}
EOF

    # Cleanup
    cleanup

    log_info "Build complete!"
}

# Run main function
main "$@"

