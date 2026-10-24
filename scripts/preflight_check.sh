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
        echo "  - ERROR: Required tool '$tool' is not installed on host!" >&2
        exit 1
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

# 4. Check Git Authentication & Repository Branch Reachability
echo "[Check 4/6] Checking workspace repository branches on GitHub..."
python3 - <<'EOF'
import sys, os, yaml, subprocess

with open("ansible/roles/ros2_workspace/tasks/main.yml", "r") as f:
    tasks = yaml.safe_load(f)

repos = []
for task in tasks:
    if task.get("name") == "Clone git repositories":
        repos = task.get("loop", [])
        break

token = os.environ.get("GITHUB_TOKEN", "")
failures = 0

for r in repos:
    name = r["name"]
    version = r["version"]
    url = f"https://github.com/UbiquityRobotics/{name}.git"
    if token:
        url = f"https://{token}@github.com/UbiquityRobotics/{name}.git"
    
    # Run a fast 1-second git ls-remote to ensure repo and branch exist
    cmd = ["git", "ls-remote", "--exit-code", url, version, f"refs/heads/{version}", f"refs/tags/{version}"]
    try:
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8)
        if res.returncode == 0:
            print(f"  - PASS: {name} @ {version}")
        else:
            print(f"  - ERROR: Branch/tag '{version}' not found on {name}!", file=sys.stderr)
            failures += 1
    except subprocess.TimeoutExpired:
        print(f"  - WARNING: Network timeout checking {name} (skipping)", file=sys.stderr)
    except Exception as e:
        print(f"  - ERROR checking {name}: {e}", file=sys.stderr)
        failures += 1

if failures > 0:
    print(f"\nFATAL: {failures} repository branch checks failed!", file=sys.stderr)
    sys.exit(1)
EOF

# 5. Check executable permissions on bin/ and scripts/
echo "[Check 5/6] Checking script execution permissions..."
SCRIPTS_TO_CHECK=(
    "bin/uchroot"
    "bin/runner"
    "build.sh"
    "scripts/automated_tests.sh"
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
echo "[Check 6/6] Checking prebuilt frontend web distribution bundle..."
BUNDLE_PATH="${REPO_ROOT}/ansible/roles/ros2_workspace/files/ezmap-web-dist.tar.gz"
if [ -f "$BUNDLE_PATH" ]; then
    if tar -tzf "$BUNDLE_PATH" | grep -q "index.html"; then
        echo "  - PASS: ezmap-web-dist.tar.gz is a valid tarball containing index.html."
    else
        echo "  - ERROR: ezmap-web-dist.tar.gz is corrupt or does not contain index.html!" >&2
        exit 1
    fi
else
    echo "  - WARNING: ezmap-web-dist.tar.gz not found locally. It must be fetched from GitHub release during build."
fi

echo ""
echo "=========================================================="
echo "          ALL PRE-FLIGHT CHECKS PASSED (READY TO BUILD)   "
echo "=========================================================="
