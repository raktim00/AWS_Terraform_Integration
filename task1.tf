provider "aws" {
  region     = "ap-south-1"
  profile    = "raktim"
}

// Creating RSA key

variable "EC2_Key" {default="httpdserverkey"}
resource "tls_private_key" "httpdkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

// Creating AWS key-pair

resource "aws_key_pair" "generated_key" {
  key_name   = var.EC2_Key
  public_key = tls_private_key.httpdkey.public_key_openssh
}

// Creating security group

resource "aws_security_group" "httpdsecurity" {

depends_on = [
    aws_key_pair.generated_key,
  ]

  name         = "httpdsecurity"
  description  = "allow ssh and httpd"
 
  ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPD Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "httpdsecurity"
  }
}

// Creating EC2 Instance and Installing Required Softwares in it.

resource "aws_instance" "HttpdInstance" {

depends_on = [
    aws_security_group.httpdsecurity,
  ]

  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = var.EC2_Key
  security_groups = [ "${aws_security_group.httpdsecurity.name}" ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.httpdkey.private_key_pem
    host     = aws_instance.HttpdInstance.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "HttpdServer1"
  }
}

// Creating EBS volume and attaching it to EC2 Instance.

resource "aws_ebs_volume" "HttpdEBS" {
  availability_zone = aws_instance.HttpdInstance.availability_zone
  size              = 1
  tags = {
    Name = "HttpdEBS"
  }
}

resource "aws_volume_attachment" "EBSattach" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.HttpdEBS.id
  instance_id = aws_instance.HttpdInstance.id
  force_detach = true
}

// Mounting the Volume in EC2 Instance and Cloning GitHub files in Httpd Server

resource "null_resource" "VolumeMount"  {

depends_on = [
    aws_volume_attachment.EBSattach,
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.httpdkey.private_key_pem
    host     = aws_instance.HttpdInstance.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/raktim00/DevOpsHW.git /var/www/html/"
    ]
  }
}

// Creating S3 bucket.

resource "aws_s3_bucket" "httpds3" {
bucket = "raktim-httpd-files"
acl    = "public-read"
}

//Putting Objects in S3 Bucket

resource "aws_s3_bucket_object" "s3_object" {
  bucket = aws_s3_bucket.httpds3.bucket
  key    = "Raktim.JPG"
  source = "C:/Users/rakti/OneDrive/Desktop/Raktim.JPG"
  acl    = "public-read"
}

// Creating Cloud Front Distribution.

locals {
s3_origin_id = aws_s3_bucket.httpds3.id
}

resource "aws_cloudfront_distribution" "CloudFrontAccess" {

depends_on = [
    aws_s3_bucket_object.s3_object,
  ]

origin {
domain_name = aws_s3_bucket.httpds3.bucket_regional_domain_name
origin_id   = local.s3_origin_id
}

enabled             = true
is_ipv6_enabled     = true
comment             = "s3bucket-access"

default_cache_behavior {
allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
viewer_protocol_policy = "allow-all"
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
}
# Cache behavior with precedence 0
ordered_cache_behavior {
path_pattern     = "/content/immutable/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD", "OPTIONS"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
headers      = ["Origin"]
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 86400
max_ttl                = 31536000
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
# Cache behavior with precedence 1
ordered_cache_behavior {
path_pattern     = "/content/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
price_class = "PriceClass_200"
restrictions {
geo_restriction {
restriction_type = "blacklist"
locations        = ["CA"]
}
}
tags = {
Environment = "production"
}
viewer_certificate {
cloudfront_default_certificate = true
}
retain_on_delete = true
}

// Changing the html code and adding the image url in that.

resource "null_resource" "HtmlCodeChange"  {
depends_on = [
    aws_cloudfront_distribution.CloudFrontAccess,
  ]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.httpdkey.private_key_pem
    host     = aws_instance.HttpdInstance.public_ip
  }
  provisioner "remote-exec" {
    inline = [
	"echo '<img src='https://${aws_cloudfront_distribution.CloudFrontAccess.domain_name}/Raktim.JPG' width='300' height='330'>' | sudo tee -a /var/www/html/Raktim.html"
    ]
  }
}

// Creating EBS snapshot volume.

resource "aws_ebs_snapshot" "httpd_snapshot" {
depends_on = [
    null_resource.HtmlCodeChange,
  ]
  volume_id = aws_ebs_volume.HttpdEBS.id

  tags = {
    Name = "Httpd_snap"
  }
}

// Finally opening the browser to that particular html site to see how It's working.

resource "null_resource" "ChromeOpen"  {
depends_on = [
    aws_ebs_snapshot.httpd_snapshot,
  ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.HttpdInstance.public_ip}/Raktim.html"
  	}
}


