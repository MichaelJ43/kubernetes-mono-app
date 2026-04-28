variable "aws_region" {
  type = string
}

variable "state_bucket" {
  type = string
}

variable "state_region" {
  type = string
}

variable "lock_table" {
  type = string
}

variable "foundation_state_key" {
  type        = string
  description = "S3 key for foundation terraform.tfstate"
}
