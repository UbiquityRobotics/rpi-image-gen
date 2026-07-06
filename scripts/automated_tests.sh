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

# 1. Verify ros2_ws Workspace Structure (Only if this is a ROS 2 robot image)
if [ "$IGconf_image_variant" == "ros2-base-image" ]; then
    echo "  - INFO: Building base-image. Skipping ROS 2 workspace tests."
else
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

    # Verify that the src directory contains the specifically required nodes
    REQUIRED_NODES=(
        "ezmap"
        "ezpkg_grid_driving_ros2"
        "fiducials"
        "iris_ur_lama"
        "iris_ur_lama_ros"
        "lidar_ros2"
        "magni_robot"
        "move_smooth"
        "robot_bringup"
        "ubiquity_core_utils"
        "ubiquity_motor_ros2"
        "ubiquity_route_manager"
        "ubiquity_route_msgs"
        "camera_ros"
        "libcamera"
        "libpisp"
    )

    echo "  - Checking for specifically required nodes in ros2_ws/src..."
    for node in "${REQUIRED_NODES[@]}"; do
        if ! find "$WS_DIR/src" -maxdepth 2 -type d -name "$node" | grep -q .; then
            echo "  - ERROR: Required node '$node' is missing from ros2_ws/src!"
            echo "    Please verify your .yaml meta files are cloning this repository."
            exit 1
        fi
    done

    SRC_COUNT=$(ls -1q "$WS_DIR/src" | wc -l)
    echo "  - PASS: All strictly required nodes found. Total $SRC_COUNT top-level items in src."

    # 2. Verify ROS 2 Build Success (setup.bash and nodes)
    echo "[Test 2/3] Verifying ROS 2 build outputs..."
    if [ -f "$WS_DIR/install/setup.bash" ]; then
        echo "  - PASS: setup.bash found in install directory."
    else
        echo "  - ERROR: setup.bash missing! The workspace didn't compile successfully."
        exit 1
    fi

    # Count compiled packages by looking for package.xml in the install directory (handles both isolated and merged layouts)
    NODE_COUNT=$(find "$WS_DIR/install" -mindepth 3 -maxdepth 4 -name "package.xml" | wc -l)
    if [ "$NODE_COUNT" -gt 5 ]; then
        echo "  - PASS: Found $NODE_COUNT successfully compiled ROS 2 packages in install dir."
    else
        echo "  - ERROR: Only $NODE_COUNT compiled packages found. colcon build likely failed silently!"
        exit 1
    fi
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
