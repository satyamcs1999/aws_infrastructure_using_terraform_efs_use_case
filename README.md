__<h1>Deploying AWS Infrastructure (EFS use case) using Terraform and it’s integration with Jenkins</h1>__

![Terraform_Jenkins_AWS](https://miro.medium.com/max/875/1*Y2i80oe9bAVP-HJepILKkg.png)<br>

<br>
<h2>What is Terraform ?</h2>
<p><b>Terraform</b> is an open-source infrastructure as code software tool created by <b>HashiCorp</b>. It enables users to define and provision a datacenter infrastructure using a high-level configuration language known as <b>HashiCorp Configuration Language</b>, or optionally <b>JSON</b>.</p>
<p>The current project has been divided into two parts i.e. first part involves AWS and Terraform and second part involves integration of the the setup with Jenkins.</p>

<h2>Part 1 : AWS and Terraform</h2>
<p>First of all, we need to specify the provider to be used in our Terraform Code , in our case we are using <b>AWS</b>, thereby we need to specify the same , I have specified the access key, secret key , though you can create a <b>profile</b> and specify the same for security purpose and region under which we are creating the infrastructure.</p><br>

```hcl
provider "aws" {
  region     = "ap-south-1"
  access_key = "****************"
  secret_key = "****************"
}
```

<p><b>Note</b> :- Never upload the Terraform Code with credentials explicitly specified on any public platform like GitHub and many more as it would pose huge risk to your account’s security.</p><br>

<p align="center"><b>. . .</b></p><br>


<p>Here, availability zone “ap-south-1c ” is blacklisted as the instance type (which is specified in AWS Instance Resource) is not available in this particular Availability Zone.</p><br>

```hcl
data "aws_availability_zones" "task_az" {
  blacklisted_names = ["ap-south-1c"]
}
```

<br>

<p align="center"><b>. . .</b></p><br>

<p>Instead of manually creating key in AWS console and then specifying it directly in our AWS Instance, automation in key generation could be done by creating a <b>TLS Private Key</b> and here we use <b>RSA</b> algorithm for private key generation which is required for generation of key pair required for accessing <b>EC2</b> Instance.</p><br>

```hcl
resource "tls_private_key" "tlskey" {
  algorithm = "RSA"
}

resource "aws_key_pair" "tkey" {
  key_name   = "task-key"
  public_key = tls_private_key.tlskey.public_key_openssh
}
```

<p><b>Note</b> :-If not specified , the size of TLS private key generated using RSA algorithm is 2048 bits.</p><br>

<p align="center"><b>. . .</b></p><br>

<p>Under <b>VPC</b>, we specify <b>CIDR Block</b> (a set of IP Addresses used for creating unique identifiers for the network and individual devices) as it is mandatory.</p><br>

```hcl
resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    "Name" = "task_vpc"
  }
}
```

<br>
<p><b>Subnet</b> defines a range of IP addresses under <b>VPC</b>, under which <b>VPC Id</b> and <b>CIDR Block</b> needs to be specified , also for <b>SSH</b> connection to <b>EC2</b> Instance , a parameter <b>map_public_ip_on_launch</b> needs to be set to true .</p>
<p>Also. first availability zone excluding the one that has been blacklisted is also specified.</p>

```hcl
resource "aws_subnet" "subnet_public" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.1.0.0/16"
  map_public_ip_on_launch = "true"
  availability_zone = data.aws_availability_zones.task_az.names[0]
  tags = {
    "Name" = "task_subnet"
  }
}
```

<br>
<p><b>Internet Gateway</b> performs <b>network address translation (NAT)</b> for EC2 instances which have been assigned public IPv4 addresses.</p>

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "task_ig"
  }
}
```

<br>
<p>VPC consist of an implicit router and <b>Route Table</b> is used to control the direction of network traffic.</p>

```hcl
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
```

<br>
<p><b>Subnet</b> in VPC must be associated with <b>Route Table</b> as it controls the routing of Subnet.</p>

```hcl
resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rtb_public.id
}
```

<br>

<p align="center"><b>. . .</b></p><br>

<p><b>Security Group</b> in AWS is used for controlling inbound and outbound traffic. In this case , port <b>22</b> with <b>TCP</b> Protocol is used for enabling <b>SSH</b> connection, for <b>HTTP</b>, port <b>80</b> is used and in this case, for enabling <b>NFS</b> for purpose of mounting <b>EFS</b> on <b>EC2</b> Instances, port <b>2049</b> is used.</p><br>
<p><b>Ingress</b> is used for specifying inbound rules which defines the traffic allowed in the EC2 instances and on which ports whereas <b>Egress</b> is used for specifying outbound rules which defines the traffic allowed to leave the EC2 instances on which ports and to which destinations.</p>

```hcl
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
```

![Security_Groups_AWS](https://miro.medium.com/max/875/1*mJMrTtMFmplAnS6GINFQWQ.png)

<p align="center"><b>Security Groups</b></p><br>

<p align="center"><b>. . .</b></p><br>

<p><b>EC2 Instances</b> provides a balance of compute, memory and networking resources. <b>AMI</b> or <b>Amazon Machine Images</b> provides the information required for launching an instance whereas instance type which has been predefined in this case i.e. <b>“t2.micro”</b> is the combination of CPU, Memory, Storage and Networking Capacity as per requirements of the users or clients .</p><br>

```hcl
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
```

![EC2_AWS](https://miro.medium.com/max/875/1*5pLeypHDOFhQGCBFM5THmw.png)

<p align="center"><b>EC2</b></p><br>

<p>After launching the EC2 instance , setup of <b>provisioner</b> and <b>connection</b> is done under <b>null resource</b> as both of them needs to be declared inside resource or in case of connection, it could be declared under provisioner as well. In connection, <b>type</b> ,<b>user</b>, <b>private key</b> is defined (could be obtained from tls_private_key resource) and <b>host</b>(public IP which could be obtained from aws_instance resource).</p>
<p>After the connection is set up, set up for project inside the instance could be done using <b>“remote-exec”</b> provisioner, for purpose of setting up webserver, httpd is installed , whereas for obtaining web page, git is installed whereas for setting up NFS , tools like amazon-efs-utils and nfs-utils are installed.</p>

```hcl
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
```

<br>

<p align="center"><b>. . .</b></p><br>

<p>Amazon Elastic File System (Amazon <b>EFS</b>) provides a simple, scalable, fully managed, elastic NFS file system for use with <b>AWS</b> Cloud services and on-premises resources. Amazon EFS is easy to use and offers a simple interface that allows you to create and configure file systems quickly and easily.</p><br>

```hcl
resource "aws_efs_file_system" "myefs" {
  depends_on = [
    null_resource.op_after_creation
  ]
  tags = {
    Name = "myEFS"
  }
}
```

<br>
<p>A <b>mount target</b> provides an IP address for an NFSv4 endpoint at which you can <b>mount</b> an Amazon <b>EFS</b> file system. You mount your file system using its Domain Name Service (DNS) name, which resolves to the IP address of the EFS mount target in the same Availability Zone as your EC2 instance. In this case, IP Address is used for purpose of mounting.</p>

```hcl
resource "aws_efs_mount_target" "efs_mount" {
  depends_on = [
    aws_efs_file_system.myefs
  ]
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id = aws_subnet.subnet_public.id
  security_groups = [ aws_security_group.sg_80.id ]
}
```

<br>
<p>For purpose of using IP Address to mount EFS to EC2 Instance , <b>data source</b> for <b>EFS</b> mount target is used for generating the <b>IP Address</b>. Mounting process as well as writing in <b>fstab</b> file so as to avoid mounting whenever system reboots is specified in a null resource following the data resource.</p>

```hcl
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
```

![EFS_AWS_1](https://miro.medium.com/max/875/1*-RNLj1IMgnLPsQKOGad5-A.png)

<p align="center"><b>EFS</b></p><br>

![EFS_AWS_2](https://miro.medium.com/max/875/1*iyZYTg4tzFl_ZY5BzxXYxg.png)

<p align="center"><b>EFS</b></p><br>

![EFS_AWS_EC2](https://miro.medium.com/max/875/1*qLems9qsI5BokxCrJBSkAQ.png)

<p align="center"><b>EFS mounted on EC2 Instances(Check Type nfs4)</b></p><br>

<p align="center"><b>. . .</b></p><br>

<p><b>VPC Endpoints</b> ensures that the data between <b>VPC</b> and <b>S3</b> is transferred within Amazon Network , thereby helps in protecting instances from internet traffic.</p><br>

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.vpc.id
  service_name = "com.amazonaws.ap-south-1.s3"
}
```

<br>
<p><b>VPC Endpoints</b> are associated with <b>Route Tables</b> and the reason for the same is that the traffic from instances in the subnet could be routed through the endpoint.</p>

```hcl
resource "aws_vpc_endpoint_route_table_association" "verta_public" {
  route_table_id  = aws_route_table.rtb_public.id
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}
```

<br><br>

<p><b>S3</b> , an abbreviation of <b>Simple Storage Service</b> is a public cloud storage resource , an object level storage and provides S3 <b>buckets</b> , which are similar to file folders , consisting of data and its metadata.</p>
<p>Here,<b>force_destroy</b> has been set to true so as to delete bucket with objects within it without error.</p>

```hcl
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
```

![S3](https://miro.medium.com/max/875/1*D_kNoSxs10EDueaLfgCWtw.png)

<p align="center"><b>S3</b></p><br>

<p align="center"><b>. . .</b></p><br>

<p><b>CodePipeline</b> is a fully managed continuous delivery service that helps in automating the release pipeline.This overall setup has been done for creating a continuous delivery pipeline between <b>GitHub repo</b> and <b>S3 bucket</b> and and accordingly values has been provided to the parameters of actions .</p><br>
<p><b>Note :-</b> The recommended policy for providing <b>role_arn</b> parameter to grant someone to make call on behalf on AWS is <b>AdministratorAccess</b>.</p>

```hcl
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
```

![CodePipeline](https://miro.medium.com/max/875/1*f5qleqAAiXKMDHfCm7NwMw.png)

<p align="center"><b>CodePipeline</b></p><br>

<p><b>Waiting time</b> between two resources could be generated using Terraform resource known as <b>time_sleep</b>.</p>
<p>The reason behind creation of waiting time is due to time it takes for S3 to replicate the data across <b>multiple servers</b> , if the objects within the bucket is accessed before the replication completes, it would show an error like <b>“NoSuchKey”</b> error.</p>

```hcl
resource "time_sleep" "waiting_time" {
  depends_on = [
    aws_codepipeline.task_codepipeline
  ]
  create_duration = "5m" 
}
```

<br>
<p>As soon as <b>waiting time</b> is over , <b>“local-exec”</b> provisioner enables execution in local system , and in this case , <b>AWS CLI</b> command for making a specific object publicly accessible is performed as the public access to bucket doesn’t ensure public access to the objects within it , so to make a object publicly accessible , the permission has to be provided separately for the object as well.</p>

```hcl
resource "null_resource" "codepipeline_cloudfront" {
   
  depends_on = [
    time_sleep.waiting_time 
  ]
  provisioner "local-exec" {
    command = "/usr/local/bin/aws s3api put-object-acl  --bucket t1-aws-terraform  --key freddie_mercury.jpg   --acl public-read"
  }
}
```

<br>

<p align="center"><b>. . .</b></p><br>

<p><b>CloudFront</b> is a fast <b>Content Delivery Network (CDN)</b> for secure delivery of data, videos, application and APIs to customers globally with low latency and high transfer speed. It involves defining <b>default cache behaviour</b>, <b>domain name</b>, <b>cookies</b> , <b>TTL(Time to Live)</b>, <b>viewer certificate</b> and <b>restrictions</b> like geo restriction.</p><br>

```hcl
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
```

![CloudFront](https://miro.medium.com/max/875/1*0BPoCFkXD2XeSBKfBFx7Iw.png)

<p align="center"><b>CloudFront</b></p><br>

<p>As soon as <b>CloudFront Distribution</b> is set up, <b>null_resource</b> i.e., <b>cloudfront_url_updation</b> under which connection is set up to the EC2 instances which is same as the one created in previous ones , here usage of <b>“remote- exec”</b> provisioner is done but for different purpose i.e. updation of image source in <b>HTML img tag</b> with the domain_name whose value could be obtained from CloudFront Distribution created.</p>

```hcl
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
```

<br>

<p align="center"><b>. . .</b></p><br>

<p><b>public_ip</b> generated by aws_instance could be placed as an output so as to access the web page set up inside EC2 Instance by using <b>output</b> command in Terraform.</p><br>

```hcl
output "instance_public_ip" {
  depends_on = [
     null_resource.cloudfront_url_updation
  ]
  value = aws_instance.myinstance.public_ip
}
```

<br><br>

<h2>Part 2 : Integration with Jenkins</h2>

<h3>Job 1 : Generation of Public URL using ngrok</h3>

<p>First of all set up ngrok which uses the concept of tunneling providing Public URL, the command to activate ngrok is as follows</p><br>
<p><b>./ngrok http 8080</b></p><br>
<p>Here , the port number specified i.e., <b>8080</b> is the default port number for <b>Jenkins</b>.</p>

![ngrok](https://miro.medium.com/max/875/1*72KcjdsWyRi3fkbsElkJ4Q.png)

<br><br>
<h3>Job 2 : Setting up Webhook in GitHub</h3>

<p>First, select the repository and then select <b>Settings</b> on right hand corner.</p>

![webhook_1](https://miro.medium.com/max/875/1*loo-FxE7l4XBb7pP9oE-SA.png)

<br>
<p>Then , select <b>Webhooks</b> from the list of options present on the left hand side.</p>

![webhook_2](https://miro.medium.com/max/875/1*oOc21axSnjcTjQnU5k3H2A.png)

<br>
<p>Then click on <b>Add Webhook</b> on the top right .</p>

![webhook_3](https://miro.medium.com/max/875/1*8SLK0KIvEoXtPKMinyAjLw.png)

<br>
<p>Then in <b>Payload URL</b>, specify the URL in the format <b>“generatedURL/github-webhook/”</b> and under <b>Current type</b> , select <b>“application/json”</b>.</p>

![webhook_4](https://miro.medium.com/max/875/1*Op_u8C_S30dZ2ifHwIrmrQ.png)<br>

<p>Hence , the Webhook setup in GitHub has been done successfully</p><br><br>

<h3>Job 3 : Setting up Jenkins</h3>

<p>In the command line , the command for enabling Jenkins are as follows</p><br>
<p><b>systemctl start jenkins</b></p><br>
<p>Then , using <b>ifconfig</b> command, find the IP Address respective to the Network Card of your system.</p>
<p>After which, specify the IP address along with Port Number <b>8080</b> i.e., default port number for Jenkins and then this screen would appear .</p>

![Jenkins](https://miro.medium.com/max/875/1*gjmLcaXCTg5bJaXnKh271g.png)

<br>
<p>Enter Jenkins using the respective <b>Username</b> and <b>Password</b>.</p>
<p>Select on <b>“New item”</b></p>

![Jenkins_1](https://miro.medium.com/max/875/1*2-IIUiq_ou65WsO3F3W4Tg.png)

<br>
<p>Enter the name of the Job and click on <b>“Freestyle project”</b>, then click <b>OK</b>.</p>

![Jenkins_2](https://miro.medium.com/max/875/1*3FNhqqbTl3zcyuMhgGTS0Q.png)

<br><br>

<h3>Job 4 : Jenkins Job Setup</h3>
<p>For setting up Jenkins with GitHub , place the URL of the respective repository under <b>“Repository URL”</b> section of <b>Git</b> under <b>Source Code Management</b>.</p>
<p>For setting up <b>Build Trigger</b> to the Webhook that was setup before , click on <b>“GitHub hook trigger for GITScm polling”</b> .</p>

![Jenkins_3](https://miro.medium.com/max/875/1*c-Mp7c1XaqwgMU0JzcVM3A.png)

<br>
<p>Under <b>Build</b>, select <b>“Execute shell”</b></p>

![Jenkins_4](https://miro.medium.com/max/875/1*6otHDI0w_OrIe_e2H5rZnA.png)

<br>
<p>Then , add the code for setting up CI/CD Pipeline of AWS and Terraform with Jenkins .</p>

```shell
/usr/local/bin/aws configure set aws_access_key_id *******************
/usr/local/bin/aws configure set aws_secret_access_key ************************
/usr/local/bin/terraform destroy -auto-approve -lock=false -input=false
/usr/local/bin/terraform init -input=false
/usr/local/bin/terraform destroy -auto-approve -lock=false -input=false
/usr/local/bin/terraform plan -input=false -lock=false  -parallelism=1
/usr/local/bin/terraform apply -auto-approve -lock=false -input=false  -parallelism=1
/usr/local/bin/terraform destroy -auto-approve -lock=false -input=false
```

<h2>Note</h2>
<p>To learn how to create an GitHub <b>OAuth Token</b> , check this link</p>
https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line


<h2>Thank You :smiley:<h2>
<h3>LinkedIn Profile</h3>
https://www.linkedin.com/in/satyam-singh-95a266182

<h2>Link to the repository mentioned above</h2>
https://github.com/satyamcs1999/terraform_aws_jenkins.git

