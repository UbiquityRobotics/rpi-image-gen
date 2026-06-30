# Ubiquity Magni Robot OS Provisioning Playbook

This project contains the Ansible playbooks to provision a bare-metal OS image for the Ubiquity Magni robot.

## Project Structure

```text
/home/michael/code/ubiquity/rpi-image-gen/
├── PROJECT.md                # Project architecture and design specification
├── ansible/
│   ├── group_vars/
│   │   └── all.yml           # Global variables
│   ├── inventory.ini         # Inventory configuration
│   ├── site.yml              # Entrypoint playbook
│   ├── validate.sh           # Syntax checking script
│   └── roles/
│       ├── base_system/      # System updates, package dependencies, user settings
│       ├── networking/       # NetworkManager setup, Wi-Fi AP scripts, dynamic SSID
│       ├── hardware/         # robot.yaml config, udev rules, UART pin mapping script/service
│       ├── zenoh/            # Zenoh router wrapper, json5 config files, systemd unit
│       ├── ros2_workspace/   # Git repositories clone, npm build, rosdep, colcon compile
│       └── systemd_services/ # Systemd unit files for hardware, navigation, and UI services
```

## Provisioning Details

### 1. Base System (`base_system`)
- **APT packages**: Installs base system requirements, development tools, camera ROS dependencies, and ROS 2 Jazzy desktop/base packages.
- **Security Limits**: Appends real-time priority limits for user `ubuntu` in `/etc/security/limits.conf` (`ubuntu - nice -20`).
- **User Groups**: Ensures the `ubuntu` user belongs to the `dialout` and `video` groups.

### 2. Networking (`networking`)
- **SSID Dynamic Configuration**: Deploys a boot script (`setup-ap.sh`) that dynamically constructs a unique Wi-Fi SSID based on the system's MAC address (e.g. `Magni-XXXX`).
- **Hostname Configuration**: Deploys a boot script (`setup-hostname.sh`) to dynamically set the hostname (e.g. `magni-XXXX`).
- **Systemd Units**: Deploys and enables `setup-hostname.service` and `firstboot-ap.service` to apply settings on first boot.

### 3. Hardware Configuration (`hardware`)
- **Robot Extrinsics**: Configures `/etc/ubiquity/robot.yaml` template containing generation (`gen6`), active LiDAR type, LiDAR position, camera markers, and sensor state.
- **Udev Rules**: Standardizes device aliases `/etc/udev/rules.d/99-ubiquity.rules` (such as `/dev/robot_serial` and `/dev/robot_lidar`/`/dev/ldlidar`).
- **Pin Multiplexing**: Deploys a service `magni-uart-pinctrl.service` running a script mapping GPIO UART pins 14 and 15 using `pinctrl` or `raspi-gpio`.

### 4. Zenoh Router (`zenoh`)
- **Router Config**: Deploys the default configurations `DEFAULT_RMW_ZENOH_ROUTER_CONFIG_pi4.json5` and `DEFAULT_RMW_ZENOH_ROUTER_CONFIG_pi5.json5`.
- **Startup Wrapper**: Deploys a wrapper script `start-zenoh.sh` which detects the Raspberry Pi board model and launches `rmw_zenohd` with the appropriate configuration.
- **Systemd Service**: Registers and enables `rmw_zenohd.service` to start Zenoh at boot.

### 5. ROS 2 Workspace (`ros2_workspace`)
- Clones 13 core repositories to `/home/ubuntu/ros2_ws/src/` on specified branches:
  - `robot_bringup` (master)
  - `magni_robot` (fix-tf-remappings)
  - `ubiquity_core_utils` (master)
  - `iris_ur_lama` (jazzy-devel)
  - `iris_ur_lama_ros` (jazzy-devel)
  - `ubiquity_motor_ros2` (jazzy-devel)
  - `fiducials` (jazzy-devel)
  - `lidar_ros2` (jazzy-devel)
  - `move_smooth` (jazzy-devel)
  - `ubiquity_route_manager` (nav2-refactor)
  - `ubiquity_route_msgs` (master)
  - `ezpkg_grid_driving_ros2` (jazzy-devel)
  - `ezmap` (refactor/modular-arch, recursive)
- Builds the UI touchscreen web application using `npm install && npm run build` inside `route_select_ui`.
- Installs workspace dependencies via `rosdep install`.
- Builds the workspace using `colcon build`.

### 6. Systemd Services (`systemd_services`)
- Registers and enables the three primary systemd orchestration services in dependency order:
  1. `magni_hardware.service` (Hardware and drivers layer)
  2. `magni_navigation.service` (SLAM / Path Planning layer)
  3. `magni_ui.service` (UI Web App / user interface layer)

## Verification
Execute the validation script:
```bash
cd ansible
./validate.sh
```
This runs `ansible-playbook --syntax-check` on `site.yml`.
