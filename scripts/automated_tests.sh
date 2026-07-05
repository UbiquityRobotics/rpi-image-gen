#!/bin/bash
set -e

ROOTFS=$1

echo ""
echo "=========================================================="
echo "          RUNNING AUTOMATED ROOTFS TESTS                  "
echo "=========================================================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Root filesystem path is invalid or missing: $ROOTFS"
    exit 1
fi

# 1. Verify ros2_ws Workspace Structure
echo "[Test 1/3] Verifying ros2_ws structure..."
WS_DIR="$ROOTFS/home/ubuntu/ros2_ws"

if [ ! -d "$WS_DIR" ]; then
    echo "ERROR: ros2_ws directory does not exist at $WS_DIR!"
    exit 1
fi

for dir in src build install log; do
    if [ -d "$WS_DIR/$dir" ]; then
        echo "  - PASS: $dir directory found."
    else
        echo "  - ERROR: Missing $dir directory in ros2_ws!"
        echo "    This indicates the build failed or colcon did not run properly."
        exit 1
    fi
done

# Verify that the src directory actually contains packages
SRC_COUNT=$(ls -1q "$WS_DIR/src" | wc -l)
if [ "$SRC_COUNT" -eq 0 ]; then
    echo "  - ERROR: The ros2_ws/src directory is completely empty!"
    echo "    This means the git clones failed."
    exit 1
else
    echo "  - PASS: Found $SRC_COUNT items in ros2_ws/src:"
    ls -1 "$WS_DIR/src" | sed 's/^/      * /'
fi

# 2. Verify ROS 2 Build Success (setup.bash and nodes)
echo "[Test 2/3] Verifying ROS 2 build outputs..."
if [ -f "$WS_DIR/install/setup.bash" ]; then
    echo "  - PASS: setup.bash found in install directory."
else
    echo "  - ERROR: setup.bash missing! The workspace didn't compile successfully."
    exit 1
fi

# Check if any executable nodes were compiled in the lib folder
NODE_COUNT=$(find "$WS_DIR/install" -type f -executable | wc -l)
if [ "$NODE_COUNT" -gt 0 ]; then
    echo "  - PASS: Found $NODE_COUNT compiled ROS 2 executables/nodes in install dir."
else
    echo "  - ERROR: No compiled executables found in the install directory. Nodes failed to build."
    exit 1
fi

# 3. Verify Systemd Services
echo "[Test 3/3] Verifying critical services..."
SERVICE_DIR="$ROOTFS/etc/systemd/system"
if [ ! -d "$SERVICE_DIR" ]; then
    echo "  - ERROR: systemd services directory is missing!"
    exit 1
fi

# Check for custom/ubiquity services installed
CUSTOM_SERVICES=$(find "$SERVICE_DIR" -name "*.service" -type f)
if [ -n "$CUSTOM_SERVICES" ]; then
    echo "  - PASS: Systemd services found."
else
    echo "  - WARNING: No custom systemd services found in /etc/systemd/system."
fi

echo "=========================================================="
echo "          ALL AUTOMATED TESTS PASSED SUCCESSFULLY!        "
echo "=========================================================="
echo ""
