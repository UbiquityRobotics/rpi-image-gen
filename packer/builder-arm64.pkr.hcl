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

  # Pre-bake all required container and OS creation tools
  provisioner "shell" {
    inline = [
      "sudo apt-get update && sudo apt-get upgrade -y",
      "sudo apt-get install -y podman bdebstrap mmdebstrap qemu-user-static zstd s3cmd git curl jq udev libarchive-tools",
      "sudo systemctl enable podman",
      # Setup User Namespaces for podman unshare
      "echo 'admin:100000:65536' | sudo tee -a /etc/subuid",
      "echo 'admin:100000:65536' | sudo tee -a /etc/subgid",
      # Pre-configure loopback module for image formatting
      "sudo modprobe loop"
    ]
  }
}
