# PDFium XCFramework

Pre-built PDFium XCFramework for iOS, macOS, and Mac Catalyst.

## Features

- **Universal Binary**: Supports all architectures (arm64, x86_64)
- **Multiple Platforms**:
  - iOS Device (arm64) - Minimum iOS 13.0
  - iOS Simulator (arm64, x86_64) - Minimum iOS 13.0
  - macOS (arm64, x86_64) - Minimum macOS 10.15
  - Mac Catalyst (arm64, x86_64) - Minimum iOS 13.0
- **Easy Integration**: Works with Swift Package Manager, CocoaPods, or manual installation
- **Automated Builds**: GitHub Actions workflow for reproducible builds

## Installation

See [latest release](https://github.com/espresso3389/pdfium-xcframework/releases/latest).

## Building from Source

### Prerequisites

- macOS with Xcode installed
- Bash 3.2 or later (comes with macOS)
- Command Line Tools: `xcode-select --install`

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/espresso3389/pdfium-xcframework.git
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
