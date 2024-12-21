# Default provider for ap-southeast-1
provider "aws" {
  region = "ap-southeast-1"
}

# Additional provider for us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}