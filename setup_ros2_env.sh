#!/bin/bash
set -e

# Update package lists
sudo apt update

# Install Git and Podman
sudo apt install -y git podman dosfstools mtools s3cmd

# Run your dependency installation script
sudo ./install_deps.sh

# Ensure the Ubuntu archive keyring is present
sudo apt-get install -y ubuntu-archive-keyring

# Add the ROS 2 GPG key
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key | sudo tee /usr/share/keyrings/ros-archive-keyring.gpg > /dev/null

# Add the ROS 2 repository for Ubuntu Noble (arm64)
echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu noble main' | sudo tee /etc/apt/sources.list.d/ros2.list

# Update package lists again to include ROS 2 repository
sudo apt update
