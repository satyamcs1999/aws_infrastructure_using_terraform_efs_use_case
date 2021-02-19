provider "aws" {
  region     = "ap-south-1"
  access_key = "****************"
  secret_key = "****************"
}

data "aws_availability_zones" "task_az" {
  blacklisted_names = ["ap-south-1c"]
}

resource "tls_private_key" "tlskey" {
  algorithm = "RSA"
}

resource "aws_key_pair" "tkey" {
  key_name   = "task-key"
  public_key = tls_private_key.tlskey.public_key_openssh
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    "Name" = "task_vpc"
  }
}

resource "aws_subnet" "subnet_public" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.1.0.0/16"
  map_public_ip_on_launch = "true"
  availability_zone = data.aws_availability_zones.task_az.names[0]
  tags = {
    "Name" = "task_subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "task_ig"
  }
}

resource "aws_route_table" "rtb_public" {
  vpc_id = aws_vpc.vpc.id
  route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
     "Name" = "task_route"
  }
}

resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rtb_public.id
}

resource "aws_security_group" "sg_80" {
  name = "sg_80"
  vpc_id = aws_vpc.vpc.id
  
  ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

  ingress {
    from_port   = 2049
    to_port     = 2049
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
    Name = "task_sg"
  }
}

resource "aws_instance"  "myinstance"  {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = data.aws_availability_zones.task_az.names[0]
  key_name      = aws_key_pair.tkey.key_name
  subnet_id = aws_subnet.subnet_public.id
  vpc_security_group_ids = [ aws_security_group.sg_80.id ]
  
  tags = {
    Name = "tfos"
  }
} 

resource "null_resource" "op_after_creation"  {

  depends_on = [
    aws_instance.myinstance
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tlskey.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y amazon-efs-utils",
      "sudo yum install -y nfs-common",
      "sudo yum install -y nfs-utils",
      "sudo yum install httpd git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
  }  
}

resource "aws_efs_file_system" "myefs" {
  depends_on = [
    null_resource.op_after_creation
  ]
  tags = {
    Name = "myEFS"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  depends_on = [
    aws_efs_file_system.myefs
  ]
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id = aws_subnet.subnet_public.id
  security_groups = [ aws_security_group.sg_80.id ]
}

data "aws_efs_mount_target" "by_id" {
  mount_target_id = aws_efs_mount_target.efs_mount.id
}

resource "null_resource" "mount_target"  {

  depends_on = [
    data.aws_efs_mount_target.by_id
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tlskey.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }

  provisioner "remote-exec" {
      inline = [
        "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${data.aws_efs_mount_target.by_id.ip_address}:/ /var/www/html",
        "sudo su -c \"echo '${data.aws_efs_mount_target.by_id.ip_address}:/ /var/www/html nfs4 defaults,vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0' >> /etc/fstab\"",
        "sudo rm -rf /var/www/html/*",
        "sudo git clone https://github.com/satyamcs1999/terraform_aws_jenkins.git /var/www/html/"
     ]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.ap-south-1.s3"
}

resource "aws_vpc_endpoint_route_table_association" "verta_public" {
  route_table_id  = aws_route_table.rtb_public.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_s3_bucket" "task_bucket" {

  depends_on = [
   null_resource.mount_target
  ]
  bucket = "t1-aws-terraform"
  acl    = "public-read"
  region = "ap-south-1"
  force_destroy = "true"
  website{
    index_document = "index.html"
  }

  tags = {
    Name = "t1-aws-terraform"
  }
}

resource "aws_codepipeline" "task_codepipeline" {
   name = "task_codepipeline"
   role_arn = "arn:aws:iam::**********:role/sats"
   artifact_store {
    location = aws_s3_bucket.task_bucket.bucket
    type = "S3"
  }
  stage {
    name = "Source"
    
    action {
      name = "Source"
      category = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = "1"
      output_artifacts = ["source_output"]
      
      configuration = {
        Owner = "satyamcs1999"
        Repo = "terraform_aws_jenkins"
        Branch = "master"
        OAuthToken = "****************************"
      }
    }
  }
  
  stage {
    name = "Deploy"

    action {
      name = "Deploy"
      category = "Deploy"
      owner = "AWS"
      provider = "S3"
      version = "1"
      input_artifacts = ["source_output"]

      configuration = {
        BucketName = "t1-aws-terraform"
        Extract = "true"
      }
    }
  }
}

resource "time_sleep" "waiting_time" {
  depends_on = [
    aws_codepipeline.task_codepipeline
  ]
  create_duration = "5m" 
}

resource "null_resource" "codepipeline_cloudfront" {
   
  depends_on = [
    time_sleep.waiting_time 
  ]
  provisioner "local-exec" {
    command = "/usr/local/bin/aws s3api put-object-acl  --bucket t1-aws-terraform  --key freddie_mercury.jpg   --acl public-read"
  }
}

resource "aws_cloudfront_distribution" "task_cloudfront_distribution" {
  depends_on = [
    null_resource.codepipeline_cloudfront  
  ]
  origin {
    domain_name = aws_s3_bucket.task_bucket.bucket_domain_name
    origin_id = "S3-t1-aws-terraform"
  }
  
  enabled = true
  is_ipv6_enabled = "true"

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods = ["GET", "HEAD","OPTIONS"]
    target_origin_id = "S3-t1-aws-terraform"
    
    forwarded_values {
      query_string = "false"
      
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = "true"
  }
}

resource "null_resource" "cloudfront_url_updation" {
  depends_on = [
    aws_cloudfront_distribution.task_cloudfront_distribution
  ]  
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.tlskey.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }

  provisioner "remote-exec"{
    inline = [
      "sudo sed -ie 's,freddie_mercury.jpg,https://${aws_cloudfront_distribution.task_cloudfront_distribution.domain_name}/freddie_mercury.jpg,g' /var/www/html/index.html"
    ]
  }
}

output "instance_public_ip" {
  depends_on = [
     null_resource.cloudfront_url_updation
  ]
  value = aws_instance.myinstance.public_ip
}