# PDFium XCFramework

Pre-built PDFium XCFramework for iOS, macOS, and Mac Catalyst.

## Features

- **Universal Binary**: Supports all architectures (arm64, x86_64)
- **Multiple Platforms**:
  - iOS Device (arm64)
  - iOS Simulator (arm64, x86_64)
  - macOS (arm64, x86_64)
  - Mac Catalyst (arm64, x86_64)
- **Easy Integration**: Works with Swift Package Manager, CocoaPods, or manual installation
- **Automated Builds**: GitHub Actions workflow for reproducible builds

## Installation

### Swift Package Manager (Recommended)

1. Download `Package.swift` from the [latest release](https://github.com/OWNER/REPO/releases)
2. Add it to your project root
3. The Package.swift contains the correct URL and checksum for the XCFramework

Or manually add to your existing `Package.swift`:

```swift
dependencies: [
    .binaryTarget(
        name: "PDFium",
        url: "https://github.com/OWNER/REPO/releases/download/vVERSION/PDFium.xcframework.zip",
        checksum: "CHECKSUM_FROM_RELEASE"
    )
]
```

### CocoaPods

1. Download `PDFium.podspec` from the [latest release](https://github.com/OWNER/REPO/releases)
2. Add to your `Podfile`:

```ruby
pod 'PDFium', :podspec => 'path/to/PDFium.podspec'
```

3. Run:

```bash
pod install
```

### Manual Installation

1. Download the latest `PDFium.xcframework.zip` from [Releases](https://github.com/OWNER/REPO/releases)
2. Verify the checksum:
   ```bash
   shasum -a 256 -c PDFium.xcframework.zip.sha256
   ```
3. Unzip the archive
4. Drag `PDFium.xcframework` into your Xcode project
5. In your target's General tab, add it to "Frameworks, Libraries, and Embedded Content"

## Usage

Import PDFium in your Swift code:

```swift
import PDFium

// Use PDFium APIs
// See https://pdfium.googlesource.com/pdfium/ for documentation
```

## Building from Source

### Prerequisites

- macOS with Xcode installed
- Bash 3.2 or later (comes with macOS)
- Command Line Tools: `xcode-select --install`

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/OWNER/REPO.git
   cd pdfium-xcframework
   ```

2. Run the build script:
   ```bash
   ./build.sh
   ```

3. The XCFramework will be created in `./output/PDFium.xcframework`

### Environment Variables

You can customize the build by setting environment variables:

```bash
# PDFium version to download
export VERSION="144.0.7506.0"

# Release tag from pdfium-binaries repo
export RELEASE_TAG="chromium/7506"

# Build and output directories
export WORK_DIR="./build"
export OUTPUT_DIR="./output"

./build.sh
```

## GitHub Actions Workflow

This repository includes a GitHub Actions workflow that automatically builds and releases the XCFramework.

### Automatic Release (on tag push)

```bash
git tag v144.0.7506.0
git push origin v144.0.7506.0
```

The workflow will:
1. Build the XCFramework
2. Create a zip archive with SHA256 checksum
3. **Auto-generate Package.swift and PDFium.podspec** with correct URLs and checksums
4. Create a GitHub release with all artifacts (zip, checksum, Package.swift, PDFium.podspec)

### Manual Build

You can also trigger the workflow manually from the Actions tab with custom version and release tag parameters.

### Local Package File Generation

After building locally, you can generate Package.swift and PDFium.podspec:

```bash
# Build the XCFramework
./build.sh

# Generate package files
export GITHUB_REPO="username/repository"
./generate-package-files.sh
```

## Verification

After downloading a release, verify the integrity:

```bash
# Download both the zip and checksum files
curl -LO https://github.com/OWNER/REPO/releases/download/vVERSION/PDFium.xcframework.zip
curl -LO https://github.com/OWNER/REPO/releases/download/vVERSION/PDFium.xcframework.zip.sha256

# Verify checksum
shasum -a 256 -c PDFium.xcframework.zip.sha256
```

Expected output: `PDFium.xcframework.zip: OK`

## Source

This project packages pre-built PDFium binaries from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) into an XCFramework format for easy integration with iOS and macOS projects.

## License

PDFium is licensed under the BSD 3-Clause License. See the [PDFium license](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE) for details.

This packaging script is provided as-is for convenience.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

- PDFium Documentation: https://pdfium.googlesource.com/pdfium/
- Issues: https://github.com/OWNER/REPO/issues
