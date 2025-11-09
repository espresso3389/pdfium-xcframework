#!/bin/bash
set -e

# Configuration
VERSION="${VERSION:-144.0.7506.0}"
RELEASE_TAG="chromium/7506"
BASE_URL="https://github.com/bblanchon/pdfium-binaries/releases/download/${RELEASE_TAG}"
WORK_DIR="${WORK_DIR:-./build}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
XCFRAMEWORK_NAME="PDFium.xcframework"

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

    log_info "Creating framework for ${platform}-${arch}${variant:+-${variant}}..."

    # Extract framework name without .framework extension
    # The binary name MUST match the framework directory name for xcodebuild
    local framework_name=$(basename "$framework_path" .framework)
    local binary_name="${framework_name}"

    # Create framework structure
    mkdir -p "${framework_path}/Versions/A/Headers"
    mkdir -p "${framework_path}/Versions/A/Resources"

    # Copy dylib as the framework binary
    cp "$dylib_path" "${framework_path}/Versions/A/${binary_name}"

    # Note: Headers will be added at the XCFramework level to avoid duplication
    # We'll extract them separately and add with -headers flag to xcodebuild

    # Create symlinks
    cd "${framework_path}/Versions" && ln -sf "A" "Current" && cd - > /dev/null
    cd "${framework_path}" && ln -sf "Versions/Current/${binary_name}" "${binary_name}" && cd - > /dev/null
    cd "${framework_path}" && ln -sf "Versions/Current/Headers" "Headers" && cd - > /dev/null
    cd "${framework_path}" && ln -sf "Versions/Current/Resources" "Resources" && cd - > /dev/null

    # Create Info.plist with proper platform variant support
    local supported_platforms="<string>${platform}</string>"
    if [ "$variant" = "catalyst" ]; then
        supported_platforms="<string>MacOSX</string>"
    fi

    # Create Info.plist
    cat > "${framework_path}/Versions/A/Resources/Info.plist" <<EOF
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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        ${supported_platforms}
    </array>
</dict>
</plist>
EOF
}

# Process architecture in parallel
process_architecture() {
    local platform=$1
    local arch=$2
    local tgz_file=$3
    local variant=$4
    local framework_name="PDFium-${platform}-${arch}${variant:+-${variant}}.framework"
    local extract_dir="${WORK_DIR}/extracted/${platform}-${arch}${variant:+-${variant}}"
    local framework_dir="${WORK_DIR}/frameworks/${framework_name}"

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

    create_framework "$dylib" "$framework_dir" "$platform" "$arch" "$variant"
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
    # Format: "final_framework_name|framework1|framework2|..."
    FAT_CONFIGS=(
        "PDFium-iPhoneSimulator.framework|PDFium-iPhoneSimulator-arm64.framework|PDFium-iPhoneSimulator-x64.framework"
        "PDFium-MacOSX-catalyst.framework|PDFium-MacOSX-arm64-catalyst.framework|PDFium-MacOSX-x64-catalyst.framework"
        "PDFium-MacOSX.framework|PDFium-MacOSX-arm64.framework|PDFium-MacOSX-x64.framework"
    )

    framework_paths=()

    # Create fat frameworks
    for fat_config in "${FAT_CONFIGS[@]}"; do
        IFS='|' read -r fat_name framework1 framework2 <<< "$fat_config"

        framework1_path="${WORK_DIR}/frameworks/${framework1}"
        framework2_path="${WORK_DIR}/frameworks/${framework2}"
        fat_path="${WORK_DIR}/frameworks/${fat_name}"

        if [ ! -d "$framework1_path" ] || [ ! -d "$framework2_path" ]; then
            log_error "Missing frameworks for $fat_name"
            continue
        fi

        log_info "Creating fat framework: ${fat_name}"

        # Copy the first framework as the base
        cp -R "$framework1_path" "$fat_path"

        # Get binary names
        binary1=$(basename "$framework1" .framework)
        binary2=$(basename "$framework2" .framework)
        fat_binary=$(basename "$fat_name" .framework)

        # Use lipo to combine the binaries
        lipo -create \
            "${framework1_path}/Versions/A/${binary1}" \
            "${framework2_path}/Versions/A/${binary2}" \
            -output "${fat_path}/Versions/A/${fat_binary}"

        # Remove the old binary from the copied framework
        rm -f "${fat_path}/Versions/A/${binary1}"

        # Update the symlink to point to the new binary name
        rm -f "${fat_path}/${binary1}"
        rm -f "${fat_path}/${fat_binary}"
        cd "${fat_path}" && ln -sf "Versions/Current/${fat_binary}" "${fat_binary}" && cd - > /dev/null

        # Update Info.plist with new bundle executable name
        /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${fat_binary}" "${fat_path}/Resources/Info.plist" 2>/dev/null || true

        framework_paths+=("$fat_path")
    done

    # Add single-architecture framework (iOS device)
    framework_paths+=("${WORK_DIR}/frameworks/PDFium-iPhoneOS-arm64.framework")

    # Extract headers once for the XCFramework
    log_info "Extracting headers for XCFramework..."
    HEADERS_DIR="${WORK_DIR}/headers"
    mkdir -p "$HEADERS_DIR"

    # Find any framework path file to get headers from
    first_config="${CONFIGS[0]}"
    IFS='|' read -r config tgz_file _ _ _ <<< "$first_config"

    if [ -f "${WORK_DIR}/.framework_path_${config}" ]; then
        first_framework=$(cat "${WORK_DIR}/.framework_path_${config}")
        # Get the extraction directory from the framework path
        first_extract_dir=$(echo "$first_framework" | sed "s|${WORK_DIR}/frameworks/PDFium-\([^.]*\)\.framework|${WORK_DIR}/extracted/\1|")

        # Find the dylib to locate headers
        first_dylib=$(find "${first_extract_dir}" \( -name "*.dylib" -o -name "*.a" \) | head -n 1)
        if [ -n "$first_dylib" ]; then
            extract_root=$(dirname "$(dirname "$first_dylib")")
            if [ -d "${extract_root}/include" ]; then
                cp -R "${extract_root}/include"/* "$HEADERS_DIR/"
                log_info "Headers extracted to ${HEADERS_DIR}"
            fi
        fi
    fi

    # Create xcframework
    log_info "Creating XCFramework..."
    xcodebuild_args=(-create-xcframework)

    for framework in "${framework_paths[@]}"; do
        xcodebuild_args+=(-framework "$framework")
    done

    # Add headers at XCFramework level if they exist
    if [ -d "$HEADERS_DIR" ] && [ "$(ls -A "$HEADERS_DIR")" ]; then
        xcodebuild_args+=(-headers "$HEADERS_DIR")
    fi

    xcodebuild_args+=(-output "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}")
    
    # Remove existing xcframework if it exists
    if [ -d "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}" ]; then
        rm -rf "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}"
    fi
    
    xcodebuild "${xcodebuild_args[@]}"
    
    log_info "✅ XCFramework created successfully at ${OUTPUT_DIR}/${XCFRAMEWORK_NAME}"
    
    # Cleanup
    cleanup
    
    log_info "Build complete!"
}

# Run main function
main "$@"

