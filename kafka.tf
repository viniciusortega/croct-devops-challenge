locals {
  #Base config
  strimzi_docker_image           = "quay.io/strimzi/kafka:0.34.0-kafka-3.4.0"
  kafka_namespace                = "application"

  #Kafka K8S resource names
  kafka_cluster_name             = "kafka-default-cluster"
  kafka_topic_name               = "kafka-default-topic"
  kafka_producer_job_name        = "kafka-producer-job"
  kafka_consumer_deployment_name = "kafka-console-consumer"
  kafka_producer_input_file_name = "kafka-producer-input-file"
  kafka_config_name              = "kafka-config"

  #Kafka servers
  kafka_bootstrap_server         = "${local.kafka_cluster_name}-kafka-bootstrap:9092"
  kafka_zookeeper_server         = "${local.kafka_cluster_name}-zookeeper:2181"
  
  enable_recreate_job_to_update_configmap  = false
}



resource "kubernetes_manifest" "kafka_cluster" {
  manifest = yamldecode( <<-EOF
    apiVersion: kafka.strimzi.io/v1beta2
    kind: Kafka
    metadata:
      name: ${local.kafka_cluster_name}
      namespace: ${local.kafka_namespace}
    spec:
      kafka:
        replicas: 1
        listeners:
          - name: plain
            port: 9092
            type: internal
            tls: false
        storage:
          type: jbod
          volumes:
          - id: 0
            type: persistent-claim
            size: 1Gi
            deleteClaim: false
        config:
          offsets.topic.replication.factor: 1
          transaction.state.log.replication.factor: 1
          transaction.state.log.min.isr: 1
          default.replication.factor: 1
          min.insync.replicas: 1
      zookeeper:
        replicas: 1
        storage:
          type: persistent-claim
          size: 1Gi
          deleteClaim: false
      entityOperator:
        topicOperator: {}
        userOperator: {}
    EOF
  )
  depends_on = [
    kubernetes_namespace.application,
    helm_release.strimzi
  ]
}

resource "kubernetes_manifest" "kafka_topic" {
  manifest = yamldecode( <<-EOF
    apiVersion: kafka.strimzi.io/v1beta2
    kind: KafkaTopic
    metadata:
      name: ${local.kafka_topic_name}
      namespace: ${local.kafka_namespace}
      labels:
        strimzi.io/cluster: "${local.kafka_cluster_name}"
    spec:
      partitions: 1
      replicas: 1
    EOF
  )
  depends_on = [
    kubernetes_manifest.kafka_cluster
  ]
}

resource "kubernetes_manifest" "kafka_producer_input_file" {
  manifest = yamldecode( <<-EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${local.kafka_producer_input_file_name}
      namespace: ${local.kafka_namespace}
    data:
      inputfile.txt: |
        this
        is a
        example message
    EOF
  )
}

resource "null_resource" "check_configmap_update" {
  count = local.enable_recreate_job_to_update_configmap ? 1 : 0
  triggers = {
    shoot_id = kubernetes_manifest.kafka_producer_input_file.manifest.data["inputfile.txt"]
  }

  provisioner "local-exec" {
    command = <<EOT
      # Taint resource
      echo "Tainting resource: kubernetes_manifest.kafka_producer_perf_test_job"
      terraform taint -lock=false kubernetes_manifest.kafka_producer_perf_test_job > /dev/null 2>&1
      
      # Execute terraform apply
      echo "Applying changes..."
      terraform apply -lock=false -target kubernetes_manifest.kafka_producer_perf_test_job -auto-approve > /dev/null 2>&1
    EOT
  }
  depends_on = [
    kubernetes_manifest.kafka_producer_input_file,
    kubernetes_manifest.kafka_producer_perf_test_job
  ]
}

resource "kubernetes_manifest" "kafka_broker_config" {
  manifest = yamldecode( <<-EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${local.kafka_config_name}
      namespace: ${local.kafka_namespace}
    data:
      server.properties: |-
        broker.id=0
        listeners=PLAINTEXT://${local.kafka_bootstrap_server}
        log.dirs=/var/lib/kafka/data
        zookeeper.connect=${local.kafka_zookeeper_server}
    EOF
  )
}

resource "kubernetes_manifest" "kafka_producer_perf_test_job" {
  manifest = yamldecode( <<-EOF
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: ${local.kafka_producer_job_name}
      namespace: ${local.kafka_namespace}
    spec:
      template:
        spec:
          initContainers:
            - name: wait-for-kafka
              image: ${local.strimzi_docker_image}
              command:
                - sh
                - -c
                - |
                  #!/bin/bash
                  set -e
                  until bin/kafka-broker-api-versions.sh --bootstrap-server ${local.kafka_bootstrap_server}; do
                    echo "Waiting for Kafka to be ready..."
                    sleep 1
                  done
              volumeMounts:
                - name: ${local.kafka_config_name}
                  mountPath: /opt/kafka/config
          containers:
            - name: kafka-producer
              image: ${local.strimzi_docker_image}
              command:
                - sh
                - -c
                - "bin/kafka-console-producer.sh --bootstrap-server ${local.kafka_bootstrap_server} --topic ${local.kafka_topic_name} < /inputfile.txt"
              volumeMounts:
                - name: ${local.kafka_producer_input_file_name}
                  mountPath: /inputfile.txt
                  subPath: inputfile.txt
          restartPolicy: Never
          volumes:
            - name: ${local.kafka_producer_input_file_name}
              configMap:
                name: ${local.kafka_producer_input_file_name}
            - name: ${local.kafka_config_name}
              configMap:
                name: ${local.kafka_config_name}
      backoffLimit: 4
    EOF
  )
  depends_on = [
    kubernetes_manifest.kafka_producer_input_file,
    kubernetes_manifest.kafka_broker_config
  ]
}

resource "kubernetes_manifest" "kafka_console_consumer" {
  manifest = yamldecode( <<-EOF
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: ${local.kafka_consumer_deployment_name}
      namespace: ${local.kafka_namespace}
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: ${local.kafka_consumer_deployment_name}
      template:
        metadata:
          labels:
            app: ${local.kafka_consumer_deployment_name}
        spec:
          initContainers:
            - name: wait-for-kafka
              image: ${local.strimzi_docker_image}
              command:
                - sh
                - -c
                - |
                  #!/bin/bash
                  set -e
                  until bin/kafka-broker-api-versions.sh --bootstrap-server ${local.kafka_bootstrap_server}; do
                    echo "Waiting for Kafka to be ready..."
                    sleep 1
                  done
              volumeMounts:
                - name: ${local.kafka_config_name}
                  mountPath: /opt/kafka/config
          containers:
            - name: ${local.kafka_consumer_deployment_name}
              image: ${local.strimzi_docker_image}
              command: ["bin/kafka-console-consumer.sh"]
              args: ["--bootstrap-server", "${local.kafka_bootstrap_server}", "--topic", "${local.kafka_topic_name}", "--from-beginning"]
          restartPolicy: Always
          volumes:
            - name: ${local.kafka_config_name}
              configMap:
                name: ${local.kafka_config_name}
    EOF
  )
}