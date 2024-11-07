# terraform-ses-reputation-management

Improve your SES reputation using dedicated IPs and sending reports

This module will create :
* a dedicated IP managed pool in SES
* an associated configuration-set to use in your idendities or API requests
* a dynamodb with some indexes to store all reports received for this configuration-set using lambda

## Usage

```hcl
module "dedicated-ip" {
  source = "github.com/e-serenity/terraform-ses-reputation-management"

  name_prefix = "my-vpc"
}
```
