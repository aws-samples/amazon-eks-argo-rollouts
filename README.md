# Progressive Delivery in Amazon EKS using Argo Rollouts

## Prerequisites

- An active AWS account.
- AWS Command Line Interface (AWS CLI), installed and configured. For more information about this, see Installing, updating, and uninstalling the AWS CLI in the AWS CLI documentation.
- Terraform installed on your local machine. For more information about this, see the Terraform documentation.
- kubectl
- eksctl
- helm

## Setup

### Create EKS Cluster and its dependencies (VPC etc)

For simplicity, we will not cover basics of best practices when deploying resources via Terraform. Please see check this [link](https://www.terraform.io/language/settings/backends/s3) for remote state management.

```
terraform init
terraform plan
terraform apply -auto-approve
```

### Set your local environment variables

```
export CLUSTER_NAME=eks-argo-rollouts
export ACCOUNT_ID=<YOUR AWS ACCOUNT ID>
export AWS_REGION=ap-southeast-1
```

### Create the App Mesh and namespace

```
kubectl apply -f examples/mesh.yaml
```

### Create the virtual gateway expose the API endpoint outside the cluster

```
kubectl apply -f examples/virtual_gateway.yaml
```

#### Setup Grafana

Grafana has been installed as part of the Terraform module, so we will need to get the password and import the dashboard.

Get Grafana password:

```
kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Launch Grafana UI:

```
kubectl -n grafana port-forward svc/grafana 3000:80
```

Login with the below credentials:

```
Username: admin
Password: Value from previous step
```

Follow the steps to import sample dashboard

- Import the dashboard provided from monitoring/dashboard.json
- Create Datasource for Appmesh prometheus:
- Click Add data source -> Prometheus
- Set url to: http://appmesh-prometheus.appmesh-system.svc.cluster.local:9090
- Set it to default data source.
- Click save and test.

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

Create the App mesh logical constructs

```
kubectl apply -f examples/blue-green/meshed_app.yaml
```

Create the Analysis template

```
kubectl apply -f examples/blue-green/analysis-template.yaml
```

Create the rollout object

```
envsubst < examples/blue-green/rollout.yaml | kubectl apply -f -
```

### Canary Deployment

Create the App mesh logical constructs

```
kubectl apply -f examples/canary/meshed_app.yaml
```

Create the Analysis objects

```
kubectl apply -f examples/canary/analysis_template.yaml
```

Create the rollout object

```
envsubst < examples/canary/rollout.yaml | kubectl apply -f -
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

docker build app/v3/demo-app --platform=linux/amd64 -t demo-app
docker tag demo-app:latest ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v3.0.0
docker push ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/demo-app:v3.0.0
