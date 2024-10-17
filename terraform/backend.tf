terraform {
  backend "s3" {
    bucket         = "terraform-state-jellyvision" # Use the bucket name you created
    key            = "terraform/state"
    region         = "us-east-1"
    dynamodb_table = "terraform_locks" # Use the name of the DynamoDB table you created
  }
}
