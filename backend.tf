terraform {
  backend "s3" {
    bucket         = "tfstatebucket-stef"
    key            = "project/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}