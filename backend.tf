terraform {
  backend "s3" {
    bucket         = "tfstate-202373502652"
    key            = "visitor-counter/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
