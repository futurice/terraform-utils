# aws_ec2_ebs_docker_host

Creates a standalone Docker host on EC2, optionally attaching an external EBS volume for persistent data.

This is convenient for quickly setting up non-production-critical Docker workloads. If you need something fancier, consider e.g. ECS, EKS or Fargate.

## Example 1: Running a docker container

Assuming you have the [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) set up:

```tf
module "my_host" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_ec2_ebs_docker_host#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v13.1...master
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_ec2_ebs_docker_host?ref=v13.1"

  hostname             = "my-docker-host"
  ssh_private_key_path = "~/.ssh/id_rsa"     # if you use shared Terraform state, consider changing this to something that doesn't depend on "~"
  ssh_public_key_path  = "~/.ssh/id_rsa.pub"
  allow_incoming_http  = true                # by default, only incoming SSH is allowed; other protocols for the security group are opt-in
}

output "host_ssh_command" {
  description = "Run this command to create a port-forward to the remote docker daemon"
  value       = "ssh -i ${module.my_host.ssh_private_key_path} -o StrictHostKeyChecking=no -L localhost:2377:/var/run/docker.sock ${module.my_host.ssh_username}@${module.my_host.public_ip}"
}
```

After `terraform apply`, and running the `host_ssh_command`, you should be able to connect from your local Docker CLI to the remote daemon, e.g.:

```bash
$ DOCKER_HOST=localhost:2377 docker run -d -p 80:80 nginx
```

Visit the IP address of your host in a browser to make sure it works.

## Example 2: Using a persistent data volume

Assuming you have the [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) set up:

```tf
resource "aws_ebs_volume" "my_data" {
  availability_zone = module.my_host.availability_zone # ensure the volume is created in the same AZ the docker host
  type              = "gp2"                            # i.e. "Amazon EBS General Purpose SSD"
  size              = 25                               # in GiB; if you change this in-place, you need to SSH over and run e.g. $ sudo resize2fs /dev/xvdh
  tags              = { Name = "my-host-data" }        # make this resource easier to identify in the AWS Console (tag "Name" is effectively "display name" in some services)
}

module "my_host" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_ec2_ebs_docker_host#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v13.1...master
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_ec2_ebs_docker_host?ref=v13.1"

  hostname             = "my-host"
  ssh_private_key_path = "~/.ssh/id_rsa"           # note that with a shared Terraform state, paths with "~" will become problematic
  ssh_public_key_path  = "~/.ssh/id_rsa.pub"
  data_volume_id       = aws_ebs_volume.my_data.id # attach our EBS data volume
}

output "host_ssh_command" {
  description = "Run this command to check that the data volume got mounted"
  value       = "ssh -i ${module.my_host.ssh_private_key_path} -o StrictHostKeyChecking=no ${module.my_host.ssh_username}@${module.my_host.public_ip} df -h"
}
```

Note that due to [a bug in Terraform](https://github.com/hashicorp/terraform/issues/12570), at the time of writing, you need to apply in two parts:

```bash
$ terraform apply -target aws_ebs_volume.my_data
...
$ terraform apply
...
```

Afterwards, running the `host_ssh_command` should give you something like:

```
Filesystem      Size  Used Avail Use% Mounted on
udev            481M     0  481M   0% /dev
tmpfs            99M  752K   98M   1% /run
/dev/xvda1      7.7G  2.1G  5.7G  27% /
tmpfs           492M     0  492M   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           492M     0  492M   0% /sys/fs/cgroup
/dev/loop0       88M   88M     0 100% /snap/core/5328
/dev/loop1       13M   13M     0 100% /snap/amazon-ssm-agent/495
/dev/xvdh        25G   45M   24G   1% /data
tmpfs            99M     0   99M   0% /run/user/1000
```

That is, you can see the 25 GB data volume mounted at `/data`.

## Example 3: Running additional provisioners

Assuming you have the [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) set up:

```tf
module "my_host" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_ec2_ebs_docker_host#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v13.1...master
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_ec2_ebs_docker_host?ref=v13.1"

  hostname             = "my-docker-host"
  ssh_private_key_path = "~/.ssh/id_rsa"
  ssh_public_key_path  = "~/.ssh/id_rsa.pub"
}

resource "null_resource" "provisioners" {
  depends_on = [module.my_host] # wait until other provisioners within the module have finished

  connection {
    host        = module.my_host.public_ip
    user        = module.my_host.ssh_username
    private_key = module.my_host.ssh_private_key
    agent       = false
  }

  provisioner "remote-exec" {
    inline = ["echo HELLO WORLD"]
  }
}
```

## Example 4: Using the `docker` provider

Note that until [`depends_on` support for providers](https://github.com/hashicorp/terraform/issues/2430) lands in Terraform, this is a bit cumbersome, but it's documented here in case it's useful.

Assuming you have the [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) set up:

```tf
module "my_host" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_ec2_ebs_docker_host#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v13.1...master
  source = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_ec2_ebs_docker_host?ref=v13.1"

  hostname             = "my-docker-host"
  ssh_private_key_path = "~/.ssh/id_rsa"
  ssh_public_key_path  = "~/.ssh/id_rsa.pub"
  allow_incoming_http  = true
}

output "ssh_config_entry" {
  description = "Add this entry to your `~/.ssh/config` to be able to connect to the docker daemon over SSH"
  value       = <<-EOF
    # This ~/.ssh/config entry was generated by Terraform
    Host ${module.my_host.public_ip}
      User ${module.my_host.ssh_username}
      IdentityFile ${path.root}/${module.my_host.ssh_private_key_path}
      StrictHostKeyChecking no
    EOF
}

provider "docker" {
  host = "ssh://${module.my_host.ssh_username}@${module.my_host.public_ip}"
}

resource "docker_image" "nginx" {
  name = "nginx"
}

resource "docker_container" "nginx" {
  image    = docker_image.nginx.latest
  name     = "nginx"
  must_run = true

  ports {
    internal = 80
    external = 80
  }
}

output "test_link" {
  value = "http://${module.my_host.public_ip}/"
}
```

Due to the limitation mentioned above, applying this for the first time is somewhat involved:

1. Create the host on EC2 first, with `terraform apply -target module.my_host`
1. Add its key config to your SSH client, with `terraform output ssh_config_entry >> ~/.ssh/config`
1. Create the Docker resources, with `terraform apply`
1. You should now be able to visit the `test_link` and see nginx greeting you

After the first apply, however, you don't need to take these special steps again.

<!-- terraform-docs:begin -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| hostname | Hostname by which this service is identified in metrics, logs etc | `string` | `"aws-ec2-ebs-docker-host"` | no |
| instance_type | See https://aws.amazon.com/ec2/instance-types/ for options; for example, typical values for small workloads are `"t2.nano"`, `"t2.micro"`, `"t2.small"`, `"t2.medium"`, and `"t2.large"` | `string` | `"t2.micro"` | no |
| instance_ami | See https://cloud-images.ubuntu.com/locator/ec2/ for options | `string` | `"ami-0c4c42893066a139e"` | no |
| ssh_private_key_path | SSH private key file path, relative to Terraform project root | `string` | `"ssh.private.key"` | no |
| ssh_public_key_path | SSH public key file path, relative to Terraform project root | `string` | `"ssh.public.key"` | no |
| ssh_username | Default username built into the AMI (see 'instance_ami') | `string` | `"ubuntu"` | no |
| vpc_id | ID of the VPC our host should join; if empty, joins your Default VPC | `string` | `""` | no |
| reprovision_trigger | An arbitrary string value; when this value changes, the host needs to be reprovisioned | `string` | `""` | no |
| root_volume_size | Size (in GiB) of the EBS volume that will be created and mounted as the root fs for the host | `number` | `8` | no |
| data_volume_id | The ID of the EBS volume to mount as `/data` | `string` | `""` | no |
| swap_file_size | Size of the swap file allocated on the root volume | `string` | `"512M"` | no |
| swap_swappiness | Swappiness value provided when creating the swap file | `string` | `"10"` | no |
| allow_incoming_http | Whether to allow incoming HTTP traffic on the host security group | `bool` | `false` | no |
| allow_incoming_https | Whether to allow incoming HTTPS traffic on the host security group | `bool` | `false` | no |
| allow_incoming_dns | Whether to allow incoming DNS traffic on the host security group | `bool` | `false` | no |
| tags | AWS Tags to add to all resources created (where possible); see https://aws.amazon.com/answers/account-management/aws-tagging-strategies/ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| hostname | Hostname by which this service is identified in metrics, logs etc |
| public_ip | Public IP address assigned to the host by EC2 |
| instance_id | AWS ID for the EC2 instance used |
| availability_zone | AWS Availability Zone in which the EC2 instance was created |
| ssh_username | Username that can be used to access the EC2 instance over SSH |
| ssh_private_key_path | Path to SSH private key that can be used to access the EC2 instance |
| ssh_private_key | SSH private key that can be used to access the EC2 instance |
| security_group_id | Security Group ID, for attaching additional security rules externally |
<!-- terraform-docs:end -->
