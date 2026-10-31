packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for building the Golden AMI"
  default     = "us-east-2"
}

source "amazon-ebs" "arm64_builder" {
  ami_name      = "ubiquity-rpi-builder-arm64-{{timestamp}}"
  instance_type = "t4g.xlarge"
  region        = var.aws_region
  source_ami    = "ami-009dbf7acf984fc41"
  ssh_username  = "admin"

  # Fast gp3 NVMe root disk (matching workers.py)
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 80
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "ubiquity-rpi-builder-arm64"
    Environment = "CI"
    ManagedBy   = "Packer"
  }
}

build {
  name    = "ubiquity-builder"
  sources = ["source.amazon-ebs.arm64_builder"]

  # Pre-bake all required container, build, and OS creation tools (including rpi-image-gen 2.9.x)
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "sudo apt-get update && sudo apt-get upgrade -y",
      # Core build essentials & packaging tools (rpi-image-gen 2.9.x requirement)
      "sudo apt-get install -y build-essential make autoconf automake libtool pkgconf flex gettext autopoint dpkg-dev",
      # Python, serialization, and schema validation
      "sudo apt-get install -y python3 python3-pip python3-yaml python3-debian python3-jsonschema python3-boto3 python3-apt",
      # Container and filesystem synthesis tools
      "sudo apt-get install -y podman bdebstrap mmdebstrap qemu-user-static genimage cryptsetup",
      # Archive, compression, and transfer utilities
      "sudo apt-get install -y zstd s3cmd git curl jq udev libarchive-tools xz-utils dosfstools mtools crudini pv btrfs-progs dctrl-tools zip",
      # Ansible for provisioning Magni stack
      "sudo apt-get install -y ansible",
      # Keyrings
      "sudo apt-get install -y debian-archive-keyring ubuntu-archive-keyring ca-certificates || true",
      "sudo mkdir -p /usr/share/keyrings",
      "sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg",
      "sudo chmod 644 /usr/share/keyrings/ros-archive-keyring.gpg",
      # Enable podman and configure user namespaces for podman unshare
      "sudo systemctl enable podman",
      "echo 'admin:100000:65536' | sudo tee -a /etc/subuid",
      "echo 'admin:100000:65536' | sudo tee -a /etc/subgid",
      # Pre-configure container engine
      "sudo mkdir -p /etc/containers",
      "printf '[engine]\\ncgroup_manager = \"cgroupfs\"\\nevents_logger = \"file\"\\n' | sudo tee /etc/containers/containers.conf",
      # Pre-configure loopback module for image formatting
      "sudo modprobe loop",
      "echo 'loop' | sudo tee -a /etc/modules",
      # Pre-stage directory for Tier 1 Golden Base RootFS NVMe cache
      "sudo mkdir -p /opt/ubiquity/base-rootfs",
      "sudo chown -R admin:admin /opt/ubiquity",
      "curl -sSL https://ubiquity-pi-image.sfo2.digitaloceanspaces.com/cache/magni-base-noble-jazzy.tar.zst -o /opt/ubiquity/base-rootfs/magni-base-noble-jazzy.tar.zst || true"
    ]
  }
}
