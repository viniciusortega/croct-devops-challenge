resource "kubernetes_manifest" "kafka_cluster" {
  manifest = yamldecode( <<-EOF
    apiVersion: kafka.strimzi.io/v1beta2
    kind: Kafka
    metadata:
      name: kafka-default-cluster
      namespace: application
    spec:
      kafka:
        replicas: 3
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
            size: 100Gi
            deleteClaim: false
        config:
          offsets.topic.replication.factor: 1
          transaction.state.log.replication.factor: 1
          transaction.state.log.min.isr: 1
          default.replication.factor: 3
          min.insync.replicas: 2
      zookeeper:
        replicas: 3
        storage:
          type: persistent-claim
          size: 100Gi
          deleteClaim: false
      entityOperator:
        topicOperator: {}
        userOperator: {}
    EOF
  )
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
}

resource "kubernetes_manifest" "kafka_internal_svc" {
  manifest = yamldecode( <<-EOF
    apiVersion: v1
    kind: Service
    metadata:
      name: kafka-cluster-internal-svc
      namespace: application
    spec:
      selector:
        strimzi.io/cluster: kafka-default-cluster
        strimzi.io/kind: Kafka
      ports:
        - name: kafka
          port: 9092
          protocol: TCP
          targetPort: 9092
      type: ClusterIP
    EOF
  )
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
          containers:
            - name: kafka-producer
              image: quay.io/strimzi/kafka:0.34.0-kafka-3.4.0
              command:
                - sh
                - -c
                - "bin/kafka-console-producer.sh --bootstrap-server kafka-cluster-internal-svc:9092 --topic kafka-default-topic < /inputfile.txt"
              volumeMounts:
                - name: inputfile
                  mountPath: /inputfile.txt
                  subPath: inputfile.txt
          restartPolicy: Never
          volumes:
            - name: inputfile
              configMap:
                name: kafka-producer-input-file
      backoffLimit: 4
    EOF
  )
  depends_on = [
    kubernetes_manifest.kafka_producer_input_file
  ]
}