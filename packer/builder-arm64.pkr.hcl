packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      # In Packer HCL, the registry source identifier is "github.com/hashicorp/amazon"
      # (The actual GitHub repository is: https://github.com/hashicorp/packer-plugin-amazon)
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for building the Golden AMI"
  default     = "us-east-1"
}

source "amazon-ebs" "arm64_builder" {
  ami_name      = "ubiquity-rpi-builder-arm64-{{timestamp}}"
  instance_type = "t4g.xlarge"
  region        = var.aws_region
  ssh_username  = "admin"
  spot_price    = "auto"

  # Enforce IMDSv2 Security
  imds_support = "v2.0"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Dynamically discover the latest official Debian 12 ARM64 AMI
  source_ami_filter {
    filters = {
      name                = "debian-12-arm64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["136540069911"] # Official Debian Organization
  }

  # Fast gp3 NVMe root disk
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 50
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
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

  # Pre-bake all required container and OS creation tools
  provisioner "shell" {
    inline = [
      "sudo apt-get update && sudo apt-get upgrade -y",
      "sudo apt-get install -y podman bdebstrap mmdebstrap qemu-user-static zstd s3cmd git curl jq udev libarchive-tools",
      "sudo systemctl enable podman",
      # Setup User Namespaces for podman unshare
      "echo 'admin:100000:65536' | sudo tee /etc/subuid",
      "echo 'admin:100000:65536' | sudo tee /etc/subgid",
      # Pre-configure loopback module for image formatting
      "sudo modprobe loop"
    ]
  }
}
