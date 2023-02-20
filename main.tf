provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks_blueprints.eks_cluster_id
}

data "aws_availability_zones" "available" {}

locals {
  name         = basename(path.cwd)
  cluster_name = coalesce(var.cluster_name, local.name)
  region       = "eu-west-1"

  mesh_name = "my-app-mesh"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.17.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.23"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  managed_node_groups = {
    mg_5 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["m5.large"]
      min_size        = 2
      subnet_ids      = module.vpc.private_subnets
    }
  }
}

module "eks_blueprints_kubernetes_addons" {
  #source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.17.0"
  source = "github.com/allamand/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=appmesh-prometheus"
  #source = "/home/ubuntu/environment/eks/terraform/terraform-aws-eks-blueprints/modules/kubernetes-addons"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_vpc_cni            = true
  enable_amazon_eks_coredns            = true
  enable_amazon_eks_kube_proxy         = true
  enable_amazon_eks_aws_ebs_csi_driver = true

  # Add-ons
  enable_aws_load_balancer_controller = false
  enable_aws_cloudwatch_metrics       = false
  enable_aws_for_fluentbit            = false
  enable_cert_manager                 = false
  enable_cluster_autoscaler           = false
  enable_ingress_nginx                = false

  enable_keda               = false
  enable_metrics_server     = true
  enable_prometheus         = true
  enable_traefik            = false
  enable_vpa                = false
  enable_yunikorn           = false
  enable_argo_rollouts      = true
  enable_grafana            = true
  enable_appmesh_controller = true
  enable_appmesh_prometheus = true
}

#The namespace need to exist to create IRSA service accounts
module "irsa_app_envoy_proxies" {
  source                      = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.17.0"
  kubernetes_namespace        = "app"
  create_kubernetes_namespace = true
  kubernetes_service_account  = "app-envoy-proxies"
  irsa_iam_policies           = [aws_iam_policy.appmesh_envoy.arn]
  eks_cluster_id              = module.eks_blueprints.eks_cluster_id
  eks_oidc_provider_arn       = module.eks_blueprints.eks_oidc_provider_arn

  depends_on = [module.eks_blueprints_kubernetes_addons]
}

resource "aws_iam_policy" "appmesh_envoy" {
  name_prefix = "appmesh-envoy"
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "appmesh:StreamAggregatedResources",
              "appmesh:*",
              "xray:*"
          ],
          "Resource": "*"
      },
      {
          "Effect": "Allow",
          "Action": [
              "acm:ExportCertificate",
              "acm-pca:GetCertificateAuthorityCertificate"
          ],
          "Resource": "*"
      },
      {
        "Action": [
          "logs:*"
        ],
        "Effect": "Allow",
        "Resource": "*"
      }
  ]
}
  POLICY
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

#---------------------------------------------------------------
# ECR Resources
#---------------------------------------------------------------

resource "aws_ecr_repository" "demo_app" {
  name                 = "demo-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "app"
    labels = {
      mesh                                     = local.mesh_name
      gateway                                  = "ingress-gw"
      "appmesh.k8s.aws/sidecarInjectorWebhook" = "enabled"
    }
  }

  timeouts {
    delete = "15m"
  }
}
