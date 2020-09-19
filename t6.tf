provider "aws" {
    region = "ap-south-1"
    profile = "azeem"
}

resource "tls_private_key" "this" {
    algorithm = "RSA"
}


resource "local_file" "private_key" {
    content         =   tls_private_key.this.private_key_pem
    filename        =   "mykey.pem"
}


resource "aws_key_pair" "mykey" {
    key_name   = "mykey_new"
    public_key = tls_private_key.this.public_key_openssh
}

resource "aws_vpc" "prod_vpc" {
  cidr_block       = "192.168.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
  instance_tenancy = "default"
  tags = {
    Name = "myfirstVPC"
}
  }
resource "aws_subnet" "mysubnet" {
  vpc_id     = aws_vpc.prod_vpc.id
  cidr_block = "192.168.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "myfirstsubnet"
  
}
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prod_vpc.id
  tags = {
    Name = "mygw"
  }
  
}


resource "aws_route_table" "mypublicRT" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "myRT1"
  }
  
}


resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.mysubnet.id
  route_table_id = aws_route_table.mypublicRT.id
}


resource "aws_security_group" "allow_traffic" {
  name        = "allow_nfs"
  description = "NFS "
  vpc_id      = aws_vpc.prod_vpc.id


  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


   ingress {
    description = "NFS"
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }


  ingress {
     description = "SSH from VPC"
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


  tags = {
    Name = "myfirewall"
  }
}

resource "aws_efs_file_system" "myefs" {
  creation_token = "EFS"
  tags = {
    Name = "MyEFS"
  }
}


resource "aws_efs_mount_target" "mytarget" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_subnet.mysubnet.id
  security_groups = [aws_security_group.allow_traffic.id]
}

resource "aws_instance" "myefsOS" {
    depends_on = [ aws_efs_mount_target.mytarget ]
    ami = "ami-0ebc1ac48dfd14136"
    instance_type = "t2.micro"
    key_name  = aws_key_pair.mykey.key_name
    subnet_id = aws_subnet.mysubnet.id
    vpc_security_group_ids = [aws_security_group.allow_traffic.id]


    user_data = <<-EOF
        #! /bin/bash
        
        sudo yum install httpd -y
        sudo systemctl start httpd 
        sudo systemctl enable httpd
        sudo rm -rf /var/www/html/*
        sudo yum install -y amazon-efs-utils
        sudo apt-get -y install amazon-efs-utils
        sudo yum install -y nfs-utils
        sudo apt-get -y install nfs-common
        sudo file_system_id_1="${aws_efs_file_system.myefs.id}
        sudo efs_mount_point_1="/var/www/html"
        sudo mkdir -p "$efs_mount_point_1"
        sudo test -f "/sbin/mount.efs" && echo "$file_system_id_1:/ $efs_mount_point_1 efs tls,_netdev" >> /etc/fstab || echo "$file_system_id_1.efs.ap-south-1.amazonaws.com:/$efs_mount_point_1 nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >> /etc/fstab
        sudo test -f "/sbin/mount.efs" && echo -e "\n[client-info]\nsource=liw"   >> /etc/amazon/efs/efs-utils.conf
        sudo mount -a -t efs,nfs4 defaults
        cd /var/www/html
        sudo yum insatll git -y
        sudo mkfs.ext4 /dev/xvdf1
        sudo rm -rf /var/www/html/*
        sudo yum install git -y
        sudo git clone https://github.com/azeemushanali/miniport.git /var/www/html
        
        EOF


    tags = {
    Name = "myOS"
    }
}

resource "aws_s3_bucket" "mybucket" {


bucket = "anshi2210"
acl = "public-read"
force_destroy = true
policy = <<EOF
{
  "Id": "MakePublic",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "*",
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::anshi2210/*",
      "Principal": "*"
    }
  ]
}
EOF



provisioner "local-exec" {
    command     = "git clone https://github.com/azeemushanali/miniport.git AWS_task2"
    
  }


provisioner "local-exec" {
        when        =   destroy
        command     =   "echo Y | rmdir /s AWS_task2"
    }




tags = {
Name = "anshi2210"
}
}




resource "aws_s3_bucket_object" "Upload_image" {
  depends_on = [
    aws_s3_bucket.mybucket
  ]
  bucket = aws_s3_bucket.mybucket.bucket
  key    = "mypic.jpeg"
  source = "AWS_task2/myimage.jpeg"
  acl    = "public-read"
}



locals {
  s3_origin_id = "S3-${aws_s3_bucket.mybucket.bucket}"
  image_url    = "${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.Upload_image.key}"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [
    aws_instance.myefsOS
  ]
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
  }


  enabled = true


  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_domain_name
    origin_id   = local.s3_origin_id
  }


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }


  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_instance.myefsOS.public_ip
    port        = 22
    private_key = tls_private_key.this.private_key_pem
    
  }


  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<!DOCTYPE html><html lang='en'><head><!-- Required meta tags --><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1, shrink-to-fit=no'><title>Azeemushan Ali</title><!-- Bootstrap CSS --><link rel='stylesheet' type='text/css' href='assets/css/bootstrap.min.css' ><!-- Fonts --><link rel='stylesheet' type='text/css' href='assets/fonts/font-awesome.min.css'><!-- Icon --><link rel='stylesheet' type='text/css' href='assets/fonts/simple-line-icons.css'><!-- Slicknav --><link rel='stylesheet' type='text/css' href='assets/css/slicknav.css'><!-- Menu CSS --><link rel='stylesheet' type='text/css' href='assets/css/menu_sideslide.css'><!-- Slider CSS --><link rel='stylesheet' type='text/css' href='assets/css/slide-style.css'><!-- Nivo Lightbox --><link rel='stylesheet' type='text/css' href='assets/css/nivo-lightbox.css' ><!-- Animate --><link rel='stylesheet' type='text/css' href='assets/css/animate.css'><!-- Main Style --><link rel='stylesheet' type='text/css' href='assets/css/main.css'><!-- Responsive Style --><link rel='stylesheet' type='text/css' href='assets/css/responsive.css'></head><body><!-- About Section Start --><section id='about' class='section-padding'><div class='container'><div class='row'><div class='col-lg-6 col-md-6 col-sm-12 col-xs-12'><div class='img-thumb wow fadeInLeft' data-wow-delay='0.3s'><img class='img-fluid' src='http://${self.domain_name}/${aws_s3_bucket_object.Upload_image.key}' alt=''></div></div> <div class='col-lg-6 col-md-6 col-sm-12 col-xs-12'><div class='profile-wrapper wow fadeInRight' data-wow-delay='0.3s'><h3>Hi Guys! I am Azeemushan Ali</h3><p>I'm Azeemushan Ali, a software developer working in domains of Python,Machine Learning and Cloud. I am involved in various Open Source organizations, spending time on contributing to various projects over GitHub in the form of code. Also, I have some experience in mentoring folks in various Open source programs.I am currently pursuing an undergraduate degree in Computer Science and Engineering, from IMS Engineering College,Ghaziabad.</p><div class='about-profile'><ul class='admin-profile'><li><span class='pro-title'> Name </span> <span class='pro-detail'>Azeemushan Ali</span></li><li><span class='pro-title'> Age </span> <span class='pro-detail'>21 Years</span></li><li><span class='pro-title'> Experience </span> <span class='pro-detail'>Freshers</span></li><li><span class='pro-title'> College </span> <span class='pro-detail'>IMS Engineering College</span></li><li><span class='pro-title'> Stream </span> <span class='pro-detail'>Computer Science</span></li><li><span class='pro-title'> e-mail </span> <span class='pro-detail'>azeemushanali@gmail.com</span></li><li><span class='pro-title'> Phone </span> <span class='pro-detail'>+ 91-8182812338</span></li><li><span class='pro-title'> Open for Jobs </span> <span class='pro-detail'>Available</span></li></ul></div><a href='#' class='btn btn-common'><i class='icon-paper-clip'></i> Download Resume</a><a href='#' class='btn btn-danger'><i class='icon-speech'></i> Contact Me</a></div></div></div></div></section><!-- About Section End --><!-- Go to Top Link --><a href='#' class='back-to-top'><i class='icon-arrow-up'></i></a><!-- jQuery first, then Popper.js, then Bootstrap JS --><script src='assets/js/jquery-min.js'></script><script src='assets/js/popper.min.js'></script><script src='assets/js/bootstrap.min.js'></script><script src='assets/js/jquery.mixitup.js'></script><script src='assets/js/jquery.counterup.min.js'></script><script src='assets/js/waypoints.min.js'></script><script src='assets/js/wow.js'></script><script src='assets/js/jquery.nav.js'></script><script src='assets/js/jquery.easing.min.js'></script>  <script src='assets/js/nivo-lightbox.js'></script><script src='assets/js/jquery.slicknav.js'></script><script src='assets/js/main.js'></script><script src='assets/js/form-validator.min.js'></script><script src='assets/js/contact-form-script.min.js'></script><script src='assets/js/map.js'></script></body></html>\" >> /var/www/html/test.html",
      "EOF"
    ]
  }
}


output "myoutput" {
  value = "http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.Upload_image.key}"
}
