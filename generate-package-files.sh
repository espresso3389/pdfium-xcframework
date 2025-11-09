#!/bin/bash
set -e

# This script generates Package.swift and PDFium.podspec with correct URLs and checksums
# Run this after building and uploading a release to GitHub

# Configuration
VERSION="${VERSION:-144.0.7506.0}"
GITHUB_REPO="${GITHUB_REPO:-OWNER/REPO}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
XCFRAMEWORK_NAME="PDFium.xcframework"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

# Read version info from build output if available
if [ -f "${OUTPUT_DIR}/.version_info" ]; then
    log_info "Reading version info from build output..."
    source "${OUTPUT_DIR}/.version_info"
    log_info "Using ZIP_NAME from build: ${ZIP_NAME}"
else
    log_warning "No .version_info found, using default zip name"
    ZIP_NAME="${XCFRAMEWORK_NAME}.zip"
fi

# Check if zip exists
ZIP_FILE="${OUTPUT_DIR}/${ZIP_NAME}"
if [ ! -f "$ZIP_FILE" ]; then
    log_error "XCFramework zip not found at: $ZIP_FILE"
    log_error "Please run ./build.sh first to create the XCFramework"
    exit 1
fi

# Calculate checksum
log_info "Calculating checksum..."
CHECKSUM=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')
log_info "Checksum: ${CHECKSUM}"

# Get GitHub repo URL
if [ "$GITHUB_REPO" = "OWNER/REPO" ]; then
    log_warning "GITHUB_REPO is not set. Using placeholder 'OWNER/REPO'"
    log_warning "Set it with: export GITHUB_REPO=username/repository"
fi

RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${ZIP_NAME}"

log_info "Release URL: ${RELEASE_URL}"

# Generate Package.swift
log_info "Generating Package.swift..."
cat > Package.swift <<EOF
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PDFium",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "PDFium",
            targets: ["PDFium"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "PDFium",
            url: "${RELEASE_URL}",
            checksum: "${CHECKSUM}"
        )
    ]
)
EOF

log_info "✓ Package.swift generated"

# Generate PDFium.podspec
log_info "Generating PDFium.podspec..."
cat > PDFium.podspec <<EOF
Pod::Spec.new do |s|
  s.name             = 'PDFium'
  s.version          = '${VERSION}'
  s.summary          = 'PDFium XCFramework for iOS and macOS'
  s.description      = <<-DESC
    PDFium is an open-source PDF rendering engine from the Chromium project.
    This pod provides a pre-built XCFramework for iOS, macOS, and Mac Catalyst.
  DESC

  s.homepage         = 'https://github.com/${GITHUB_REPO}'
  s.license          = { :type => 'BSD-3-Clause', :file => 'LICENSE' }
  s.author           = { 'PDFium XCFramework' => 'https://github.com/${GITHUB_REPO}' }
  s.source           = {
    :http => '${RELEASE_URL}',
    :sha256 => '${CHECKSUM}'
  }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.vendored_frameworks = 'PDFium.xcframework'
  s.requires_arc = true
end
EOF

log_info "✓ PDFium.podspec generated"

# Generate update instructions
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Package files generated successfully!"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ""
log_info "Next steps:"
log_info "1. Create a GitHub release with tag: v${VERSION}"
log_info "2. Upload ${ZIP_FILE} to the release"
log_info "3. Commit and push the generated files:"
log_info "   git add Package.swift PDFium.podspec"
log_info "   git commit -m 'Update Package.swift and podspec for v${VERSION}'"
log_info "   git push"
log_info ""
log_info "Or if you've already created the release:"
log_info "   git add Package.swift PDFium.podspec"
log_info "   git commit -m 'Update Package.swift and podspec for v${VERSION}'"
log_info "   git push"
log_info ""
