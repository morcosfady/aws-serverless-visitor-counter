variable "region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_origin" {
  description = "Only this website may call the API from a browser (CORS)"
  type        = string
  default     = "https://morcosfady.github.io"
}
