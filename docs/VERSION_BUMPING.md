# Version Bumping

## Automatic Build Number Increment

A script has been created at `scripts/bump_build_number.sh` to automatically increment the build number on each build.

### To Enable Automatic Version Bumping:

1. Open the Xcode project
2. Select the target (iosTrackerApp or watchTrackerApp Watch App)
3. Go to "Build Phases"
4. Click "+" and add a "New Run Script Phase"
5. Move it to be BEFORE "Compile Sources"
6. Add this script:

```bash
"${SRCROOT}/scripts/bump_build_number.sh"
```

### Manual Version Bumping

To manually bump versions using agvtool:

```bash
# Bump build number
agvtool next-version -all

# Set specific build number
agvtool new-version 42

# Set marketing version (e.g., 1.0, 1.1, 2.0)
agvtool new-marketing-version 1.1.0
```

### Current Versioning

- Marketing Version (CFBundleShortVersionString): 1.0
- Build Number (CFBundleVersion): 1

### Version Conventions

- **Patch (x.x.X)**: Bug fixes, minor tweaks (e.g., 1.0.0 → 1.0.1)
- **Minor (x.X.x)**: New features, UI changes (e.g., 1.0.0 → 1.1.0)
- **Major (X.x.x)**: Breaking changes, major refactors (e.g., 1.0.0 → 2.0.0)
