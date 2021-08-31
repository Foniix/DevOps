variable "profile" {
  default = "terraform_iam_user"
}

variable "region" {
  default = "eu-north-1"
}

variable "instance" {
  default = "t3.micro"
}

variable "instance_count" {
  default = "1"
}

variable "public_key" {
  default = "~/.ssh/MyKeyPair.pub"
}

variable "private_key" {
  default = "~/.ssh/MyKeyPair.pem"
}

variable "ansible_user" {
  default = "ubuntu"
}

variable "amis" {
  type = map(any)

  default = {
    eu-north-1 = "ami-0813b14494048969c"
  }
}

variable "ami" {
  default = "ami-0afad43e7d620260c"
}
