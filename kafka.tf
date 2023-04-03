resource "kubernetes_manifest" "kafka_cluster" {
  manifest = yamldecode( <<-EOF
    apiVersion: kafka.strimzi.io/v1beta2
    kind: Kafka
    metadata:
      name: kafka-default-cluster
      namespace: application
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
      name: kafka-default-topic
      namespace: application
      labels:
        strimzi.io/cluster: "kafka-default-cluster"
    spec:
      partitions: 3
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
      name: kafka-producer-input-file
      namespace: application
    data:
      inputfile.txt: |
        this
        is a
        example message
    EOF
  )
}

resource "kubernetes_manifest" "kafka_broker_config" {
  manifest = yamldecode( <<-EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: kafka-config
      namespace: application
    data:
      server.properties: |-
        broker.id=0
        listeners=PLAINTEXT://kafka-default-cluster-kafka:9092
        log.dirs=/var/lib/kafka/data
        zookeeper.connect=kafka-default-cluster-zookeeper:2181
    EOF
  )
}

resource "kubernetes_manifest" "kafka_producer_perf_test_job" {
  manifest = yamldecode( <<-EOF
    apiVersion: batch/v1
    kind: Job
    metadata:
      name: kafka-producer-job
      namespace: application
    spec:
      template:
        spec:
          initContainers:
            - name: wait-for-kafka
              image: quay.io/strimzi/kafka:0.34.0-kafka-3.4.0
              command:
                - sh
                - -c
                - |
                  #!/bin/bash
                  set -e
                  until bin/kafka-broker-api-versions.sh --bootstrap-server kafka-default-cluster-kafka-bootstrap:9092; do
                    echo "Waiting for Kafka to be ready..."
                    sleep 1
                  done
              volumeMounts:
                - name: kafka-config
                  mountPath: /opt/kafka/config
          containers:
            - name: kafka-producer
              image: quay.io/strimzi/kafka:0.34.0-kafka-3.4.0
              command:
                - sh
                - -c
                - "bin/kafka-console-producer.sh --bootstrap-server kafka-default-cluster-kafka-bootstrap:9092 --topic kafka-default-topic < /inputfile.txt"
              volumeMounts:
                - name: inputfile
                  mountPath: /inputfile.txt
                  subPath: inputfile.txt
          restartPolicy: Never
          volumes:
            - name: inputfile
              configMap:
                name: kafka-producer-input-file
            - name: kafka-config
              configMap:
                name: kafka-config
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
      name: kafka-console-consumer
      namespace: application
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: kafka-console-consumer
      template:
        metadata:
          labels:
            app: kafka-console-consumer
        spec:
          initContainers:
            - name: wait-for-kafka
              image: quay.io/strimzi/kafka:0.34.0-kafka-3.4.0
              command:
                - sh
                - -c
                - |
                  #!/bin/bash
                  set -e
                  until bin/kafka-broker-api-versions.sh --bootstrap-server kafka-default-cluster-kafka-bootstrap:9092; do
                    echo "Waiting for Kafka to be ready..."
                    sleep 1
                  done
              volumeMounts:
                - name: kafka-config
                  mountPath: /opt/kafka/config
          containers:
            - name: kafka-console-consumer
              image: quay.io/strimzi/kafka:0.34.0-kafka-3.4.0
              command: ["bin/kafka-console-consumer.sh"]
              args: ["--bootstrap-server", "kafka-default-cluster-kafka-bootstrap:9092", "--topic", "kafka-default-topic", "--from-beginning"]
          restartPolicy: Always
          volumes:
            - name: kafka-config
              configMap:
                name: kafka-config
    EOF
  )
}