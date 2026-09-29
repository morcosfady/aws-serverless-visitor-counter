variable "region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_origin" {
  description = "Only this website may call the API from a browser (CORS)"
  type        = string
  default     = "https://morcosfady.github.io"
}

variable "alert_email" {
  description = "Where alarms and budget alerts go (already public on my portfolio's contact section)"
  type        = string
  default     = "morcos.fady94@gmail.com"
}
