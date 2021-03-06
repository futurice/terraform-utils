# aws_domain_redirect

This module implements a domain that redirects clients to another URL. Useful for creating human-friendly shortcuts for deeper links into a site, or for dynamic links (e.g. `download.example.com` always pointing to your latest release).

Main features:

- DNS entries are created automatically
- HTTPS enabled by default
- HTTP Strict Transport Security supported

Optional features:

- Plain HTTP instead of HTTPS
- Sending a permanent redirect (`301 Moved Permanently`) instead of default (`302 Found`)

Resources used:

- Route53 for DNS entries
- ACM for SSL certificates
- CloudFront for proxying requests
- Lambda@Edge for transforming requests
- IAM for permissions

## About CloudFront operations

This module manages CloudFront distributions, and these operations are generally very slow. Your `terraform apply` may take anywhere from a few minutes **up to 45 minutes** (if you're really unlucky). Be patient: if they start successfully, they almost always finish successfully, it just takes a while.

Additionally, this module uses Lambda@Edge functions with CloudFront. Because Lambda@Edge functions are replicated, [they can't be deleted immediately](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html). This means a `terraform destroy` won't successfully remove all resources on its first run. It should complete successfully when running it again after a few hours, however.

## Example

Assuming you have the [AWS provider](https://www.terraform.io/docs/providers/aws/index.html) set up, and a DNS zone for `example.com` configured on Route 53:

```tf
# Lambda@Edge and ACM, when used with CloudFront, need to be used in the US East region.
# Thus, we need a separate AWS provider for that region, which can be used with an alias.
# Make sure you customize this block to match your regular AWS provider configuration.
# https://www.terraform.io/docs/configuration/providers.html#multiple-provider-instances
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "my_redirect" {
  # Available inputs: https://github.com/futurice/terraform-utils/tree/master/aws_domain_redirect#inputs
  # Check for updates: https://github.com/futurice/terraform-utils/compare/v13.1...master
  source    = "git::ssh://git@github.com/futurice/terraform-utils.git//aws_domain_redirect?ref=v13.1"
  providers = { aws.us_east_1 = aws.us_east_1 } # this alias is needed because ACM is only available in the "us-east-1" region

  redirect_domain = "go.example.com"
  redirect_url    = "https://www.futurice.com/careers/"
}
```

Applying this will take a long time, because both ACM and especially CloudFront are quite slow to update. After that, both `http://go.example.com` and `https://go.example.com` should redirect clients to `https://www.futurice.com/careers/`.

<!-- terraform-docs:begin -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| redirect_domain | Domain which will redirect to the given `redirect_url`; e.g. `"docs.example.com"` | `any` | n/a | yes |
| redirect_url | The URL this domain redirect should send clients to; e.g. `"https://readthedocs.org/projects/example"` | `any` | n/a | yes |
| name_prefix | Name prefix to use for objects that need to be created (only lowercase alphanumeric characters and hyphens allowed, for S3 bucket name compatibility) | `string` | `""` | no |
| comment_prefix | This will be included in comments for resources that are created | `string` | `"Domain redirect: "` | no |
| cloudfront_price_class | Price class to use (`100`, `200` or `"All"`, see https://aws.amazon.com/cloudfront/pricing/) | `number` | `100` | no |
| viewer_https_only | Set this to `false` if you need to support insecure HTTP access for clients, in addition to HTTPS | `bool` | `true` | no |
| redirect_permanently | Which HTTP status code to use for the redirect; if `true`, uses `301 Moved Permanently`, instead of `302 Found` | `bool` | `false` | no |
| hsts_max_age | How long should `Strict-Transport-Security` remain in effect for the site; disabled automatically when `viewer_https_only = false` | `number` | `31557600` | no |
| lambda_logging_enabled | When `true`, writes information about incoming requests to the Lambda function's CloudWatch group | `bool` | `false` | no |
| tags | AWS Tags to add to all resources created (where possible); see https://aws.amazon.com/answers/account-management/aws-tagging-strategies/ | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| reverse_proxy | CloudFront-based reverse-proxy that's used for implementing the redirect |
<!-- terraform-docs:end -->
