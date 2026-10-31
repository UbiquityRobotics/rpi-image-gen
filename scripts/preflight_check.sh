#!/usr/bin/env bash
# =============================================================================
# scripts/preflight_check.sh
# Fast pre-flight validation gate (< 5 seconds).
# Inspired by official raspberrypi/rpi-image-gen test/run-all.sh.
# Run in CI and locally before launching heavy bdebstrap/mmdebstrap builds.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo "=========================================================="
echo "          RUNNING FAST PRE-FLIGHT VALIDATION GATES        "
echo "=========================================================="

# 1. Check required tools
echo "[Check 1/6] Checking required host binaries..."
REQUIRED_TOOLS=("python3" "git" "ansible-playbook")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        if [ "$tool" = "ansible-playbook" ] && command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
            echo "  - INFO: Attempting auto-installation of ansible on host..."
            apt-get update -qq && apt-get install -y -qq ansible || true
        fi
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "  - ERROR: Required tool '$tool' is not installed on host! (Install via: sudo apt-get install -y ansible)" >&2
            exit 1
        fi
    fi
    echo "  - PASS: Found $tool"
done

# 2. Syntax-check Ansible Playbooks and Roles
echo "[Check 2/6] Validating Ansible syntax across all roles..."
if ! bash "${REPO_ROOT}/ansible/validate.sh"; then
    echo "  - ERROR: Ansible playbook validation failed!" >&2
    exit 1
fi
echo "  - PASS: Ansible playbooks and roles syntax verified."

# 3. Validate YAML syntax in meta/ and config/
echo "[Check 3/6] Validating YAML configuration files..."
python3 - <<'EOF'
import sys, glob, yaml

yaml_files = glob.glob("meta/**/*.yaml", recursive=True) + glob.glob("config/**/*.yaml", recursive=True)
errors = 0
for f in yaml_files:
    try:
        with open(f, "r") as fp:
            yaml.safe_load(fp)
    except Exception as e:
        print(f"  - ERROR parsing {f}: {e}", file=sys.stderr)
        errors += 1

if errors > 0:
    sys.exit(1)
print(f"  - PASS: Successfully validated {len(yaml_files)} YAML configuration files.")
EOF

# 4. Check Ubiquity Core Debian Appliance Packages
echo "[Check 4/6] Checking Ubiquity Core Appliance debian packages..."
python3 - <<'EOF'
import sys, os, glob, subprocess

debs_dir = "ansible/roles/ros2_workspace/files/debs"
local_debs = glob.glob(os.path.join(debs_dir, "*.deb"))

expected_packages = [
    "ros-jazzy-robot-bringup",
    "ros-jazzy-magni-description",
    "ros-jazzy-ubiquity-core-utils",
    "ezmap-web",
    "ros-jazzy-move-smooth",
    "ros-jazzy-ubiquity-route-manager",
    "ros-jazzy-fiducials",
    "ros-jazzy-ubiquity-motor-ros2",
    "ros-jazzy-lidar-ros2",
    "ros-jazzy-iris-lama-ros",
]

if local_debs:
    print(f"  - Found {len(local_debs)} appliance debian packages staged in {debs_dir}.")
    found_pkgs = set()
    for deb in local_debs:
        basename = os.path.basename(deb)
        for exp in expected_packages:
            if basename.startswith(exp):
                found_pkgs.add(exp)
                print(f"  - PASS: Found staged deb for {exp} ({basename})")
    
    missing = set(expected_packages) - found_pkgs
    if missing:
        print(f"  - WARNING: Missing staged debs for: {missing}. These will be downloaded during CI release fetch step.", file=sys.stderr)
else:
    print(f"  - INFO: No local debs in {debs_dir}. They will be fetched during CI build step.")
EOF

# 5. Check executable permissions on bin/ and scripts/
echo "[Check 5/6] Checking script execution permissions..."
SCRIPTS_TO_CHECK=(
    "bin/uchroot"
    "bin/runner"
    "build.sh"
    "scripts/automated_tests.sh"
    "scripts/build_golden_base.sh"
    "scripts/synthesize_fast_appliance.sh"
    "scripts/bdebstrap/setup01-apt-cache"
    "scripts/bdebstrap/cleanup99-apt-cache"
)
for s in "${SCRIPTS_TO_CHECK[@]}"; do
    if [ ! -x "${REPO_ROOT}/$s" ]; then
        echo "  - ERROR: Script '$s' is missing execute permissions (+x)!" >&2
        exit 1
    fi
    echo "  - PASS: $s is executable"
done

# 6. Check prebuilt assets integrity
echo "[Check 6/6] Checking prebuilt frontend web distribution package (.deb)..."
DEB_PATH="${REPO_ROOT}/ansible/roles/ros2_workspace/files/debs/ezmap-web_all.deb"
if [ ! -f "$DEB_PATH" ]; then
    DEB_PATH="${REPO_ROOT}/ansible/roles/ros2_workspace/files/ezmap-web_all.deb"
fi
BUNDLE_PATH="${REPO_ROOT}/ansible/roles/ros2_workspace/files/ezmap-web-dist.tar.gz"
if [ -f "$DEB_PATH" ]; then
    if dpkg-deb -c "$DEB_PATH" | grep -q "index.html"; then
        echo "  - PASS: ezmap-web_all.deb is a valid Debian package containing index.html."
    else
        echo "  - ERROR: ezmap-web_all.deb is corrupt or does not contain index.html!" >&2
        exit 1
    fi
elif [ -f "$BUNDLE_PATH" ]; then
    if tar -tzf "$BUNDLE_PATH" | grep -q "index.html"; then
        echo "  - PASS: ezmap-web-dist.tar.gz is a valid tarball containing index.html."
    else
        echo "  - ERROR: ezmap-web-dist.tar.gz is corrupt or does not contain index.html!" >&2
        exit 1
    fi
else
    echo "  - WARNING: Neither ezmap-web_all.deb nor ezmap-web-dist.tar.gz found locally. It must be fetched from GitHub release during build."
fi

echo ""
echo "=========================================================="
echo "          ALL PRE-FLIGHT CHECKS PASSED (READY TO BUILD)   "
echo "=========================================================="
