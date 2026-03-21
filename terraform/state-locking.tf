resource "aws_dynamodb_table" "terraform_locks" {
  name         = "project5-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "project5-terraform-locks"
  }
}