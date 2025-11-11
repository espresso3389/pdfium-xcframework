# Agent Instructions for PDFium XCFramework Releases

This document provides instructions for AI agents (like Claude Code) to autonomously handle release processes for the PDFium XCFramework project.

## Automated Release Process

When the user requests a new release, the agent should execute the following steps automatically:

### 1. Trigger GitHub Actions Workflow

Use the GitHub CLI to trigger the build workflow:

**For latest PDFium version:**
```bash
gh workflow run build-release.yml --field build_mode=latest
```

**For specific chromium version (e.g., 7520):**
```bash
gh workflow run build-release.yml --field build_mode=specific --field chromium_version=7520
```

### 2. Monitor Workflow Execution

Wait for the workflow to start and get its run ID:
```bash
sleep 3 && gh run list --workflow=build-release.yml --limit=1
```

Watch the workflow progress:
```bash
gh run watch <RUN_ID>
```

### 3. Verify Release Creation

After workflow completion, check the created release:
```bash
gh release list --limit 1
```

View release details:
```bash
gh release view <RELEASE_TAG>
```

### 4. Validate Release Assets

Download and verify Package.swift contains correct URLs:
```bash
gh release download <RELEASE_TAG> -p "Package.swift" -O /tmp/Package.swift
cat /tmp/Package.swift
```

Verify the URL format includes BUILD_ID:
- Format: `https://github.com/espresso3389/pdfium-xcframework/releases/download/v{VERSION}-{BUILD_ID}/PDFium-chromium-{VERSION}-{BUILD_ID}.xcframework.zip`
- Example: `https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7520.0-20251111-173323/PDFium-chromium-7520-20251111-173323.xcframework.zip`

### 5. Report Results

Provide a summary including:
- Release tag (e.g., `v144.0.7520.0-20251111-173323`)
- Release URL
- PDFium version
- Build ID
- Upstream source (e.g., `chromium/7520`)
- Verification status of all assets

## Release Tag Format

Releases use the following tag format to ensure uniqueness:

```
v{VERSION}-{BUILD_ID}
```

Where:
- `VERSION`: PDFium version (e.g., `144.0.7520.0`)
- `BUILD_ID`: Timestamp in format `YYYYMMDD-HHMMSS` (e.g., `20251111-173323`)

Example: `v144.0.7520.0-20251111-173323`

## Key Files in Release

Each release includes:
1. **PDFium-chromium-{VERSION}-{BUILD_ID}.xcframework.zip** - The XCFramework binary
2. **Package.swift** - Swift Package Manager configuration with correct URL and checksum
3. **PDFium.podspec** - CocoaPods specification with correct URL and checksum
4. **PDFium-chromium-{VERSION}-{BUILD_ID}.xcframework.zip.sha256** - SHA256 checksum file

## Important Notes

### Fixed Issues (as of 2025-11-12)
1. ✅ **App Store Validation Errors Fixed**:
   - Added `MinimumOSVersion` to Info.plist (iOS: 11.0, macOS: 10.13, Catalyst: 11.0)
   - Fixed `CFBundleShortVersionString` to use 3-part version format (144.0.7520 instead of 144.0.7520.0)
   - Added dSYM support (if available from upstream)

2. ✅ **Unique Release Tags**:
   - Each build creates a unique release with BUILD_ID timestamp
   - No more overwrites of existing releases
   - Multiple builds of the same PDFium version are supported

3. ✅ **Correct Release URLs**:
   - Package.swift and PDFium.podspec use full tag including BUILD_ID
   - Fixed confusion between upstream tag (`chromium/7520`) and our release tag

### Variable Naming
- `UPSTREAM_RELEASE_TAG`: The pdfium-binaries upstream tag (e.g., `chromium/7520`)
- `RELEASE_TAG` (in workflow): Our GitHub release tag (e.g., `v144.0.7520.0-20251111-173323`)

## Troubleshooting

### Workflow Fails to Fetch Latest Version
If the "latest" mode fails due to GitHub API rate limits:
1. Check the latest version manually:
   ```bash
   curl -s https://api.github.com/repos/bblanchon/pdfium-binaries/releases/latest | grep '"tag_name"'
   ```
2. Trigger with specific version instead:
   ```bash
   gh workflow run build-release.yml --field build_mode=specific --field chromium_version=<VERSION>
   ```

### Release Already Exists
This should not happen with the BUILD_ID system, but if it does:
1. Delete the existing release:
   ```bash
   gh release delete <RELEASE_TAG>
   git push --delete origin <RELEASE_TAG>
   ```
2. Re-trigger the workflow

## Workflow Files

- **Build Script**: `build.sh`
- **Package Generator**: `generate-package-files.sh`
- **GitHub Actions Workflow**: `.github/workflows/build-release.yml`

## Summary for Agents

When asked to create a release:
1. Trigger workflow with appropriate parameters
2. Monitor execution until completion
3. Verify release was created with correct tag format
4. Check Package.swift and PDFium.podspec URLs
5. Report success with release details

The entire process should be handled automatically without user intervention.
