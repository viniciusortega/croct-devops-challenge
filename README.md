# croct-devops-challenge

## Challenge
The task is create a Terraform module to deploy a Kafka cluster, a consumer and a producer on an existing Kubernetes cluster using the Strimzi Kafka operator.

## Used Tecnologies
- **Minikube (Kubernetes)** -> v1.29.0
- **Helm** -> v2.9.0
- **Terraform** -> v1.4.4

## Prerequisites

To run this project, you will first need to have a Minikube K8S Cluster running. To install and run it, you can follow the [Minikube Tutorial](https://minikube.sigs.k8s.io/docs/start/).

    :warning: To be able to use Minikube, [Docker](https://docs.docker.com/engine/install/ubuntu/) must be properly installed.

You must also install Terraform. Simply follow the official step-by-step guide from [Hashicorp Terraform](https://developer.hashicorp.com/terraform/downloads). Remember that the version used in this challenge was v1.4.4, and previous or later versions may impact the project's functionality.

## Usage

To use this project, follow these steps:

1. Clone the repository:
```bash
git clone https://github.com/viniciusortega/croct-devops-challenge.git
```

2. Change into the project directory:
```bash
cd croct-devops-challenge
```

3. Guarantee the Kubernetes context:
```bash
kubectl config use-context minikube
```
3. Initialize Terraform:
```bash
terraform init
```

4. Apply the Terraform configuration:

```bash
terraform apply
```

This will create a Strimzi Operator, Kafka cluster, Kafka topic, producer job, and the consumer deployment along with their dependencies. The producer job uses the Kafka producer to publish messages to a specified topic.


## Configuration

The following locals can be configured in the `kafka.tf` file:

| Name | Description | Default |
|------|-------------|---------|
| `strimzi_docker_image` | The Strimzi Kafka Docker image to use | `quay.io/strimzi/kafka:0.24.0-kafka-2.8.0` |
| `kafka_namespace` | The namespace in which to deploy Kafka | `"kafka"` |
| `kafka_cluster_name` | The name of the Kafka cluster | `"my-kafka-cluster"` |
| `kafka_topic_name` | The name of the Kafka topic | `"my-kafka-topic"` |
| `kafka_producer_job_name` | The name of the Kafka producer job | `"my-kafka-producer-job"` |
| `kafka_consumer_deployment_name` | The name of the Kafka consumer deployment | `"my-kafka-consumer-deployment"` |
| `kafka_producer_input_file_name` | The name of the file containing the Kafka producer input | `"producer-input-file.txt"` |
| `kafka_config_name` | The name of the Kafka ConfigMap | `"my-kafka-config"` |
| `kafka_bootstrap_server` | The Kafka bootstrap server URL | `"${local.kafka_cluster_name}-kafka-bootstrap:9092"` |
| `kafka_zookeeper_server` | The Kafka ZooKeeper server URL | `"${local.kafka_cluster_name}-zookeeper:2181"` |

## Contributing

Pull requests are welcome. For major changes, please open an issue first
to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License

[MIT](https://choosealicense.com/licenses/mit/)