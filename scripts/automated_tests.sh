#!/bin/bash
set -e

ROOTFS=$1

# Re-execute in podman unshare if running as non-root to ensure user namespace access
if [ "$(id -u)" -ne 0 ] && command -v podman >/dev/null 2>&1; then
    exec podman unshare "$0" "$@"
fi

echo ""
echo "=========================================================="
echo "          RUNNING AUTOMATED ROOTFS TESTS                  "
echo "=========================================================="

if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS" ]; then
    echo "ERROR: Root filesystem path is invalid or missing: $ROOTFS"
    exit 1
fi

# 1. Verify ROS 2 Jazzy Underlay & Appliance Packages (Only if this is a ROS 2 robot image)
if [ "$IGconf_image_variant" == "ros2-base-image" ]; then
    echo "  - INFO: Building base-image. Skipping ROS 2 appliance tests."
else
    echo "[Test 1/5] Verifying ROS 2 Jazzy Underlay & Debian Appliance packages..."
    UNDERLAY_DIR="$ROOTFS/opt/ros/jazzy"

    if [ ! -d "$UNDERLAY_DIR" ]; then
        echo "ERROR: ROS 2 Jazzy underlay does not exist at $UNDERLAY_DIR!"
        exit 1
    fi

    if [ -f "$UNDERLAY_DIR/setup.bash" ]; then
        echo "  - PASS: setup.bash found in /opt/ros/jazzy."
    else
        echo "  - ERROR: setup.bash missing from /opt/ros/jazzy!"
        exit 1
    fi

    REQUIRED_APPLIANCE_PACKAGES=(
        "robot_bringup"
        "magni_description"
        "ubiquity_motor_ros2"
        "move_smooth"
        "ubiquity_route_manager"
        "ubiquity_core_utils"
        "ld19_lidar"
        "iris_lama"
        "aruco_detect"
        "camera_ros"
    )

    echo "  - Checking for Ubiquity Core Appliance packages in /opt/ros/jazzy/share..."
    for pkg in "${REQUIRED_APPLIANCE_PACKAGES[@]}"; do
        if [ -d "$UNDERLAY_DIR/share/$pkg" ]; then
            echo "  - PASS: Found underlay package '$pkg'"
        else
            echo "  - ERROR: Required underlay package '$pkg' missing from /opt/ros/jazzy/share!"
            exit 1
        fi
    done

    # 2. Verify Clean Customer Workspace & Appliance Isolation
    echo "[Test 2/5] Verifying clean customer workspace structure..."
    WS_DIR="$ROOTFS/home/ubuntu/ros2_ws"

    if [ ! -d "$WS_DIR/src" ]; then
        echo "ERROR: ros2_ws/src directory does not exist at $WS_DIR/src!"
        exit 1
    fi

    # Ensure customer workspace is pristine and contains no clutter
    SRC_COUNT=$(find "$WS_DIR/src" -mindepth 1 -maxdepth 1 | wc -l)
    if [ "$SRC_COUNT" -eq 0 ]; then
        echo "  - PASS: Customer workspace src is pristine and empty (pure appliance model)."
    else
        echo "  - WARNING: Customer workspace contains $SRC_COUNT items in src."
    fi
fi

# 3. Verify Systemd Services & 5-Tier Execution Architecture
echo "[Test 3/5] Verifying 5-tier launch architecture & systemd services..."
SERVICE_DIR="$ROOTFS/etc/systemd/system"
if [ ! -d "$SERVICE_DIR" ]; then
    echo "  - ERROR: systemd services directory is missing!"
    exit 1
fi

# Check global execution wrapper
if [ -x "$ROOTFS/usr/local/bin/magni-ros2-run.sh" ]; then
    echo "  - PASS: /usr/local/bin/magni-ros2-run.sh wrapper script found and is executable."
elif [ "$IGconf_image_variant" == "ros2-base-image" ]; then
    echo "  - INFO: Skipping magni-ros2-run.sh check on base-image."
else
    echo "  - ERROR: /usr/local/bin/magni-ros2-run.sh wrapper script is missing or not executable!"
    exit 1
fi

# Check the 5 decoupled Magni tier services
TIER_SERVICES=(
    "magni-hardware.service"
    "magni-teleop.service"
    "magni-navigation.service"
    "magni-ui.service"
    "magni-diagnostics.service"
)

for svc in "${TIER_SERVICES[@]}"; do
    if [ -f "$SERVICE_DIR/$svc" ] || [ -f "$SERVICE_DIR/multi-user.target.wants/$svc" ]; then
        echo "  - PASS: Found service unit: $svc"
    elif [ "$IGconf_image_variant" == "ros2-base-image" ]; then
        echo "  - INFO: Skipping $svc check on base-image."
    else
        echo "  - ERROR: Service $svc is missing from /etc/systemd/system!"
        exit 1
    fi
done

# 4. Verify EZ-Map Web Application & Nginx Deployment
echo "[Test 4/5] Verifying EZ-Map web frontend and Nginx deployment..."
if [ "$IGconf_image_variant" == "ros2-base-image" ]; then
    echo "  - INFO: Skipping web frontend check on base-image."
else
    if [ -f "$ROOTFS/var/www/ezmap/index.html" ] && [ -s "$ROOTFS/var/www/ezmap/index.html" ]; then
        echo "  - PASS: /var/www/ezmap/index.html static web application is deployed."
    else
        echo "  - ERROR: /var/www/ezmap/index.html is missing or empty! Web deployment failed."
        exit 1
    fi

    if [ -L "$ROOTFS/etc/nginx/sites-enabled/ezmap" ]; then
        echo "  - PASS: Nginx ezmap site configuration is enabled."
    else
        echo "  - ERROR: Nginx ezmap site symlink missing in /etc/nginx/sites-enabled!"
        exit 1
    fi
fi

# 5. Verify Image Provenance Metadata
echo "[Test 5/5] Verifying image build provenance metadata..."
if [ "$IGconf_image_variant" == "ros2-base-image" ]; then
    echo "  - INFO: Skipping provenance check on base-image."
else
    if [ -f "$ROOTFS/etc/ubiquity-image-release" ]; then
        echo "  - PASS: Found /etc/ubiquity-image-release."
    else
        echo "  - ERROR: Missing /etc/ubiquity-image-release metadata!"
        exit 1
    fi
fi

echo "=========================================================="
echo "          ALL AUTOMATED TESTS PASSED SUCCESSFULLY!        "
echo "=========================================================="
echo ""
