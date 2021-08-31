output "url-jenkins" {
  value = "http://${aws_instance.jenkins-ci.0.public_ip}:8080"
}

output "url-tomcat" {
  value = "http://${aws_instance.tomcat.0.public_ip}:8888"
}

output "url-mysql" {
  value = "http://${aws_instance.mysql.0.public_ip}:3306"
}
