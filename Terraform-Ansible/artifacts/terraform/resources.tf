resource "aws_key_pair" "demo_key" {
  key_name   = "MyKeyPair"
  public_key = file(var.public_key)
}

#Create aws ec2 instance with Jenkins container
resource "aws_instance" "jenkins-ci" {
  count = var.instance_count

  ami           = var.ami
  instance_type = var.instance
  key_name      = aws_key_pair.demo_key.key_name

  tags = {
    Name = "jenkins-ci-${count.index + 1}"
  }

  #added security groups
  vpc_security_group_ids = [
    "${aws_security_group.web.id}",
    "${aws_security_group.ssh.id}",
    "${aws_security_group.egress-tls.id}",
    "${aws_security_group.ping-ICMP.id}",
    "${aws_security_group.web_server.id}"
  ]

  connection {
    private_key = file(var.private_key)
    user        = var.ansible_user
    host        = "${aws_instance.jenkins-ci[count.index].public_ip}"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /etc/playbooks && sudo chown ubuntu: /etc/playbooks"]
  }  

  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/playbooks/install_docker.yaml"
    destination = "/etc/playbooks/install_docker.yaml"
  }  
  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/docker/jenkins-docker-compose.yml"
    destination = "/etc/playbooks/jenkins-docker-compose.yml"
  }  

  provisioner "remote-exec" {
    inline = [
       "sudo apt-get -qq install python3.8 -y",
       "sudo apt-get -qq install python-pip -y",
       "sudo apt-add-repository ppa:ansible/ansible -y",
       "sudo apt install ansible -y",
       "ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i jenkins-ci.ini /etc/playbooks/install_docker.yaml",
       "sudo docker-compose -f /etc/playbooks/jenkins-docker-compose.yml up -d",
    ]
  }
}


#Create aws ec2 instance with Tomcat container
resource "aws_instance" "tomcat" {
  count = var.instance_count

  ami           = var.ami
  instance_type = var.instance
  key_name      = aws_key_pair.demo_key.key_name

  tags = {
    Name = "tomcat-${count.index + 1}"
  }

  #added security groups
  vpc_security_group_ids = [
    "${aws_security_group.web.id}",
    "${aws_security_group.ssh.id}",
    "${aws_security_group.egress-tls.id}",
    "${aws_security_group.ping-ICMP.id}",
    "${aws_security_group.web_server.id}"
  ]

  connection {
    private_key = file(var.private_key)
    user        = var.ansible_user
    host        = "${aws_instance.tomcat[count.index].public_ip}"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /etc/playbooks && sudo chown ubuntu: /etc/playbooks"]
  }  

  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/playbooks/install_docker.yaml"
    destination = "/etc/playbooks/install_docker.yaml"
  }  
  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/docker/tomcat-docker-compose.yml"
    destination = "/etc/playbooks/tomcat-docker-compose.yml"
  }
  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/docker/webapps"
    destination = "/etc/playbooks/webapps"
  }

  provisioner "remote-exec" {
    inline = [
       "sudo apt-get -qq install python3.8 -y",
       "sudo apt-get -qq install python-pip -y",
       "sudo apt-add-repository ppa:ansible/ansible -y",
       "sudo apt install ansible -y",
       "ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i tomcat.ini /etc/playbooks/install_docker.yaml",
       "sudo docker-compose -f /etc/playbooks/tomcat-docker-compose.yml up -d",
    ]
  }
}

#Create aws ec2 instance with MySQL container
resource "aws_instance" "mysql" {
  count = var.instance_count

  ami           = var.ami
  instance_type = var.instance
  key_name      = aws_key_pair.demo_key.key_name

  tags = {
    Name = "mysql-${count.index + 1}"
  }

  #added security groups
  vpc_security_group_ids = [
    "${aws_security_group.web.id}",
    "${aws_security_group.ssh.id}",
    "${aws_security_group.egress-tls.id}",
    "${aws_security_group.ping-ICMP.id}",
    "${aws_security_group.db_server.id}"
  ]

  connection {
    private_key = file(var.private_key)
    user        = var.ansible_user
    host        = "${aws_instance.mysql[count.index].public_ip}"
  }

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /etc/playbooks && sudo chown ubuntu: /etc/playbooks"]
  }  

  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/playbooks/install_docker.yaml"
    destination = "/etc/playbooks/install_docker.yaml"
  }
  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/docker/mysql"
    destination = "/etc/playbooks/mysql"
  }
  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/docker/db-variables.env"
    destination = "/etc/playbooks/db-variables.env"
  }  
  provisioner "file" {
    source      = "/root/Terraform-Ansible/artifacts/docker/mysql-docker-compose.yml"
    destination = "/etc/playbooks/mysql-docker-compose.yml"
  }  

  provisioner "remote-exec" {
    inline = [
       "sudo apt-get -qq install python3.8 -y",
       "sudo apt-get -qq install python-pip -y",
       "sudo apt-add-repository ppa:ansible/ansible -y",
       "sudo apt install ansible -y",
       "ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i postgresql.ini /etc/playbooks/install_docker.yaml",
       "sudo docker-compose -f /etc/playbooks/mysql-docker-compose.yml up -d",
    ]
  }
}

resource "aws_security_group" "web" {
  name        = "default-web-example"
  description = "Security group for web that allows web traffic from internet"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-default"
  }
}

resource "aws_security_group" "ssh" {
  name        = "default-ssh-example"
  description = "Security group for nat instances that allows SSH and VPN traffic from internet"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh-default"
  }
}

# Allow the web app to receive requests on port 8080
resource "aws_security_group" "web_server" {
  name        = "default-web_server-example"
  description = "Default security group that allows to use ports"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  tags = {
    Name = "web_server-default"
  }
}

# Allow the DB to receive requests on port 5432
resource "aws_security_group" "db_server" {
  name        = "default-db_server-example"
  description = "Default security group that allows to use port 5432"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db_server-default"
  }
}
