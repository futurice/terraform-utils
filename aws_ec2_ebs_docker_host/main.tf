# Create the main EC2 instance
# https://www.terraform.io/docs/providers/aws/r/instance.html
resource "aws_instance" "this" {
  instance_type          = var.instance_type
  ami                    = var.instance_ami
  availability_zone      = local.availability_zone
  key_name               = aws_key_pair.this.id # the name of the SSH keypair to use for provisioning
  vpc_security_group_ids = [aws_security_group.this.id]
  subnet_id              = data.aws_subnet.this.id
  user_data              = sha1(local.reprovision_trigger)          # this value isn't used by the EC2 instance, but its change will trigger re-creation of the resource
  tags                   = merge(var.tags, { Name = var.hostname }) # make this resource easier to identify in the AWS Console (tag "Name" is effectively "display name" in some services)
  volume_tags            = merge(var.tags, { Name = var.hostname }) # ^ ditto

  root_block_device {
    volume_size = var.root_volume_size
  }

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = var.ssh_username
    private_key = file(var.ssh_private_key_path)
    agent       = false # don't use SSH agent because we have the private key right here
  }

  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${var.hostname}",
      "echo 127.0.0.1 ${var.hostname} | sudo tee -a /etc/hosts", # https://askubuntu.com/a/59517
    ]
  }

  provisioner "remote-exec" {
    script = "${path.module}/provision-docker.sh"
  }

  provisioner "file" {
    source      = "${path.module}/provision-swap.sh"
    destination = "/home/${var.ssh_username}/provision-swap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /home/${var.ssh_username}/provision-swap.sh ${var.swap_file_size} ${var.swap_swappiness}",
      "rm /home/${var.ssh_username}/provision-swap.sh",
    ]
  }
}

# Attach the separate data volume to the instance, if so configured

resource "aws_volume_attachment" "this" {
  count       = var.data_volume_id == "" ? 0 : 1 # only create this resource if an external EBS data volume was provided
  device_name = "/dev/xvdh"                      # note: this depends on the AMI, and can't be arbitrarily changed
  instance_id = aws_instance.this.id
  volume_id   = var.data_volume_id
}

resource "null_resource" "provisioners" {
  count      = var.data_volume_id == "" ? 0 : 1 # only create this resource if an external EBS data volume was provided
  depends_on = [aws_volume_attachment.this]     # because we depend on the EBS volume being available

  connection {
    host        = aws_instance.this.public_ip # see https://github.com/hashicorp/terraform/issues/23679 for discussion on the deprecation warning for this line
    user        = var.ssh_username
    private_key = file(var.ssh_private_key_path)
    agent       = false # don't use SSH agent because we have the private key right here
  }

  # When creating the attachment
  provisioner "remote-exec" {
    script = "${path.module}/provision-ebs.sh"
  }

  # When tearing down the attachment
  provisioner "remote-exec" {
    when   = destroy
    inline = ["sudo umount -v ${aws_volume_attachment.this[0].device_name}"]
  }
}
