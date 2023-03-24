variable "aws_region" {
       description = "The AWS region to create things in." 
       default     = "eu-west-1" 
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone id"
}

variable "env" {
  description = "environment stage"
}

variable "markets" {
  type = map
}

variable "versioning" {
    type        = bool
    description = "(Optional) A state of versioning."
    default     = true
}

variable "domain" {
  description = "Top level domain to be served by CloudFront"
}

variable "acl" {
    type        = string
    description = " Defaults to private "
    default     = "private"
}

variable "bucket_prefix" {
    type        = string
    description = "(required since we are not using 'bucket') Creates a unique bucket name beginning with the specified prefix"
    default     = "tf-s3bucket-"
}
variable "tags" {
    type        = map
    description = "(Optional) A mapping of tags to assign to the bucket."
    default     = {
        environment = "DEV"
        terraform   = "true"
    }
}