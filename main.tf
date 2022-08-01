terraform {
  cloud {
    organization = "great-stone-biz"
    hostname     = "app.terraform.io" # default
    workspaces {
      name = "terraform-edu-chapter9-compute"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "remote"

  config = {
    organization = "great-stone-biz"
    workspaces = {
      name = "terraform-edu-chapter9-network"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = "terraform cloud workflow"
      Owner   = "jerry & tom"
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "hashicat" {
  count    = var.ec2_count
  instance = aws_instance.hashicat[count.index].id
  vpc      = true
}

resource "aws_eip_association" "hashicat" {
  count         = var.ec2_count
  instance_id   = aws_instance.hashicat[count.index].id
  allocation_id = aws_eip.hashicat[count.index].id
}

resource "aws_instance" "hashicat" {
  count                       = var.ec2_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.hashicat.key_name
  associate_public_ip_address = true
  subnet_id                   = data.terraform_remote_state.network.outputs.subnet_id_hashicat
  vpc_security_group_ids      = [data.terraform_remote_state.network.outputs.security_group_id_hashicat]

  tags = {
    Name = "${var.prefix}-hashicat-instance"
  }
}

resource "null_resource" "configure_cat_app" {
  count      = var.ec2_count
  depends_on = [aws_eip_association.hashicat]

  // triggers = {
  //   build_number = timestamp()
  // }

  provisioner "file" {
    source      = "files/"
    destination = "/home/ubuntu/"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.hashicat.private_key_pem
      host        = aws_eip.hashicat[count.index].public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt -y update",
      "sleep 15",
      "sudo apt -y update",
      "sudo apt -y install apache2",
      "sudo systemctl start apache2",
      "sudo chown -R ubuntu:ubuntu /var/www/html",
      "chmod +x *.sh",
      "PLACEHOLDER=${var.placeholder} WIDTH=${var.width} HEIGHT=${var.height} PREFIX=${var.prefix} ./deploy_app.sh",
      "sudo apt -y install cowsay",
      "cowsay Mooooooooooo!",
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.hashicat.private_key_pem
      host        = aws_eip.hashicat[count.index].public_ip
    }
  }
}

resource "tls_private_key" "hashicat" {
  algorithm = "RSA"
}

locals {
  private_key_filename = "${var.prefix}-ssh-key.pem"
}

resource "aws_key_pair" "hashicat" {
  key_name   = local.private_key_filename
  public_key = tls_private_key.hashicat.public_key_openssh
}
