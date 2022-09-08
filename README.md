# Progressive Delivery in Amazon EKS using Argo Rollouts

## Prerequisites

* An active AWS account.
* AWS Command Line Interface (AWS CLI), installed and configured. For more information about this, see Installing, updating, and uninstalling the AWS CLI in the AWS CLI documentation.
* Terraform installed on your local machine. For more information about this, see the Terraform documentation. 
* kubectl
* eksctl
* helm

## Setup

### Create EKS Cluster and its dependencies (VPC etc)


For simplicity, we will not cover basics of best practices when deploying resources via Terraform. Please see check this [link](https://www.terraform.io/language/settings/backends/s3) for remote state management.


```
terraform init
terraform plan
terraform apply -auto-approve
```
### Install App Mesh Controller


#### Add helm repo for App Mesh


```
helm repo add eks https://aws.github.io/eks-charts
```

#### Create a namespace


```
kubectl create ns appmesh-system
```

#### Install App Mesh CRDs

```
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"
```

```
kubectl apply -k "github.com/aws/eks-charts/stable/appmesh-controller//crds?ref=master"
```

#### Create your OIDC identity provider for the cluster



`kubectl create ns appmesh-system`

#### Set your local environment variables

```
export CLUSTER_NAME=eks-argo-rollouts
export AWS_REGION=ap-southeast-1
export ACCOUNT_ID=REPLACE_ME
```

#### Create your OIDC identity provider for the cluster


```
  eksctl utils associate-iam-oidc-provider \
    --region=$AWS_REGION \
    --cluster $CLUSTER_NAME \
    --approve
```

#### Create an IAM role for the appmesh-controller service account

Replace `$ACCOUNT_ID` with the AWS Account ID your cluster is running in.

Create role and bind to appmesh-controller Kubernetes service account:

```
eksctl create iamserviceaccount \
    --cluster $CLUSTER_NAME \
    --namespace appmesh-system \
    --name appmesh-controller \
    --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve
```
#### Deploy app mesh controller

```
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller
```

#### Create the App Mesh and namespace

```
kubectl apply -f examples/mesh.yaml
```

#### Create an IAM Policy for Envoy proxy

```
aws iam create-policy \
    --policy-name DevEnvoyNamespaceIAMPolicy \
    --policy-document file://envoy-iam-policy.json
```

```
eksctl create iamserviceaccount --cluster eks-argo-rollouts \
  --namespace app \
  --name app-envoy-proxies \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/DevEnvoyNamespaceIAMPolicy \
  --override-existing-serviceaccounts \
  --approve 
```

---
### Install Appmesh Prometheus

```
helm repo add eks https://aws.github.io/eks-charts

helm upgrade -i appmesh-prometheus eks/appmesh-prometheus \
--namespace appmesh-system
```

<!-- ```
helm upgrade -i appmesh-prometheus eks/appmesh-prometheus \
--namespace appmesh-system \
--set retention=12h \
--set persistentVolumeClaim.claimName=prometheus
``` -->


### Install Grafana

```
helm repo add grafana https://grafana.github.io/helm-charts
cat << EoF > grafana.yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.prometheus.svc.cluster.local
      access: proxy
      isDefault: true
```

```
kubectl create namespace grafana
```

```
helm install grafana grafana/grafana \
    --namespace grafana \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='digidemo' \
    --values grafana.yaml \
    --set service.type=LoadBalancer
```

To access grafana:
```
export ELB=$(kubectl get svc -n grafana grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$ELB"
```

Import the dashboard provided from dashboards/dashboard.json

#### Setup Grafana

Get Grafana password:
```
kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Launch Grafana UI:
```
kubectl -n grafana port-forward svc/grafana 3000:80
```
Login with the below credentials

```
Username: admin
Password: Value from previous step
```
Follow the steps to import sample dashboard

* Import the dashboard provided from monitoring/dashboard.json
* Create Datasource for Appmesh prometheus:
* Click Add data source -> Prometheus
* Set url to: http://appmesh-prometheus.appmesh-system.svc.cluster.local:9090
* Set it to default data source.
* Click save and test.

### Build Docker image and push to ECR

Login to ECR
```
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```


Push the stable version of the sample app:
```
cd app/v1/demo-app
docker build --platform=linux/amd64 -t demo-app .
docker tag demo-app:latest ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v1.0.0
docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v1.0.0
```

Push the unstable version of the sample app:
```
cd app/v2/demo-app
docker build --platform=linux/amd64 -t demo-app .
docker tag demo-app:latest ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v2.0.0
docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v2.0.0
```

Push the fixed version of the sample app:
```
cd app/v2-fix/demo-app
docker build --platform=linux/amd64 -t demo-app .
docker tag demo-app:latest ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v2.0.1
docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v2.0.1
```

---
### Blue/Green Deployment

Create the rollout object

```
kubectl apply -f examples/blue-green/rollout.yaml
```

Create the App mesh logical constructs

```
kubectl apply -f examples/blue-green/meshed_app.yaml
```

Create the virtual gateway expose the API endpoint outside the cluster

```
kubectl apply -f examples/virtual_gateway.yaml
```

### Canary Deployment


Create the rollout object

```
kubectl apply -f examples/canary/rollout.yaml
```

Create the App mesh logical constructs

```
kubectl apply -f examples/canary/meshed_app.yaml
```

Create the virtual gateway expose the API endpoint outside the cluster

```
kubectl apply -f examples/virtual_gateway.yaml
```

---

## Clean up

```
terraform destroy -auto-approve
```

This should take up to 10 minutes.

---

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
