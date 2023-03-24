terraform {
  backend "s3" {
    bucket = "tf-lambdastate-bucket"
    key = "main"
    region = "eu-west-1"
    dynamodb_table = "tf-dynamo-db-table"
  }
}